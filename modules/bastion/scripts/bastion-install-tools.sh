#!/bin/bash

set -Eeuo pipefail

LOG_PREFIX="[shoppy-bastion]"
trap 'echo "❌ ${LOG_PREFIX} failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# ----------------------------- configuration ---------------------------------
K8S_MINOR="${K8S_MINOR:-v1.36}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.5}"
KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-latest}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-}"
YQ_VERSION="${YQ_VERSION:-latest}"
K9S_VERSION="${K9S_VERSION:-latest}"
INSTALL_TERRAFORM="${INSTALL_TERRAFORM:-true}"
INSTALL_GH_CLI="${INSTALL_GH_CLI:-true}"
INSTALL_K9S="${INSTALL_K9S:-true}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
AWS_REGION="${AWS_REGION:-}"

# Published signing-key fingerprints (verified before a key is trusted)
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
RUNNER_HOME="$(getent passwd "$RUNNER_USER" | cut -d: -f6)"
[[ -n "$RUNNER_HOME" ]] || die "Cannot resolve home directory of user '$RUNNER_USER'"

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

key_has_fpr() {  # captured first: `| grep -q` under pipefail can false-fail via SIGPIPE
  local fprs
  fprs="$(gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1=="fpr"{print $10}')"
  grep -qx "$2" <<<"$fprs"
}

gh_latest_tag() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'
}

# verify_sha256 <dir> <checksum-file> <artifact-name>
verify_sha256() {
  ( cd "$1" && grep -E "[ *]$3\$" "$2" | sha256sum -c - ) >/dev/null
}

# -----------------------------------------------------------------------------
# 0. SYSTEM UPDATE + BASE PACKAGES
# -----------------------------------------------------------------------------
log "0. System update & prerequisites"
apt_get update
apt_get install ca-certificates curl gnupg lsb-release apt-transport-https

# -----------------------------------------------------------------------------
# 1. FOUNDATION + TROUBLESHOOTING UTILITIES
# -----------------------------------------------------------------------------
log "1. Foundation utilities"
# dnsutils            -> dig (ExternalDNS / Route53 troubleshooting)
# netcat-openbsd, openssl -> connectivity & cert checks (Gateway API / SSL)
# gettext-base        -> envsubst; bash-completion; tmux for long sessions
apt_get install \
  git wget unzip zip tar jq make gettext-base \
  python3 python3-pip python3-venv \
  bash-completion tmux vim htop dnsutils netcat-openbsd openssl
ok "foundation packages present"

# --- yq ---
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
# 2. AWS CLI v2
# -----------------------------------------------------------------------------
log "2. AWS CLI v2"
if have aws && aws --version 2>&1 | grep -q "aws-cli/2"; then
  skip "$(aws --version 2>&1)"
else
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "$WORKDIR/awscliv2.zip"
  unzip -q "$WORKDIR/awscliv2.zip" -d "$WORKDIR"
  $SUDO "$WORKDIR/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
  ok "$(aws --version 2>&1)"
fi

# -----------------------------------------------------------------------------
# 3. KUBECTL (pkgs.k8s.io, pinned minor, held)
# -----------------------------------------------------------------------------
log "3. kubectl (${K8S_MINOR})"
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
  $SUDO apt-mark hold kubectl >/dev/null
  ok "kubectl $(kubectl version --client 2>/dev/null | awk 'NR==1{print $3}')"
fi

# -----------------------------------------------------------------------------
# 4. HELM (fingerprint-verified)
# -----------------------------------------------------------------------------
log "4. Helm"
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
# 5. KUSTOMIZE (standalone; newer than the one built into kubectl)
# -----------------------------------------------------------------------------
log "5. Kustomize"
if have kustomize; then
  skip "kustomize $(kustomize version 2>/dev/null | awk 'NR==1')"
else
  if [[ "$KUSTOMIZE_VERSION" == "latest" ]]; then
    # the repo also tags api/* and kyaml/* releases, so pick the newest kustomize/* one
    KUSTOMIZE_VERSION="$(curl -fsSL 'https://api.github.com/repos/kubernetes-sigs/kustomize/releases?per_page=40' \
      | jq -r '[.[] | select(.tag_name | startswith("kustomize/"))][0].tag_name | sub("^kustomize/";"")')"
    [[ -n "$KUSTOMIZE_VERSION" && "$KUSTOMIZE_VERSION" != "null" ]] \
      || die "Could not resolve latest kustomize release (GitHub API rate limit?). Set KUSTOMIZE_VERSION=v5.x.y"
  fi
  K_BASE="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}"
  K_TGZ="kustomize_${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz"
  curl -fsSL -o "$WORKDIR/$K_TGZ" "${K_BASE}/${K_TGZ}"
  curl -fsSL -o "$WORKDIR/kustomize_checksums.txt" "${K_BASE}/checksums.txt"
  verify_sha256 "$WORKDIR" kustomize_checksums.txt "$K_TGZ" || die "Kustomize checksum verification failed"
  tar -xzf "$WORKDIR/$K_TGZ" -C "$WORKDIR" kustomize
  $SUDO install -m 0755 "$WORKDIR/kustomize" /usr/local/bin/kustomize
  ok "kustomize $(kustomize version 2>/dev/null | awk 'NR==1')"
fi

# -----------------------------------------------------------------------------
# 6. ARGOCD CLI (pinned + SHA-256 verified)
# -----------------------------------------------------------------------------
log "6. ArgoCD CLI (${ARGOCD_VERSION})"
if have argocd; then
  skip "$(argocd version --client 2>/dev/null | awk 'NR==1')"
