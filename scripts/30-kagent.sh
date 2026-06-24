#!/usr/bin/env bash
# Install kagent CRDs + controller (Anthropic provider) and a sample Agent.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[[ -n "${ANTHROPIC_API_KEY:-}" ]] || die "ANTHROPIC_API_KEY is required for kagent"

info "Installing kagent CRDs"
helmc upgrade --install kagent-crds \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace "${KAGENT_NAMESPACE}" --create-namespace \
  --wait --timeout 5m

info "Installing kagent (provider: anthropic)"
helmc upgrade --install kagent \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace "${KAGENT_NAMESPACE}" \
  -f "${REPO_ROOT}/helm/values/kagent.yaml" \
  --set providers.default=anthropic \
  --set providers.anthropic.apiKey="${ANTHROPIC_API_KEY}" \
  --wait --timeout 5m

info "Waiting for the default ModelConfig"
for _ in $(seq 1 30); do
  if kc -n "${KAGENT_NAMESPACE}" get modelconfig default-model-config >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

info "Applying sample agent (k8s-helper)"
kc apply -f "${REPO_ROOT}/manifests/kagent/sample-agent.yaml"

ok "kagent installed. UI: kubectl -n ${KAGENT_NAMESPACE} port-forward svc/kagent-ui 8080:8080"
