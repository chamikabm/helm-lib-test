# Makefile for istiolib project

HELM ?= helm
CHART_LIB := charts/istiolib
CHART_TEST := charts/istiolib-test
DOCKER_IMAGE ?= istiolib-tests
CONTAINER ?= docker  # override with `make docker-test CONTAINER=podman`
SCRIPT := scripts/run-tests.sh

.PHONY: all deps lint test docker-build docker-test clean help container-runtime-check

all: deps lint test ## Build dependencies, lint charts, run tests

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*##/: /' | sort

deps: ## Build chart dependencies for test harness
	$(HELM) dependency build $(CHART_TEST)

lint: ## Run helm lint on library & test charts
	$(HELM) lint $(CHART_LIB) $(CHART_TEST)

test: ## Run unit tests via script
	chmod +x $(SCRIPT)
	$(SCRIPT)

container-runtime-check:
	@command -v $(CONTAINER) >/dev/null 2>&1 || { echo "Container runtime '$(CONTAINER)' not found in PATH" >&2; exit 2; }

docker-build: container-runtime-check ## Build container image (docker default, podman supported) with helm + plugins pre-installed
	$(CONTAINER) build -t $(DOCKER_IMAGE) .

docker-test: docker-build ## Run tests inside container image (set CONTAINER=podman to use Podman)
	$(CONTAINER) run --rm -v $$(pwd):/workspace $(DOCKER_IMAGE) --skip-plugin-install

clean: ## Remove Helm dependency build artifacts
	@find . -name 'Chart.lock' -delete
	@find . -type d -name 'charts' -exec rm -rf {} + 2>/dev/null || true
