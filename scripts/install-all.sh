#!/usr/bin/env bash
# One-shot installer: runs every stage in order against the target cluster.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

info "openclaw-k8s — full install against context '${KUBE_CONTEXT}'"
"${HERE}/00-preflight.sh"
"${HERE}/10-cert-manager.sh"
"${HERE}/20-envoy-gateway.sh"
"${HERE}/30-kagent.sh"
"${HERE}/40-openclaw.sh"
"${HERE}/50-expose.sh"

echo
ok "All components installed. Run scripts/status.sh for a summary."
