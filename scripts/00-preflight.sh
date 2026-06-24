#!/usr/bin/env bash
# Verify tooling, cluster reachability, and required secrets before deploying.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

info "Checking required CLIs"
require_cmd kubectl
require_cmd helm
ok "kubectl + helm present"

info "Checking kube-context '${KUBE_CONTEXT}'"
kc config current-context >/dev/null 2>&1 \
  || die "context '${KUBE_CONTEXT}' not found in kubeconfig (run: kubectl config get-contexts)"
kc version -o json >/dev/null 2>&1 || die "cannot reach cluster for context '${KUBE_CONTEXT}'"
SERVER="$(kc config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
ok "reachable: ${SERVER}"

info "Checking node readiness"
kc get nodes -o wide || die "unable to list nodes"

info "Checking provider API key"
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  warn "ANTHROPIC_API_KEY is not set."
  warn "Copy .env.example to .env and fill it in, or: export ANTHROPIC_API_KEY=sk-ant-..."
  die  "missing ANTHROPIC_API_KEY"
fi
ok "ANTHROPIC_API_KEY is set (${#ANTHROPIC_API_KEY} chars)"

ok "Preflight passed. Next: scripts/install-all.sh"
