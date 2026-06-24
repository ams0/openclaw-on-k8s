#!/usr/bin/env bash
# Deploy OpenClaw via the local Helm chart (not yet exposed externally).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[[ -n "${ANTHROPIC_API_KEY:-}" ]] || die "ANTHROPIC_API_KEY is required for OpenClaw"

ensure_ns "${OPENCLAW_NAMESPACE}"

# Generate (and reuse) a stable gateway token for the Control UI login.
TOKEN_FILE="${REPO_ROOT}/.openclaw-gateway-token"
if [[ -f "${TOKEN_FILE}" ]]; then
  GATEWAY_TOKEN="$(cat "${TOKEN_FILE}")"
else
  GATEWAY_TOKEN="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 40)"
  printf '%s' "${GATEWAY_TOKEN}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
fi
info "Gateway token stored in ${TOKEN_FILE}"

info "Installing OpenClaw chart (release: ${OPENCLAW_RELEASE})"
helmc upgrade --install "${OPENCLAW_RELEASE}" "${REPO_ROOT}/charts/openclaw" \
  --namespace "${OPENCLAW_NAMESPACE}" --create-namespace \
  --set openclaw.model="${OPENCLAW_MODEL}" \
  --set secrets.anthropicApiKey="${ANTHROPIC_API_KEY}" \
  --set secrets.gatewayToken="${GATEWAY_TOKEN}" \
  --wait --timeout 5m

info "Waiting for rollout"
kc -n "${OPENCLAW_NAMESPACE}" rollout status deploy/"${OPENCLAW_RELEASE}" --timeout=180s

ok "OpenClaw running. Local UI: kubectl -n ${OPENCLAW_NAMESPACE} port-forward svc/${OPENCLAW_RELEASE} 18789:18789"
