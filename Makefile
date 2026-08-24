 # +-------------------------------------------------------------------+
 # | (C) Copyright IBM Corp. 2025, 2026                                |
 # | SPDX-License-Identifier: Apache-2.0                               |
 # +-------------------------------------------------------------------+

CURRENT_DIR			:= $(shell pwd)
MAKEFILE_PATH		:= $(abspath $(lastword $(MAKEFILE_LIST)))
REPO_ROOT			:= $(abspath $(patsubst %/,%,$(dir $(MAKEFILE_PATH))))
VERSION				?= $(shell cat $(REPO_ROOT)/VERSION)
REGISTRY   			?= docker.io/spyre-operator
DOCKER				?= $(shell command -v podman 2> /dev/null || echo docker)
DOCKERFILE			= $(REPO_ROOT)/Dockerfile
DOCKER_BUILD_OPTS	?= --progress=plain
IMAGE_NAME			:= $(REGISTRY)/spyre-device-plugin-init
IMAGE_TAG 			?= $(VERSION)
IMAGE 				?= $(IMAGE_NAME):$(IMAGE_TAG)
# Architectures whose per-arch image tags ($(IMAGE)-<arch>) are combined into the manifest.

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

DOCKER_GO_BUILD_FLAGS ?= -race

## Tool Binaries
YQ			?= $(LOCALBIN)/yq
PYTHON      ?= python3
PIP         ?= pip3

# detect-secrets
DETECT_SECRETS_GIT ?= "https://github.com/ibm/detect-secrets.git@master\#egg=detect-secrets"

## Tool Versions
YQ_VERSION	?= v4.29.2

##@ Development tools

.PHONY: yq
yq: $(YQ) ## Download yq locally if necessary.
$(YQ): $(LOCALBIN)
	test -s $(YQ) || GOBIN=$(LOCALBIN) go install github.com/mikefarah/yq/v4@$(YQ_VERSION)

##@ Local test

.PHONY: test
test: docker-build ## Run test with plain podman/docker run
	mkdir -p $(CURRENT_DIR)/test-output
	chmod 777 $(CURRENT_DIR)/test-output
	$(DOCKER) run --rm \
		--pull=never \
		-v $(CURRENT_DIR)/test-output:/usr/local/etc/device-plugins \
		-e PSEUDO_DEVICE_MODE=1 \
		$(IMAGE)
	@echo "--- topo.json output ---"
	@cat $(CURRENT_DIR)/test-output/metadata/topo.json 2>/dev/null || echo "(no topo.json produced)"
	@rm -rf $(CURRENT_DIR)/test-output || true

##@ Image operations

.PHONY: docker-build
docker-build: vendor ## Build spyre device plugin init image for build host architecture
	$(DOCKER) build $(DOCKER_BUILD_OPTS) --pull \
	--tag $(IMAGE) \
	--build-arg VERSION="$(VERSION)" \
	--build-arg BUILD_FLAGS="$(DOCKER_GO_BUILD_FLAGS)" \
	--file $(DOCKERFILE) $(CURRENT_DIR)

.PHONY: docker-push
docker-push: ## Push spyre device plugin init image for the build host architecture.
	$(DOCKER) push $(IMAGE)

.PHONY: docker-build-push
docker-build-push: docker-build docker-push ## Build and push the spyre device plugin init image for the build host

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: version
version: ## Display image version
	@echo "Image version: $(VERSION)"

.PHONY: echo-version
echo-version: ## Print (echo) the current version
	@echo "$(VERSION)"

.PHONY: clean
clean: ## Clean-up intermediate artifacts
	-rm -rf $(LOCALBIN)
	-rm -rf local.mk

.PHONY: venv
venv: ## Setup and activate venv
	$(PYTHON) -m venv venv

.PHONY: detect-secrets-install
detect-secrets-install: venv ## Install detect-secret tool
	. venv/bin/activate; $(PIP) install "git+$(DETECT_SECRETS_GIT)"

.PHONY: secrets-scan
secrets-scan: venv detect-secrets-install ## Scan secrets and create secret-baseline for repo
	. venv/bin/activate; detect-secrets scan --no-ghe-scan --exclude-files go.sum --update .secrets.baseline

.PHONY: secrets-audit
secrets-audit: venv detect-secrets-install ## Audit secrets
	. venv/bin/activate; detect-secrets audit .secrets.baseline

# helper target for viewing the value of makefile variables.
print-%  : ;@echo $* = $($*)

.PHONY: vendor
vendor:
	@:
