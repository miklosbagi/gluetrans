SHELL := /bin/bash
DOCKER_REPO := miklosbagi/gluetrans
GHCR_REPO := ghcr.io/miklosbagi/gluetranspia
DOCKER_BUILD_CMD := docker buildx build --platform linux/amd64,linux/arm64
GLUETUN_VERSION := v3.41.0
# Gluetun v3.41.0+ supports HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE; older CI matrix tags still use config.toml (issue #92).
LEGACY_GLUETUN_CONTROL_AUTH := $(shell echo '$(GLUETUN_VERSION)' | grep -qE '^v3\.(38|39|40\.0)$$' && echo legacy || echo modern)
ifeq ($(LEGACY_GLUETUN_CONTROL_AUTH),legacy)
export GLUETRANS_COMPOSE_FILE := test/docker-compose-build-legacy-gluetun.yaml
export GLUETRANS_COMPOSE_DEBUG_FILE := test/docker-compose-build-debug-legacy-gluetun.yaml
DOCKER_COMPOSE_CMD := docker compose -f $(GLUETRANS_COMPOSE_FILE)
DOCKER_COMPOSE_DEBUG_CMD := docker compose -f $(GLUETRANS_COMPOSE_DEBUG_FILE)
else
export GLUETRANS_COMPOSE_FILE := test/docker-compose-build.yaml
export GLUETRANS_COMPOSE_DEBUG_FILE := test/docker-compose-build-debug.yaml
DOCKER_COMPOSE_CMD := docker compose -f $(GLUETRANS_COMPOSE_FILE)
DOCKER_COMPOSE_DEBUG_CMD := docker compose -f $(GLUETRANS_COMPOSE_DEBUG_FILE)
endif

TRANSMISSION_VERSION := 4.0.6
SANITIZE_LOGS := 0
# Optional: FIX=89 make release-dev → tags dev-89 (Docker Hub + GHCR) for testing multiple dev builds
DEV_TAG := dev$(if $(FIX),-$(FIX),)

GLUETRANS_VPN_USERNAME := $(shell echo $$GLUETRANS_VPN_USERNAME)
include test/.env
export

all: test build release-dev release-latest

build:
	${DOCKER_BUILD_CMD} .

lint:
	@shellcheck entrypoint.sh && echo "✅ ./entrypoint.sh linting passed." || (echo "❌ ./entrypoint.sh linting failed." && exit 1)
	@shellcheck test/run-smoke.sh && echo "✅ test/run-smoke.sh linting passed." || (echo "❌ test/run-smoke.sh linting failed." && exit 1)
	@shellcheck test/run-debug-test.sh && echo "✅ test/run-debug-test.sh linting passed." || (echo "❌ test/run-debug-test.sh linting failed." && exit 1)
	@hadolint Dockerfile && echo "✅ Dockerfile linting passed." || (echo "❌ Dockerfile linting failed." && exit 1)

