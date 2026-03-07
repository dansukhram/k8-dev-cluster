#!/usr/bin/env bash
# ============================================================
# Bootstrap Flux v2 GitOps onto the k8-dev cluster
# Prerequisites:
#   - GITHUB_TOKEN env var set (classic token with repo scope)
#   - kubeconfig file present at repo root
#   - flux CLI installed
# ============================================================
set -euo pipefail

GITHUB_USER="dansukhram"
GITHUB_REPO="k8-dev-cluster"
CLUSTER_PATH="flux/clusters/k8-dev"

export KUBECONFIG="$(pwd)/kubeconfig"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: GITHUB_TOKEN is not set."
  echo "Create a classic token at https://github.com/settings/tokens"
  echo "Required scopes: repo"
  exit 1
fi

echo "==> [1/3] Checking Flux prerequisites..."
flux check --pre

echo "==> [2/3] Bootstrapping Flux on cluster k8-dev..."
flux bootstrap github \
  --owner="${GITHUB_USER}" \
  --repository="${GITHUB_REPO}" \
  --branch=main \
  --path="${CLUSTER_PATH}" \
  --personal \
  --private=false

echo "==> [3/3] Verifying Flux components..."
flux check

echo ""
echo "✅ Flux bootstrapped successfully!"
echo ""
echo "Monitor with:"
echo "  flux get all -A"
echo "  kubectl get pods -n flux-system"
