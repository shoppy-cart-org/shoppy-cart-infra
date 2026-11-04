#!/bin/bash
set -Eeuo pipefail

ORG_URL="https://github.com/shoppy-cart-org"
RUNNER_NAME="shoppy-cart-runner-01"
RUNNER_LABELS="self-hosted,linux,x64,aws,shoppy-cart"
RUNNER_USER="ubuntu"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

echo "=============================================="
echo " GitHub Actions Runner — Registration"
echo "=============================================="
echo ""
echo "Generate a FRESH token from:"
echo "GitHub Organization > Settings > Actions > Runners > New runner"
echo ""

read -rsp "Paste your fresh registration token: " RUNNER_TOKEN
echo ""

if [[ -z "$RUNNER_TOKEN" ]]; then
    echo "ERROR: Token cannot be empty."
    exit 1
fi

cd "$RUNNER_DIR"

./config.sh --unattended \
    --url "$ORG_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --work "_work"

unset RUNNER_TOKEN

echo ""
echo "Installing systemd service..."
sudo ./svc.sh install "$RUNNER_USER"
sudo ./svc.sh start

echo ""
sudo ./svc.sh status

echo ""
echo "=============================================="
echo " Runner registered and running."
echo " Verify: GitHub org Settings → Actions → Runners"
echo "=============================================="