release-dev: test
	@${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:$(DEV_TAG) --push . && echo "✅ Release $(DEV_TAG) built, tagged, and pushed to docker.io repo." || (echo "❌ Release $(DEV_TAG) failed to build docker repo package." && exit 1)
	@docker pull ${DOCKER_REPO}:$(DEV_TAG) && echo "✅ Release $(DEV_TAG) successfully pulled from docker.io repo." || (echo "❌ Release $(DEV_TAG) failed pulling back from docker repo." && exit 1)
	@docker tag ${DOCKER_REPO}:$(DEV_TAG) ${GHCR_REPO}:$(DEV_TAG) && echo "✅ Release $(DEV_TAG) tagged for ghcr repo." || (echo "❌ Release $(DEV_TAG) tagging for ghcr repo." && exit 1)
	@docker push ${GHCR_REPO}:$(DEV_TAG) && echo "✅ Release $(DEV_TAG) pushed to ghcr repo." || (echo "❌ Release $(DEV_TAG) failed pushing to ghcr repo." && exit 1)

release-latest: test
	@${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:latest --push . && echo "✅ Release latest built, tagged, and pushed to docker.io repo." || (echo "❌ Release latest failed to build docker repo package." && exit 1)
	@docker pull ${DOCKER_REPO}:latest && echo "✅ Release latest successfully pulled from docker.io repo." || (echo "❌ Release latest failed pulling back from docker repo." && exit 1)
	@docker tag ${DOCKER_REPO}:latest ${GHCR_REPO}:latest && echo "✅ Release latest tagged for ghcr repo." || (echo "❌ Release latest tagging for ghcr repo." && exit 1)
	@docker push ${GHCR_REPO}:latest && echo "✅ Release latest pushed to ghcr repo." || (echo "❌ Release latest failed pushing to ghcr repo." && exit 1)

release-version:
ifdef VERSION
	$(MAKE) test
	@${DOCKER_BUILD_CMD} -t $(DOCKER_REPO):$(VERSION) --push . && echo "✅ Release ${VERSION} built, tagged, and pushed to docker.io repo." || (echo "❌ Release ${VERSION} failed to build docker repo package." && exit 1)
	@docker pull ${DOCKER_REPO}:${VERSION} && echo "✅ Release ${VERSION} successfully pulled from docker.io repo." || (echo "❌ Release ${VERSION} failed pulling back from docker repo." && exit 1)
	@${DOCKER_BUILD_CMD} -t $(GHCR_REPO):$(VERSION) --push . && echo "✅ Release ${VERSION} built, tagged, and pushed to ghcr repo." || (echo "❌ Release ${VERSION} failed to build docker repo package." && exit 1)
	@docker tag $(DOCKER_REPO):$(VERSION) ${GHCR_REPO}:${VERSION} && echo "✅ Release ${VERSION} tagged for ghcr repo." || (echo "❌ Release ${VERSION} tagging for ghcr repo." && exit 1)
	@docker push ${GHCR_REPO}:${VERSION} && echo "✅ Release ${VERSION} pushed to ghcr repo." || (echo "❌ Release ${VERSION} failed pushing to ghcr repo." && exit 1)
else
	@echo "❌ Please provide a version number using 'make release-version VERSION=vX.Y'"
endif

test: lint pr-test test-debug-mode

pr-test: test-env-start test-run-all test-env-stop

test-debug-mode: test-debug-env-start test-run-debug test-debug-env-stop

test-env-start: test-env-stop
	@if [ "$(LEGACY_GLUETUN_CONTROL_AUTH)" = legacy ]; then \
		echo "Using bind-mounted config.toml for Gluetun $(GLUETUN_VERSION) (pre–v3.41.0 control auth)"; \
		cp test/gluetun-config/config-old.toml test/gluetun-config/config.toml; \
	fi
	SANITIZE_LOGS=0 && $(DOCKER_COMPOSE_CMD) up --no-deps --build --force-recreate --remove-orphans --detach

test-env-stop:
	$(DOCKER_COMPOSE_CMD) down --remove-orphans --volumes

test-debug-env-start: test-debug-env-stop
	@if [ "$(LEGACY_GLUETUN_CONTROL_AUTH)" = legacy ]; then \
		echo "Using bind-mounted config.toml for Gluetun $(GLUETUN_VERSION) (pre–v3.41.0 control auth)"; \
		cp test/gluetun-config/config-old.toml test/gluetun-config/config.toml; \
	fi
	SANITIZE_LOGS=0 && $(DOCKER_COMPOSE_DEBUG_CMD) up --no-deps --build --force-recreate --remove-orphans --detach

test-debug-env-stop:
	$(DOCKER_COMPOSE_DEBUG_CMD) down --remove-orphans --volumes

test-run-sonar:
	sonar-scanner \
		-Dsonar.organization=${GLUETRANS_SONAR_ORGANIZATION} \
		-Dsonar.projectKey=${GLUETRANS_SONAR_PROJECT_KEY} \
		-Dsonar.sources=. \
		-Dsonar.host.url=https://sonarcloud.io

test-run-all:
	@test/run-smoke.sh && echo "✅ All smoke tests pass." || (echo "❌ Smoke tests failed." && \
	  $(DOCKER_COMPOSE_CMD) logs gluetun | tail -n 100; \
	  $(DOCKER_COMPOSE_CMD) logs transmission | tail -n 100; \
	  $(DOCKER_COMPOSE_CMD) logs gluetrans | tail -n 100; \
	  exit 1)

test-run-debug:
	@test/run-debug-test.sh && echo "✅ DEBUG mode tests pass." || (echo "❌ DEBUG mode tests failed." && \
	  $(DOCKER_COMPOSE_DEBUG_CMD) logs gluetun | tail -n 100; \
	  $(DOCKER_COMPOSE_DEBUG_CMD) logs transmission | tail -n 100; \
	  $(DOCKER_COMPOSE_DEBUG_CMD) logs gluetrans | tail -n 100; \
	  exit 1)

.PHONY: all build lint release-dev release-latest release-version test test-env-start test-env-stop test-run-all test-debug-mode test-debug-env-start test-debug-env-stop test-run-debug
