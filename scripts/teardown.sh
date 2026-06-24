#!/usr/bin/env bash
# Remove everything this demo installs. Reverse order of install.
# Usage: scripts/teardown.sh [--keep-cert-manager] [--yes]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KEEP_CM="false"; ASSUME_YES="false"
for arg in "$@"; do
  case "$arg" in
    --keep-cert-manager) KEEP_CM="true" ;;
    --yes|-y) ASSUME_YES="true" ;;
    *) die "unknown flag: $arg" ;;
  esac
done

if [[ "${ASSUME_YES}" != "true" ]]; then
  read -r -p "This will delete OpenClaw, kagent, Envoy Gateway$([[ ${KEEP_CM} == true ]] || echo ', and cert-manager') from context '${KUBE_CONTEXT}'. Continue? [y/N] " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]] || die "aborted"
fi

info "Removing Gateway + OpenClaw"
kc delete -f "${REPO_ROOT}/manifests/gateway/gateway.yaml" --ignore-not-found
helmc uninstall "${OPENCLAW_RELEASE}" -n "${OPENCLAW_NAMESPACE}" 2>/dev/null || true
kc delete namespace "${OPENCLAW_NAMESPACE}" --ignore-not-found

info "Removing kagent"
kc delete -f "${REPO_ROOT}/manifests/kagent/sample-agent.yaml" --ignore-not-found
helmc uninstall kagent -n "${KAGENT_NAMESPACE}" 2>/dev/null || true
helmc uninstall kagent-crds -n "${KAGENT_NAMESPACE}" 2>/dev/null || true
kc delete namespace "${KAGENT_NAMESPACE}" --ignore-not-found

info "Removing Envoy Gateway"
kc delete -f "${REPO_ROOT}/manifests/gateway/gatewayclass.yaml" --ignore-not-found
helmc uninstall envoy-gateway -n "${ENVOY_NAMESPACE}" 2>/dev/null || true
kc delete namespace "${ENVOY_NAMESPACE}" --ignore-not-found

if [[ "${KEEP_CM}" != "true" ]]; then
  info "Removing cert-manager + issuers"
  kc delete -f "${REPO_ROOT}/manifests/cert-manager/clusterissuer-selfsigned.yaml" --ignore-not-found
  helmc uninstall cert-manager -n "${CERT_MANAGER_NAMESPACE}" 2>/dev/null || true
  kc delete namespace "${CERT_MANAGER_NAMESPACE}" --ignore-not-found
fi

ok "Teardown complete"
