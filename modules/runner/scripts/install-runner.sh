#!/bin/bash
set -Eeuo pipefail

RUNNER_VERSION="2.338.2"
RUNNER_USER="ubuntu"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"
RUNNER_ARCHIVE="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_ARCHIVE}"
RUNNER_SHA256="baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40"

echo "=============================================="
echo " GitHub Actions Runner — Installation"
echo "=============================================="

# Checks
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Do not run as root."
    exit 1
fi

if [[ "$(id -un)" != "$RUNNER_USER" ]]; then
    echo "ERROR: Must run as $RUNNER_USER."
    exit 1
fi

# Install dependencies
sudo apt-get update
sudo apt-get install -y curl ca-certificates tar gzip jq unzip

# Create runner directory
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download runner
echo "Downloading runner v${RUNNER_VERSION}..."
curl --fail --location "$RUNNER_URL" --output "$RUNNER_ARCHIVE"

# Verify checksum
echo "${RUNNER_SHA256}  ${RUNNER_ARCHIVE}" | sha256sum --check
echo "Checksum verified."

# Extract
tar -xzf "$RUNNER_ARCHIVE"
rm "$RUNNER_ARCHIVE"

# Install runner dependencies
sudo ./bin/installdependencies.sh

chown -R "${RUNNER_USER}:${RUNNER_USER}" "$RUNNER_DIR"

echo "=============================================="
echo " Runner binary installed."
echo " Next: run register-runner.sh manually"
echo "=============================================="