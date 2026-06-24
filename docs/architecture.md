# Architecture

This demo stands up four independent Helm-installed layers on an AKS cluster and
wires them together with the Gateway API.

```
                    Internet
                       │
                       ▼  (AKS public IP, provisioned for the Gateway's LB Service)
        ┌──────────────────────────────┐
        │      Envoy Gateway            │   gateway-helm chart
        │  GatewayClass: envoy          │   ns: envoy-gateway-system
        └──────────────┬───────────────┘
                       │ programs
                       ▼
        ┌──────────────────────────────┐
        │  Gateway: openclaw-gateway    │   ns: openclaw
        │   :80  HTTP                   │
        │   :443 HTTPS  ◄── TLS secret  │◄── cert-manager Certificate
        └──────────────┬───────────────┘        (CA-signed, openclaw-tls)
                       │ HTTPRoute (host: openclaw.<ip>.nip.io)
                       ▼
        ┌──────────────────────────────┐
        │  OpenClaw Deployment          │   charts/openclaw (local)
        │   gateway run :18789          │   ns: openclaw
        │   PVC /home/node/.openclaw    │
        └──────────────────────────────┘

   cert-manager (ns: cert-manager)          kagent (ns: kagent)
   ┌───────────────────────────┐            ┌──────────────────────────────┐
   │ selfsigned-issuer         │            │ controller + UI (:8080)      │
   │   └─► openclaw-ca (CA)     │            │ ModelConfig: default-model-… │
   │        └─► openclaw-ca-iss │            │ Agent: k8s-helper            │
   └───────────────────────────┘            └──────────────────────────────┘
```

## Components

| Layer | Chart / source | Namespace | Role in the demo |
|------|----------------|-----------|------------------|
| cert-manager | `jetstack/cert-manager` | `cert-manager` | Issues TLS certs. A self-signed `ClusterIssuer` bootstraps a CA, which signs leaf certs. |
| Envoy Gateway | `oci://docker.io/envoyproxy/gateway-helm` | `envoy-gateway-system` | Gateway API implementation; provisions the public LoadBalancer. Ships the Gateway API CRDs. |
| kagent | `oci://ghcr.io/kagent-dev/kagent/helm/{kagent-crds,kagent}` | `kagent` | Runs agentic AI as Kubernetes CRDs. Installed with the Anthropic provider + a sample `Agent`. |
| OpenClaw | `charts/openclaw` (local) | `openclaw` | The workload: the OpenClaw assistant gateway, exposed via the Gateway with TLS. |

## Why these choices

- **Gateway in the app namespace.** Keeping `openclaw-gateway`, the `HTTPRoute`,
  and the cert-manager TLS `Secret` in `openclaw` avoids cross-namespace
  `ReferenceGrant` plumbing — simplest correct topology for a single-app demo.
- **Self-signed CA by default.** It always works with no public DNS. A Let's
  Encrypt issuer is provided (`manifests/cert-manager/clusterissuer-letsencrypt.yaml`)
  for when you have a real hostname.
- **nip.io hostname.** `openclaw.<lb-ip>.nip.io` resolves to the LB IP with zero
  DNS configuration, so the HTTPRoute has a usable hostname immediately.
- **Anthropic for both.** kagent agents and the OpenClaw assistant share one
  `ANTHROPIC_API_KEY`, keeping the demo to a single credential.

## Install order (and why)

1. **cert-manager** — issuers must exist before any `Certificate` is requested.
2. **Envoy Gateway** — installs Gateway API CRDs and the controller.
3. **kagent** — independent of the gateway; installed here to keep app steps together.
4. **OpenClaw** — deployed without exposure first so the pod is healthy before routing.
5. **expose** — create the Gateway, learn its IP, then render the `HTTPRoute` + leaf `Certificate`.
