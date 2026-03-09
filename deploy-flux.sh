#!/usr/bin/env bash
#
# Deploy FluxCD to a Kubernetes cluster using release manifests.
# This script installs Flux without requiring the Flux CLI.
#
# Requirements:
#   - kubectl configured to point at the target cluster
#   - Network access to GitHub releases
#
# Usage:
#   deploy-flux.sh [--version vX.Y.Z] [--namespace flux-system]
#

set -euo pipefail

FLUX_VERSION_DEFAULT="v2.2.3"
NAMESPACE_DEFAULT="flux-system"

FLUX_VERSION="${FLUX_VERSION_DEFAULT}"
NAMESPACE="${NAMESPACE_DEFAULT}"

usage() {
  cat <<EOF
Usage: $0 [--version vX.Y.Z] [--namespace NAME]

Options:
  --version    FluxCD version to install (default: ${FLUX_VERSION_DEFAULT})
  --namespace  Kubernetes namespace to install Flux into (default: ${NAMESPACE_DEFAULT})
  -h, --help   Show this help message and exit
EOF
}

# Simple argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Error: --version requires a value" >&2
        usage
        exit 1
      fi
      FLUX_VERSION="$2"
      shift 2
      ;;
    --namespace)
      if [[ $# -lt 2 ]]; then
        echo "Error: --namespace requires a value" >&2
        usage
        exit 1
      fi
      NAMESPACE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

FLUX_URL="https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/install.yaml"

echo "Deploying FluxCD ${FLUX_VERSION} to namespace '${NAMESPACE}' using:"
echo "  ${FLUX_URL}"
echo

# Ensure namespace exists (idempotent)
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || \
  kubectl create namespace "${NAMESPACE}"

# Apply Flux installation manifests
echo "kubectl apply -n ${NAMESPACE} -f ${FLUX_URL}"
sleep 10
kubectl apply -n "${NAMESPACE}" -f "${FLUX_URL}"

echo
echo "FluxCD manifests applied. Waiting for controllers to become ready in namespace '${NAMESPACE}'..."

kubectl wait \
  --for=condition=ready pod \
  -l app.kubernetes.io/part-of=flux \
  -n "${NAMESPACE}" \
  --timeout=5m

echo
echo "FluxCD deployment completed successfully."

echo
echo "To verify the installation, run:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo
echo "To inspect Flux components, you can run for example:"
echo "  kubectl get deployments -n ${NAMESPACE}"
