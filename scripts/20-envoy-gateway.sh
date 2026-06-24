#!/usr/bin/env bash
# Install Envoy Gateway (ships Gateway API CRDs) and the "envoy" GatewayClass.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

info "Installing Envoy Gateway"
helmc upgrade --install envoy-gateway \
  oci://docker.io/envoyproxy/gateway-helm \
  --version v1.3.2 \
  --namespace "${ENVOY_NAMESPACE}" --create-namespace \
  -f "${REPO_ROOT}/helm/values/envoy-gateway.yaml" \
  --wait --timeout 5m

info "Waiting for Envoy Gateway controller"
kc -n "${ENVOY_NAMESPACE}" rollout status deploy/envoy-gateway --timeout=180s

info "Creating the 'envoy' GatewayClass"
kc apply -f "${REPO_ROOT}/manifests/gateway/gatewayclass.yaml"
kc wait --for=condition=Accepted gatewayclass/envoy --timeout=60s

ok "Envoy Gateway ready; GatewayClass 'envoy' accepted"
