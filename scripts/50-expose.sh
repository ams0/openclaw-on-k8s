#!/usr/bin/env bash
# Publish OpenClaw through Envoy Gateway with a cert-manager TLS cert.
# Creates the Gateway, waits for its LoadBalancer IP, derives a nip.io hostname,
# then upgrades the release to render the HTTPRoute + Certificate.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

info "Applying the Gateway in namespace ${OPENCLAW_NAMESPACE}"
kc apply -f "${REPO_ROOT}/manifests/gateway/gateway.yaml"

info "Waiting for the Gateway LoadBalancer IP (AKS provisions a public IP)"
LB_IP=""
for _ in $(seq 1 60); do
  LB_IP="$(gateway_lb_ip "${OPENCLAW_NAMESPACE}" openclaw-gateway)"
  [[ -n "${LB_IP}" ]] && break
  sleep 5
done
[[ -n "${LB_IP}" ]] || die "timed out waiting for Gateway LoadBalancer IP"
ok "Gateway public IP: ${LB_IP}"

# nip.io resolves <anything>.<ip>.nip.io -> <ip>, giving us a working hostname
# without managing DNS.
OPENCLAW_HOST="openclaw.${LB_IP}.nip.io"
info "Hostname: ${OPENCLAW_HOST}"

info "Upgrading OpenClaw release with external exposure + TLS"
helmc upgrade "${OPENCLAW_RELEASE}" "${REPO_ROOT}/charts/openclaw" \
  --namespace "${OPENCLAW_NAMESPACE}" \
  --reuse-values \
  --set expose.enabled=true \
  --set expose.host="${OPENCLAW_HOST}" \
  --set expose.tls.enabled=true \
  --set expose.tls.clusterIssuer=openclaw-ca-issuer \
  --wait --timeout 5m

info "Waiting for the leaf certificate to be issued"
kc -n "${OPENCLAW_NAMESPACE}" wait --for=condition=Ready \
  certificate/"${OPENCLAW_RELEASE}-tls" --timeout=120s || \
  warn "certificate not Ready yet; check: kubectl -n ${OPENCLAW_NAMESPACE} describe certificate ${OPENCLAW_RELEASE}-tls"

echo
ok "OpenClaw is exposed:"
echo "    https://${OPENCLAW_HOST}/"
echo "    (self-signed CA — your browser will warn; trust manifests/cert-manager CA to silence it)"
echo
echo "Gateway token for the Control UI:"
echo "    $(cat "${REPO_ROOT}/.openclaw-gateway-token" 2>/dev/null || echo '<see .openclaw-gateway-token>')"
