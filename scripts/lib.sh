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
: "${OPENCLAW_MODEL:=anthropic/claude-sonnet-4-6}"
: "${CERT_MANAGER_VERSION:=v1.16.2}"
# Custom public hostname for OpenClaw. When empty, scripts/50-expose.sh derives a
# nip.io host from the Gateway LB IP. Set this to a real DNS name (A record ->
# Gateway IP) to use your own domain, e.g. CUSTOM_HOST=claw.example.com
: "${CUSTOM_HOST:=}"
# cert-manager ClusterIssuer for the OpenClaw TLS cert. Use "letsencrypt-prod"
# (publicly trusted) once CUSTOM_HOST resolves to the Gateway IP, or the default
# self-signed CA issuer for demo/nip.io hosts.
: "${CLUSTER_ISSUER:=openclaw-ca-issuer}"

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

# Fetch the public address of a Gateway from its status. Envoy Gateway publishes
# the LoadBalancer IP here regardless of which namespace the proxy Service lives
# in, so this is more robust than querying the Service directly. Empty until set.
gateway_lb_ip() {
  local ns="$1" gw="$2"
  kc -n "$ns" get gateway "$gw" \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true
}
