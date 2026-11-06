#!/bin/bash

set -Eeuo pipefail

LOG_PREFIX="[shoppy-runner]"
trap 'echo "❌ ${LOG_PREFIX} failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# ----------------------------- configuration ---------------------------------
K8S_MINOR="${K8S_MINOR:-v1.36}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.5}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-}"
YQ_VERSION="${YQ_VERSION:-latest}"
TFLINT_VERSION="${TFLINT_VERSION:-latest}"
INSTALL_GH_CLI="${INSTALL_GH_CLI:-true}"
INSTALL_SECURITY_TOOLS="${INSTALL_SECURITY_TOOLS:-true}"

# Published signing-key fingerprints (verified before a key is trusted)
DOCKER_KEY_ID="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
HASHICORP_KEY_ID="${HASHICORP_KEY_ID:-D55C0D1AC78A8D8126CB631CFC9CA96ACA026560}"  # rotated Sept 2026
HELM_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"

# ------------------------------- helpers -------------------------------------
log()  { echo -e "\n${LOG_PREFIX} === $* ==="; }
ok()   { echo "  ✅ $*"; }
skip() { echo "  ⏭  $* (already installed)"; }
warn() { echo "  ⚠️  $*"; }
die()  { echo "❌ $*" >&2; exit 1; }
have() { command -v "$1" &>/dev/null; }

if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
RUNNER_USER="${RUNNER_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"

# Non-interactive apt (needrestart on 24.04 otherwise prompts and hangs cloud-init/CI)
apt_get() { $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -y -q "$@"; }

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) AWS_ARCH="x86_64"  ;;
  arm64) AWS_ARCH="aarch64" ;;
  *) die "Unsupported architecture: $ARCH" ;;
esac

CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
[[ "$CODENAME" == "noble" ]] || warn "Written for Ubuntu 24.04 (noble); detected '${CODENAME:-unknown}'."

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Returns 0 if <file> (armored or binary key) contains primary fingerprint <id>.
# (Captured into a variable first: `... | grep -q` under pipefail can false-fail via SIGPIPE.)
key_has_fpr() {
  local fprs
  fprs="$(gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1=="fpr"{print $10}')"
  grep -qx "$2" <<<"$fprs"
}

# Latest GitHub release tag without needing the API (no rate limits / jq).
gh_latest_tag() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'
}

# -----------------------------------------------------------------------------
# 0. SYSTEM UPDATE + BASE PACKAGES
# -----------------------------------------------------------------------------
log "0. System update & prerequisites"
apt_get update
apt_get install ca-certificates curl gnupg lsb-release apt-transport-https

# -----------------------------------------------------------------------------
# 1. FOUNDATION UTILITIES
# -----------------------------------------------------------------------------
log "1. Foundation utilities"
# gettext-base -> envsubst (very common in pipeline templating)
# pipx         -> Ubuntu 24.04 blocks 'pip install' system-wide (PEP 668)
apt_get install \
  git wget unzip zip tar jq make gettext-base \
  python3 python3-pip python3-venv pipx
ok "foundation packages present"

# --- yq (mikefarah) ---
if have yq; then
  skip "yq $(yq --version 2>/dev/null)"
else
  [[ "$YQ_VERSION" == "latest" ]] && YQ_VERSION="$(gh_latest_tag mikefarah/yq)"
  curl -fsSL -o "$WORKDIR/yq" \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}"
  $SUDO install -m 0755 "$WORKDIR/yq" /usr/local/bin/yq
  ok "yq ${YQ_VERSION}"
fi

# -----------------------------------------------------------------------------
# 2. DOCKER ENGINE + BUILDX + COMPOSE
# -----------------------------------------------------------------------------
log "2. Docker"
if have docker && docker compose version &>/dev/null && docker buildx version &>/dev/null; then
  skip "$(docker --version)"
else
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$WORKDIR/docker.asc"
  key_has_fpr "$WORKDIR/docker.asc" "$DOCKER_KEY_ID" \
    || die "Docker GPG fingerprint mismatch (expected $DOCKER_KEY_ID)"
  $SUDO install -m 0644 "$WORKDIR/docker.asc" /etc/apt/keyrings/docker.asc

  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt_get update
  apt_get install docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  ok "$(docker --version)"
fi

# Log rotation: unrotated container logs are the #1 way CI runners fill their disk.
if [[ ! -f /etc/docker/daemon.json ]]; then
  $SUDO install -m 0755 -d /etc/docker
  printf '{\n  "log-driver": "json-file",\n  "log-opts": { "max-size": "50m", "max-file": "3" }\n}\n' \
    | $SUDO tee /etc/docker/daemon.json >/dev/null
  ok "wrote /etc/docker/daemon.json (log rotation)"
fi
$SUDO systemctl enable docker >/dev/null 2>&1 || true
$SUDO systemctl restart docker