else
  BASE="https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}"
  BIN="argocd-linux-${ARCH}"
  curl -fsSL -o "$WORKDIR/$BIN" "${BASE}/${BIN}"
  curl -fsSL -o "$WORKDIR/cli_checksums.txt" "${BASE}/cli_checksums.txt"
  verify_sha256 "$WORKDIR" cli_checksums.txt "$BIN" || die "ArgoCD CLI checksum verification failed"
  $SUDO install -m 0755 "$WORKDIR/$BIN" /usr/local/bin/argocd
  ok "$(argocd version --client 2>/dev/null | awk 'NR==1')"
fi

# -----------------------------------------------------------------------------
# 7. TERRAFORM (optional; HashiCorp APT, fingerprint-verified)
# -----------------------------------------------------------------------------
if [[ "$INSTALL_TERRAFORM" == "true" ]]; then
  log "7. Terraform"
  if have terraform; then
    skip "$(terraform version | awk 'NR==1')"
  else
    curl -fsSL https://apt.releases.hashicorp.com/gpg -o "$WORKDIR/hashicorp.gpg"
    key_has_fpr "$WORKDIR/hashicorp.gpg" "$HASHICORP_KEY_ID" \
      || die "HashiCorp GPG fingerprint mismatch (expected $HASHICORP_KEY_ID). See https://www.hashicorp.com/official-packaging-guide"
    gpg --dearmor --yes -o "$WORKDIR/hashicorp.keyring" "$WORKDIR/hashicorp.gpg"
    $SUDO install -m 0644 "$WORKDIR/hashicorp.keyring" /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
      | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    apt_get update
    if [[ -n "$TERRAFORM_VERSION" ]]; then apt_get install "terraform=${TERRAFORM_VERSION}-*"; else apt_get install terraform; fi
    ok "$(terraform version | awk 'NR==1')"
  fi
fi

# -----------------------------------------------------------------------------
# 8. GITHUB CLI (optional — handy for the GitOps repo)
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
# 9. K9S (optional terminal UI for the cluster) — failure here is non-fatal
# -----------------------------------------------------------------------------
install_k9s() {
  [[ "$K9S_VERSION" == "latest" ]] && K9S_VERSION="$(gh_latest_tag derailed/k9s)"
  local base="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}"
  local tgz="k9s_Linux_${ARCH}.tar.gz"
  curl -fsSL -o "$WORKDIR/$tgz" "${base}/${tgz}" || return 1
  curl -fsSL -o "$WORKDIR/k9s_checksums.sha256" "${base}/checksums.sha256" || return 1
  verify_sha256 "$WORKDIR" k9s_checksums.sha256 "$tgz" || { echo "k9s checksum mismatch" >&2; return 1; }
  tar -xzf "$WORKDIR/$tgz" -C "$WORKDIR" k9s || return 1
  $SUDO install -m 0755 "$WORKDIR/k9s" /usr/local/bin/k9s
}
if [[ "$INSTALL_K9S" == "true" ]]; then
  log "9. k9s"
  if have k9s; then skip "k9s"; elif install_k9s; then ok "k9s ${K9S_VERSION}"; else warn "k9s install failed — skipped (not required)"; fi
fi

# -----------------------------------------------------------------------------
# 10. SHELL COMPLETIONS + ALIASES (system-wide)
# -----------------------------------------------------------------------------
log "10. Shell completions & aliases"
$SUDO install -m 0755 -d /etc/bash_completion.d
for tool in kubectl helm kustomize argocd; do
  if have "$tool"; then
    "$tool" completion bash 2>/dev/null | $SUDO tee "/etc/bash_completion.d/${tool}" >/dev/null || true
  fi
done
$SUDO tee /etc/profile.d/shoppy-k8s.sh >/dev/null <<'EOF'
# Shoppy Cart bastion shell helpers
alias k=kubectl
alias kgp='kubectl get pods'
alias kga='kubectl get all'
if [ -n "${BASH_VERSION:-}" ] && type __start_kubectl >/dev/null 2>&1; then
  complete -o default -F __start_kubectl k
fi
EOF
ok "completions for kubectl/helm/kustomize/argocd + alias 'k'"

# 11. Install bash-completion 
sudo apt-get update && sudo apt-get install -y bash-completion
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc

# -----------------------------------------------------------------------------
# 12. FINAL VERIFICATION + VERSION SUMMARY
# -----------------------------------------------------------------------------
show() {  # show <label> <cmd> [args...]  -> first line of the command's output
  local label="$1"; shift
  local out="MISSING ❌"
  if have "$1"; then
    out="$( ( "$@" 2>&1 || true ) | awk 'NR==1' )"
    [[ -n "$out" ]] || out="(installed, no version output)"
  fi
  printf "  %-16s %s\n" "${label}:" "$out"
}

log "12. Final verification & version summary"
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
show dig        dig -v
show openssl    openssl version
show tmux       tmux -V
show aws        aws --version
show kubectl    kubectl version --client
show helm       helm version --short
show kustomize  kustomize version
show argocd     argocd version --client
[[ "$INSTALL_TERRAFORM" == "true" ]] && show terraform terraform version
[[ "$INSTALL_GH_CLI"    == "true" ]] && show gh        gh --version
[[ "$INSTALL_K9S"       == "true" ]] && show k9s       k9s version --short
