#!/usr/bin/env bash
# Install cert-manager and the demo self-signed PKI (selfsigned -> CA -> issuer).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

info "Adding jetstack helm repo"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update jetstack >/dev/null

info "Installing cert-manager ${CERT_MANAGER_VERSION}"
helmc upgrade --install cert-manager jetstack/cert-manager \
  --namespace "${CERT_MANAGER_NAMESPACE}" --create-namespace \
  --version "${CERT_MANAGER_VERSION}" \
  -f "${REPO_ROOT}/helm/values/cert-manager.yaml" \
  --wait --timeout 5m

info "Waiting for cert-manager webhook to be ready"
kc -n "${CERT_MANAGER_NAMESPACE}" rollout status deploy/cert-manager-webhook --timeout=180s

info "Applying self-signed ClusterIssuer + CA"
kc apply -f "${REPO_ROOT}/manifests/cert-manager/clusterissuer-selfsigned.yaml"

info "Waiting for the CA certificate to be issued"
kc -n "${CERT_MANAGER_NAMESPACE}" wait --for=condition=Ready certificate/openclaw-ca --timeout=120s

ok "cert-manager ready; ClusterIssuer 'openclaw-ca-issuer' available"