# Docker group (NOTE: docker group == root-equivalent on this host; see notes at the end)
if [[ "$RUNNER_USER" != "root" ]]; then
  getent group docker >/dev/null || $SUDO groupadd docker
  if ! id -nG "$RUNNER_USER" | tr ' ' '\n' | grep -qx docker; then
    $SUDO usermod -aG docker "$RUNNER_USER"
    warn "Added ${RUNNER_USER} to the docker group — run 'newgrp docker' or log in again."
  fi
fi

# -----------------------------------------------------------------------------
# 3. AWS CLI v2
# -----------------------------------------------------------------------------
log "3. AWS CLI v2"
if have aws && aws --version 2>&1 | grep -q "aws-cli/2"; then
  skip "$(aws --version 2>&1)"
else
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "$WORKDIR/awscliv2.zip"
  unzip -q "$WORKDIR/awscliv2.zip" -d "$WORKDIR"
  $SUDO "$WORKDIR/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
  ok "$(aws --version 2>&1)"
fi

# -----------------------------------------------------------------------------
# 4. TERRAFORM (HashiCorp APT, fingerprint-verified)
# -----------------------------------------------------------------------------
log "4. Terraform"
if have terraform; then
  skip "$(terraform version | awk 'NR==1')"
else
  curl -fsSL https://apt.releases.hashicorp.com/gpg -o "$WORKDIR/hashicorp.gpg"
  key_has_fpr "$WORKDIR/hashicorp.gpg" "$HASHICORP_KEY_ID" \
    || die "HashiCorp GPG fingerprint mismatch (expected $HASHICORP_KEY_ID). Check https://www.hashicorp.com/official-packaging-guide"
  gpg --dearmor --yes -o "$WORKDIR/hashicorp.keyring" "$WORKDIR/hashicorp.gpg"
  $SUDO install -m 0644 "$WORKDIR/hashicorp.keyring" /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  apt_get update
  if [[ -n "$TERRAFORM_VERSION" ]]; then
    apt_get install "terraform=${TERRAFORM_VERSION}-*"
  else
    apt_get install terraform
  fi
  ok "$(terraform version | awk 'NR==1')"
fi

# -----------------------------------------------------------------------------
# 5. KUBECTL (pkgs.k8s.io, pinned minor, held)
# -----------------------------------------------------------------------------
log "5. kubectl (${K8S_MINOR})"
if have kubectl; then
  KUBECTL_VER="$(kubectl version --client 2>/dev/null | awk 'NR==1{print $3}')"
  skip "kubectl ${KUBECTL_VER}"
  [[ "$KUBECTL_VER" == "${K8S_MINOR}."* ]] \
    || warn "kubectl is ${KUBECTL_VER}, expected ${K8S_MINOR}.x — skew vs EKS must stay within ±1 minor."
else
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
    | gpg --dearmor --yes -o "$WORKDIR/k8s.keyring"
  $SUDO install -m 0644 "$WORKDIR/k8s.keyring" /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
    | $SUDO tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

  apt_get update
  apt_get install kubectl
  $SUDO apt-mark hold kubectl >/dev/null   # keep minor stable across 'apt upgrade'
  ok "kubectl $(kubectl version --client 2>/dev/null | awk 'NR==1{print $3}')"
fi

# -----------------------------------------------------------------------------
# 6. HELM (Buildkite-hosted official apt repo, fingerprint-verified)
# -----------------------------------------------------------------------------
log "6. Helm"
if have helm; then
  skip "helm $(helm version --short)"
else
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey -o "$WORKDIR/helm.gpg"
  key_has_fpr "$WORKDIR/helm.gpg" "$HELM_APT_KEY_ID" \
    || die "Helm GPG fingerprint mismatch — potential key compromise (expected $HELM_APT_KEY_ID)"
  gpg --dearmor --yes -o "$WORKDIR/helm.keyring" "$WORKDIR/helm.gpg"
  $SUDO install -m 0644 "$WORKDIR/helm.keyring" /usr/share/keyrings/helm.gpg

  echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
    | $SUDO tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null

  apt_get update
  apt_get install helm
  ok "helm $(helm version --short)"
fi

# -----------------------------------------------------------------------------
# 7. ARGOCD CLI (pinned release + SHA-256 verified)
# -----------------------------------------------------------------------------
log "7. ArgoCD CLI (${ARGOCD_VERSION})"
if have argocd; then
  skip "$(argocd version --client 2>/dev/null | awk 'NR==1')"
