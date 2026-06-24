SHELL := /usr/bin/env bash
SCRIPTS := scripts

.DEFAULT_GOAL := help

.PHONY: help preflight cert-manager envoy-gateway kagent openclaw expose install status teardown lint

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

preflight: ## Verify tooling, cluster, and secrets
	@$(SCRIPTS)/00-preflight.sh

cert-manager: ## Install cert-manager + self-signed PKI
	@$(SCRIPTS)/10-cert-manager.sh

envoy-gateway: ## Install Envoy Gateway + GatewayClass
	@$(SCRIPTS)/20-envoy-gateway.sh

kagent: ## Install kagent + sample agent
	@$(SCRIPTS)/30-kagent.sh

openclaw: ## Deploy OpenClaw (Helm chart)
	@$(SCRIPTS)/40-openclaw.sh

expose: ## Publish OpenClaw via Gateway + TLS
	@$(SCRIPTS)/50-expose.sh

install: ## Run the full install pipeline
	@$(SCRIPTS)/install-all.sh

status: ## Show component health
	@$(SCRIPTS)/status.sh

teardown: ## Remove everything (prompts; pass ARGS="--yes")
	@$(SCRIPTS)/teardown.sh $(ARGS)

lint: ## Lint the OpenClaw Helm chart
	@helm lint charts/openclaw
	@helm template openclaw charts/openclaw \
		--set secrets.anthropicApiKey=dummy --set secrets.gatewayToken=dummy >/dev/null \
		&& echo "helm template OK"
