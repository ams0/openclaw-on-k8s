#!/usr/bin/env bash
# Shared helpers for the openclaw-k8s scripts. Source this; do not execute.
set -euo pipefail

# Resolve repo root regardless of where a script is invoked from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Defaults (override via environment or .env) -----------------------------
: "${KUBE_CONTEXT:=claw}"            # AKS context loaded into kubeconfig
: "${OPENCLAW_NAMESPACE:=openclaw}"
: "${KAGENT_NAMESPACE:=kagent}"
: "${CERT_MANAGER_NAMESPACE:=cert-manager}"
: "${ENVOY_NAMESPACE:=envoy-gateway-system}"
: "${OPENCLAW_RELEASE:=openclaw}"
: "${OPENCLAW_MODEL:=anthropic/claude-sonnet-4-5}"
: "${CERT_MANAGER_VERSION:=v1.16.2}"

# Load .env if present (KEY=VALUE lines), without clobbering already-set vars.
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

# --- Pretty logging ----------------------------------------------------------
_c() { tput setaf "$1" 2>/dev/null || true; }
_r() { tput sgr0 2>/dev/null || true; }
info()  { echo "$(_c 4)::$(_r) $*"; }
ok()    { echo "$(_c 2)✓$(_r) $*"; }
warn()  { echo "$(_c 3)!$(_r) $*" >&2; }
die()   { echo "$(_c 1)✗ $*$(_r)" >&2; exit 1; }

# kubectl/helm pinned to the selected context so we never touch the wrong cluster.
kc()   { kubectl --context "${KUBE_CONTEXT}" "$@"; }
helmc(){ helm --kube-context "${KUBE_CONTEXT}" "$@"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Ensure a namespace exists (idempotent).
ensure_ns() {
  kc get namespace "$1" >/dev/null 2>&1 || kc create namespace "$1"
}

# Fetch the external IP of the Envoy LB Service backing a Gateway. Empty until set.
gateway_lb_ip() {
  local ns="$1" gw="$2"
  kc -n "$ns" get svc \
    -l "gateway.envoyproxy.io/owning-gateway-name=${gw}" \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
}
