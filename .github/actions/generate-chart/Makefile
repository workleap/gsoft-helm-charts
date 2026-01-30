.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

SCRIPT_PATH := ./generate-chart.ps1
SCRIPT_PATH_MULTIPLE := ./generate-multiple-charts.ps1

# Load .env file if it exists (for local development)
-include .env
export

CHART_REGISTRY := https://workleap.github.io/gsoft-helm-charts
CHART_NAME := aspnetcore
CHART_VERSION ?= latest

PRODUCT_NAME := foobar
LEAP_DEPLOY_CONFIG_PATH := ./examples/folded-config.json
INFRA_CONFIG_PATH := ./examples/infra-config.json
ENVIRONMENT := dev
REGION := eastus
HELM_RELEASE_NAME := foobar

# Mock GitHub Actions environment variables (for annotations) when not in CI
ifndef CI
GITHUB_SERVER_URL="https://github.com"
GITHUB_REPOSITORY="workleap/wl-leap-shop"
GITHUB_WORKFLOW_REF="workleap/wl-leap-deploy/.github/workflows/generate-chart.yml@refs/heads/main"
GITHUB_RUN_ID="123456789"
GITHUB_SHA="7f4b7ce6edb5aca1e2291bd34cc8a943991baaef"
GITHUB_ACTOR="marcellus.wallace@workleap.com"
endif

OUTPUT_DIR := ./out

all: chart

.PHONY: test/chart
test/chart: .github/actions/generate-chart/Makefile  ## Generate Helm chart and template manifests
	@echo "Generating Helm chart and validating manifests..."
	@make -C .github/actions/generate-chart all

FORCE:

$(OUTPUT_DIR)/chart: FORCE
	@mkdir -p $(OUTPUT_DIR)
	@echo "Generating Helm chart from test values..."
	$(SCRIPT_PATH) \
	-ChartRegistry $(CHART_REGISTRY) -ChartName $(CHART_NAME) -ChartVersion $(CHART_VERSION) \
	-ProductName $(PRODUCT_NAME) \
	-FoldedConfigJson $(LEAP_DEPLOY_CONFIG_PATH) \
	-InfraConfigJson $(INFRA_CONFIG_PATH) \
	-Environment $(ENVIRONMENT) \
	-Region $(REGION) \
	-OutputDirectory $@

$(OUTPUT_DIR)/manifests.yaml: $(OUTPUT_DIR)/chart FORCE
	@mkdir -p $(OUTPUT_DIR)
	@helm version
	@echo "Generating manifests from Helm chart..."
	@helm dependency build $<
	@helm template $(HELM_RELEASE_NAME) $< --values $</values.yaml > $@

.PHONY: chart  ## Create single umbrella Helm chart from examples config files
chart: $(OUTPUT_DIR)/chart

$(OUTPUT_DIR)/charts: FORCE
	@mkdir -p $(OUTPUT_DIR)
	@echo "Generating individual Helm charts for each workload..."
	$(SCRIPT_PATH_MULTIPLE) \
	-ChartRegistry $(CHART_REGISTRY) -ChartName $(CHART_NAME) -ChartVersion $(CHART_VERSION) \
	-ProductName $(PRODUCT_NAME) \
	-FoldedConfigJson $(LEAP_DEPLOY_CONFIG_PATH) \
	-InfraConfigJson $(INFRA_CONFIG_PATH) \
	-Environment $(ENVIRONMENT) \
	-Region $(REGION) \
	-OutputDirectory $@

.PHONY: charts  ## Create individual Helm charts (one per workload) from examples config files
charts: $(OUTPUT_DIR)/charts

.PHONY: manifests  ## Generate manifests from Helm chart
manifests: $(OUTPUT_DIR)/manifests.yaml

.PHONY: clean
clean:
	@rm -rf $(OUTPUT_DIR)

.PHONY: help
help:  ## Display this help message
	@echo "Available targets:"
	@grep -hE '^[a-zA-Z_/-]+:.*?##|^\.PHONY: [a-zA-Z_/-]+.*?##' $(MAKEFILE_LIST) | sed 's/^\.PHONY: \([^ ]*\)  */\1:  /' | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
