#!/usr/bin/env bash
# Publish OpenClaw through Envoy Gateway with a cert-manager TLS cert.
# Creates the Gateway, waits for its LoadBalancer IP, picks a hostname, then
# upgrades the release to render the HTTPRoute + Certificate.
#
# Hostname:
#   - CUSTOM_HOST set  -> use it verbatim (point an A record at the Gateway IP).
#   - CUSTOM_HOST empty -> derive openclaw.<lb-ip>.nip.io (no DNS needed).
# Issuer:
#   - CLUSTER_ISSUER (default openclaw-ca-issuer). Use letsencrypt-prod for a
#     publicly-trusted cert once CUSTOM_HOST resolves to the Gateway IP.
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

if [[ -n "${CUSTOM_HOST}" ]]; then
  OPENCLAW_HOST="${CUSTOM_HOST}"
  info "Using custom hostname: ${OPENCLAW_HOST}"
  warn "Ensure DNS A record exists:  ${OPENCLAW_HOST}  ->  ${LB_IP}"
  if [[ "${CLUSTER_ISSUER}" == letsencrypt* ]]; then
    info "Apply the Let's Encrypt issuer if not already present:"
    info "  kubectl apply -f manifests/cert-manager/clusterissuer-letsencrypt.yaml"
    warn "Let's Encrypt validates over HTTP-01; the cert stays Pending until"
    warn "${OPENCLAW_HOST} resolves to ${LB_IP}, then issues automatically."
  fi
else
  # nip.io resolves <anything>.<ip>.nip.io -> <ip>, giving a working hostname
  # without managing DNS.
  OPENCLAW_HOST="openclaw.${LB_IP}.nip.io"
  info "Hostname: ${OPENCLAW_HOST}"
fi

info "Upgrading OpenClaw release (host=${OPENCLAW_HOST}, issuer=${CLUSTER_ISSUER})"
helmc upgrade "${OPENCLAW_RELEASE}" "${REPO_ROOT}/charts/openclaw" \
  --namespace "${OPENCLAW_NAMESPACE}" \
  --reuse-values \
  --set expose.enabled=true \
  --set expose.host="${OPENCLAW_HOST}" \
  --set expose.tls.enabled=true \
  --set expose.tls.clusterIssuer="${CLUSTER_ISSUER}" \
  --wait --timeout 5m

info "Waiting for the leaf certificate to be issued"
if kc -n "${OPENCLAW_NAMESPACE}" wait --for=condition=Ready \
    certificate/"${OPENCLAW_RELEASE}-tls" --timeout=120s 2>/dev/null; then
  CERT_OK=1
else
  CERT_OK=0
  warn "certificate not Ready yet."
  warn "Inspect: kubectl -n ${OPENCLAW_NAMESPACE} describe certificate ${OPENCLAW_RELEASE}-tls"
  [[ -n "${CUSTOM_HOST}" ]] && warn "Most likely DNS for ${OPENCLAW_HOST} is not resolving to ${LB_IP} yet."
fi

echo
ok "OpenClaw exposed at:"
echo "    https://${OPENCLAW_HOST}/"
if [[ "${CLUSTER_ISSUER}" == letsencrypt* ]]; then
  [[ "${CERT_OK}" == 1 ]] && echo "    (publicly-trusted Let's Encrypt cert)" \
                          || echo "    (Let's Encrypt cert pending — see warnings above)"
else
  echo "    (self-signed CA — browser will warn; trust the manifests/cert-manager CA to silence it)"
fi
echo
echo "Gateway token for the Control UI:"
echo "    $(cat "${REPO_ROOT}/.openclaw-gateway-token" 2>/dev/null || echo '<see .openclaw-gateway-token>')"