else
  BASE="https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}"
  BIN="argocd-linux-${ARCH}"
  curl -fsSL -o "$WORKDIR/$BIN" "${BASE}/${BIN}"
  curl -fsSL -o "$WORKDIR/cli_checksums.txt" "${BASE}/cli_checksums.txt"
  ( cd "$WORKDIR" && grep " ${BIN}\$" cli_checksums.txt | sha256sum -c - ) \
    || die "ArgoCD CLI checksum verification failed"
  $SUDO install -m 0755 "$WORKDIR/$BIN" /usr/local/bin/argocd
  ok "$(argocd version --client 2>/dev/null | awk 'NR==1')"
fi

# -----------------------------------------------------------------------------
# 8. GITHUB CLI (optional)
# -----------------------------------------------------------------------------
if [[ "$INSTALL_GH_CLI" == "true" ]]; then
  log "8. GitHub CLI"
  if have gh; then
    skip "$(gh --version | awk 'NR==1')"
  else
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    $SUDO chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    apt_get update
    apt_get install gh
    ok "$(gh --version | awk 'NR==1')"
  fi
fi

# -----------------------------------------------------------------------------
# 9. SECURITY / QUALITY SCANNERS (optional): Trivy, TFLint, Checkov
# -----------------------------------------------------------------------------
if [[ "$INSTALL_SECURITY_TOOLS" == "true" ]]; then
  log "9. Security tooling"

  # --- Trivy (official apt repo) ---
  if have trivy; then
    skip "trivy $(trivy --version | awk 'NR==1')"
  else
    curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
      | gpg --dearmor --yes -o "$WORKDIR/trivy.keyring"
    $SUDO install -m 0644 "$WORKDIR/trivy.keyring" /usr/share/keyrings/trivy.gpg
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
      | $SUDO tee /etc/apt/sources.list.d/trivy.list >/dev/null
    apt_get update
    apt_get install trivy
    ok "trivy $(trivy --version | awk 'NR==1')"
  fi

  # --- TFLint (GitHub release + checksums.txt) ---
  if have tflint; then
    skip "$(tflint --version | awk 'NR==1')"
  else
    [[ "$TFLINT_VERSION" == "latest" ]] && TFLINT_VERSION="$(gh_latest_tag terraform-linters/tflint)"
    TF_BASE="https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}"
    TF_ZIP="tflint_linux_${ARCH}.zip"
    curl -fsSL -o "$WORKDIR/$TF_ZIP" "${TF_BASE}/${TF_ZIP}"
    curl -fsSL -o "$WORKDIR/tflint_checksums.txt" "${TF_BASE}/checksums.txt"
    ( cd "$WORKDIR" && grep " ${TF_ZIP}\$" tflint_checksums.txt | sha256sum -c - ) \
      || die "TFLint checksum verification failed"
    unzip -q -o "$WORKDIR/$TF_ZIP" -d "$WORKDIR/tflint-bin"
    $SUDO install -m 0755 "$WORKDIR/tflint-bin/tflint" /usr/local/bin/tflint
    ok "$(tflint --version | awk 'NR==1')"
  fi

  # --- Checkov (isolated via pipx; system pip is blocked by PEP 668) ---
  if have checkov; then
    skip "checkov $(checkov --version 2>/dev/null | awk 'NR==1')"
  else
    $SUDO env PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install checkov
    ok "checkov $(checkov --version 2>/dev/null | awk 'NR==1')"
  fi
fi

# -----------------------------------------------------------------------------
# 10. FINAL VERIFICATION + VERSION SUMMARY
# -----------------------------------------------------------------------------
# show <label> <cmd> [args...]  -> prints the first line of the command's output
show() {
  local label="$1"; shift
  local out="MISSING ❌"
  if have "$1"; then
    out="$( ( "$@" 2>&1 || true ) | awk 'NR==1' )"
    [[ -n "$out" ]] || out="(installed, no version output)"
  fi
  printf "  %-16s %s\n" "${label}:" "$out"
}

log "10. Final verification & version summary"
echo "===================================================="
echo "  INSTALLED TOOL VERSIONS"
echo "===================================================="
show git        git --version
show curl       curl --version
show wget       wget --version
show unzip      unzip -v
show jq         jq --version
show yq         yq --version
show make       make --version
show envsubst   envsubst --version
show python3    python3 --version
show pip3       pip3 --version
show pipx       pipx --version
show docker     docker --version
if have docker; then
  show compose  docker compose version
  show buildx   docker buildx version
fi
show aws        aws --version
show terraform  terraform version
show kubectl    kubectl version --client
show helm       helm version --short
show argocd     argocd version --client
[[ "$INSTALL_GH_CLI" == "true" ]]          && show gh      gh --version
if [[ "$INSTALL_SECURITY_TOOLS" == "true" ]]; then
  show trivy    trivy --version
  show tflint   tflint --version
  show checkov  checkov --version
fi

echo ""
printf "  %-16s %s\n" "docker daemon:" "$($SUDO systemctl is-active docker 2>/dev/null || echo unknown)"
