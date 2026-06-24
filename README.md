# openclaw-k8s

Deploy [OpenClaw](https://openclaw.ai) — a self-hosted personal AI assistant — on
**Kubernetes (AKS)** using a stack of Helm charts and the Gateway API, alongside
[**kagent**](https://kagent.dev) for agentic AI running as Kubernetes CRDs.

This is a teaching/demo repo: plain Helm + small shell scripts, no GitOps
controller, runnable end-to-end with one command.

## What gets deployed

| Component | How | Namespace |
|-----------|-----|-----------|
| **cert-manager** + self-signed CA | `jetstack/cert-manager` | `cert-manager` |
| **Envoy Gateway** + `envoy` GatewayClass | `envoyproxy/gateway-helm` (OCI) | `envoy-gateway-system` |
| **kagent** + sample `Agent` | `kagent-dev/kagent` (OCI) | `kagent` |
| **OpenClaw** assistant | local chart `charts/openclaw` | `openclaw` |

OpenClaw is published through Envoy Gateway over HTTPS, with a cert-manager-issued
certificate and a `*.nip.io` hostname derived from the LoadBalancer IP.

See [`docs/architecture.md`](docs/architecture.md) for the topology and rationale.

## Prerequisites

- An AKS cluster with its context in your kubeconfig (this repo defaults to context **`claw`**).
- `kubectl` and `helm` (v3.8+ for OCI charts).
- An **Anthropic API key** (used by both kagent and OpenClaw).

## Quickstart

```bash
# 1. Provide your credential
cp .env.example .env
$EDITOR .env          # set ANTHROPIC_API_KEY (and KUBE_CONTEXT if not "claw")

# 2. Install everything
make install          # == scripts/install-all.sh

# 3. Check it
make status
```

`make install` runs, in order:

```
00-preflight     verify tooling, cluster reachability, ANTHROPIC_API_KEY
10-cert-manager  install cert-manager + self-signed ClusterIssuer/CA
20-envoy-gateway install Envoy Gateway + the "envoy" GatewayClass
30-kagent        install kagent CRDs + controller (Anthropic) + sample agent
40-openclaw      deploy the OpenClaw Helm chart
50-expose        create the Gateway, get its public IP, wire HTTPRoute + TLS
```

Each stage is also an individual `make` target (`make cert-manager`, `make kagent`, …)
so you can run or re-run them piecemeal. Everything is idempotent (`helm upgrade --install`).

## Accessing things

**OpenClaw (public, after `make expose`):**
```
https://openclaw.<lb-ip>.nip.io/
```
The self-signed CA will trigger a browser warning — expected. To remove it, trust
the CA from `kubectl -n cert-manager get secret openclaw-ca-key-pair -o jsonpath='{.data.tls\.crt}' | base64 -d`.

The Control UI login token:
```bash
cat .openclaw-gateway-token
```

> **Device pairing:** by default the chart sets
> `openclaw.disableDeviceAuth: true`, so the token alone grants Control UI access
> (no per-browser `openclaw devices approve`). For a real deployment set it to
> `false` and approve devices explicitly on the Gateway host:
> `kubectl -n openclaw exec deploy/openclaw -- openclaw devices list|approve <id>`.

**OpenClaw (local, no Gateway):**
```bash
kubectl -n openclaw port-forward svc/openclaw 18789:18789
open http://127.0.0.1:18789/
```

**kagent UI:**
```bash
kubectl -n kagent port-forward svc/kagent-ui 8080:8080
open http://127.0.0.1:8080/
```

## Repository layout

```
charts/openclaw/          Helm chart for the OpenClaw workload
helm/values/              Values overrides for the third-party charts
manifests/cert-manager/   Self-signed PKI + (optional) Let's Encrypt issuer
manifests/gateway/        GatewayClass + Gateway
manifests/kagent/         Sample kagent Agent (kagent.dev/v1alpha2)
scripts/                  Ordered install scripts + status/teardown
docs/                     Architecture notes
```

## Configuration

Tune via `.env` (see `.env.example`) or `--set` on the chart:

| Setting | Where | Default |
|---------|-------|---------|
| Anthropic key | `.env` `ANTHROPIC_API_KEY` | — (required) |
| Kube context | `.env` `KUBE_CONTEXT` | `claw` |
| OpenClaw model | `.env` `OPENCLAW_MODEL` / `openclaw.model` | `anthropic/claude-sonnet-4-5` |
| Image tag | `image.tag` | `latest` |
| Persistence | `persistence.size` | `2Gi` |
| TLS issuer | `expose.tls.clusterIssuer` | `openclaw-ca-issuer` |

## Custom domain + trusted TLS (Let's Encrypt)

By default OpenClaw is published on a `*.nip.io` host with a self-signed cert. To
use your own domain with a publicly-trusted certificate:

1. **Point DNS at the Gateway.** Get the Gateway's public IP and create an A record:
   ```bash
   kubectl -n openclaw get gateway openclaw-gateway -o jsonpath='{.status.addresses[0].value}'
   # claw.example.com.  A  <that-ip>
   ```
2. **Apply the Let's Encrypt issuer** (edit the contact email first):
   ```bash
   kubectl apply -f manifests/cert-manager/clusterissuer-letsencrypt.yaml
   ```
   This requires cert-manager's Gateway API support (`config.enableGatewayAPI: true`
   in `helm/values/cert-manager.yaml`; on v1.16+ this replaced the old
   `ExperimentalGatewayAPISupport` feature gate).
3. **Re-run expose with your host + issuer:**
   ```bash
   CUSTOM_HOST=claw.example.com CLUSTER_ISSUER=letsencrypt-prod ./scripts/50-expose.sh
   ```
   The cert validates over HTTP-01 through the Gateway and issues automatically once
   DNS resolves to the Gateway IP. Until then it stays `Pending` (cert-manager's
   self-check gates ACME validation, so this does not burn Let's Encrypt rate limits).

## Troubleshooting

- **cert-manager `helm upgrade` fails with a `ValidatingWebhookConfiguration`
  conflict** (`conflict with "admissionsenforcer" ... .webhooks[...].namespaceSelector`).
  On AKS with the Azure Policy add-on, an admission enforcer takes ownership of the
  cert-manager webhook's `namespaceSelector`, so a later helm *upgrade* conflicts on
  that field. A fresh `make install` is unaffected (the field isn't contended at
  install time). cert-manager still functions; if you must upgrade, re-apply with
  `helm upgrade --force` or temporarily exclude cert-manager from Azure Policy.

## Teardown

```bash
make teardown                 # prompts for confirmation
make teardown ARGS="--yes"    # non-interactive
make teardown ARGS="--keep-cert-manager"
```

## Caveats (read before relying on this)

- **OpenClaw container contract — verified on image `2026.6.10`.** Two
  non-obvious requirements, both baked into the chart:
  - The gateway defaults to **loopback** bind and is then unreachable from the
    Service. The chart sets `gateway.bind: lan` + `gateway.mode: local` (in
    `openclaw.json`) so it listens on `0.0.0.0`. Do **not** pass
    `--allow-unconfigured` — that flag forces the loopback fallback.
  - `openclaw.json` uses `agents.defaults.model.primary` (not `agent.model`),
    and the browser Control UI needs the external origin in
    `gateway.controlUi.allowedOrigins` (the chart templates this from
    `expose.host`). If a future release changes the schema, update
    `charts/openclaw/templates/configmap.yaml`.
- **Self-signed TLS + nip.io** are for demos. For real certs, use the Let's
  Encrypt issuer with a hostname that actually resolves to the Gateway IP.
- **Secrets are passed via `--set`** at install time and never written to git.
  `.env` and `.openclaw-gateway-token` are git-ignored. For production, use a
  proper secret manager (e.g. External Secrets / Azure Key Vault).
- **Single replica.** OpenClaw keeps local state on a RWO PVC; scaling out needs
  a shared volume or external state.

## References

- OpenClaw docs — https://docs.openclaw.ai
- kagent — https://kagent.dev/docs
- Envoy Gateway — https://gateway.envoyproxy.io
- cert-manager — https://cert-manager.io/docs
