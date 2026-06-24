#!/usr/bin/env bash
# Print a quick health summary of every component.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

section() { echo; echo "$(_c 6)== $* ==$(_r)"; }

section "cert-manager (${CERT_MANAGER_NAMESPACE})"
kc -n "${CERT_MANAGER_NAMESPACE}" get pods 2>/dev/null || warn "not installed"
kc get clusterissuers 2>/dev/null || true

section "Envoy Gateway (${ENVOY_NAMESPACE})"
kc -n "${ENVOY_NAMESPACE}" get pods 2>/dev/null || warn "not installed"
kc get gatewayclass 2>/dev/null || true

section "kagent (${KAGENT_NAMESPACE})"
kc -n "${KAGENT_NAMESPACE}" get pods 2>/dev/null || warn "not installed"
kc -n "${KAGENT_NAMESPACE}" get modelconfig,agent 2>/dev/null || true

section "OpenClaw (${OPENCLAW_NAMESPACE})"
kc -n "${OPENCLAW_NAMESPACE}" get pods,svc,pvc 2>/dev/null || warn "not installed"
kc -n "${OPENCLAW_NAMESPACE}" get gateway,httproute,certificate 2>/dev/null || true

LB_IP="$(gateway_lb_ip "${OPENCLAW_NAMESPACE}" openclaw-gateway)"
if [[ -n "${LB_IP}" ]]; then
  section "Access"
  echo "OpenClaw URL: https://openclaw.${LB_IP}.nip.io/"
fi
