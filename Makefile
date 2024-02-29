SHELL := /bin/bash
DOCKER_REPO := miklosbagi/gluetrans
GHCR_REPO := ghcr.io/miklosbagi/gluetrans
DOCKER_BUILD_CMD := docker buildx build --platform linux/amd64,linux/arm64
DOCKER_COMPOSE_CMD := docker-compose -f test/docker-compose-build.yaml

GLUETUN_VERSION := v3.37.0
TRANSMISSION_VERSION := 4.0.5

GLUETRANS_VPN_USERNAME := $(shell echo $$GLUETRANS_VPN_USERNAME)
include test/.env
export

all: test build release-dev release-latest

build:
	${DOCKER_BUILD_CMD} .

lint:
	@shellcheck entrypoint.sh && echo "✅ ./entrypoint.sh linting passed." || (echo "❌ ./entrypoint.sh linting failed." && exit 1)
	@shellcheck test/run-smoke.sh && echo "✅ test/run-smoke.sh linting passed." || (echo "❌ est/run-smoke.sh linting failed." && exit 1)
	@hadolint Dockerfile && echo "✅ Dockerfile linting passed." || (echo "❌ Dockerfile linting failed." && exit 1)

release-dev: test
	@${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:dev --push . && echo "✅ Release dev built, tagged, and pushed to docker.io repo." || (echo "❌ Release dev failed to build docker repo package." && exit 1)
	@docker pull ${DOCKER_REPO}:dev && echo "✅ Release dev successfully pulled from docker.io repo." || (echo "❌ Release dev failed pulling back from docker repo." && exit 1)
	@docker tag ${DOCKER_REPO}:dev ${GHCR_REPO}:dev && echo "✅ Release dev tagged for ghcr repo." || (echo "❌ Release dev tagging for ghcr repo." && exit 1)
	@docker push ${GHCR_REPO}:dev && echo "✅ Release dev pushed to ghcr repo." || (echo "❌ Release dev failed pushing to ghcr repo." && exit 1)

release-latest: test
	@${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:latest --push . && echo "✅ Release latest built, tagged, and pushed to docker.io repo." || (echo "❌ Release latest failed to build docker repo package." && exit 1)
	@docker pull ${DOCKER_REPO}:latest && echo "✅ Release latest successfully pulled from docker.io repo." || (echo "❌ Release latest failed pulling back from docker repo." && exit 1)
	@docker tag ${DOCKER_REPO}:latest ${GHCR_REPO}:latest && echo "✅ Release latest tagged for ghcr repo." || (echo "❌ Release latest tagging for ghcr repo." && exit 1)
	@docker push ${GHCR_REPO}:latest && echo "✅ Release latest pushed to ghcr repo." || (echo "❌ Release latest failed pushing to ghcr repo." && exit 1)

release-version: test
ifdef VERSION
	@${DOCKER_BUILD_CMD} -t $(DOCKER_REPO):$(VERSION) --push . && echo "✅ Release ${VERSION} built, tagged, and pushed to docker.io repo." || (echo "❌ Release ${VERSION} failed to build docker repo package." && exit 1)
    @docker pull ${DOCKER_REPO}:${VERSION} && echo "✅ Release ${VERSION} successfully pulled from docker.io repo." || (echo "❌ Release ${VERSION} failed pulling back from docker repo." && exit 1)
	@docker tag $(DOCKER_REPO):$(VERSION) ${GHCR_REPO}:${VERSION} && echo "✅ Release ${VERSION} tagged for ghcr repo." || (echo "❌ Release ${VERSION} tagging for ghcr repo." && exit 1)
	@docker push ${GHCR_REPO}:${VERSION} && echo "✅ Release ${VERSION} pushed to ghcr repo." || (echo "❌ Release ${VERSION} failed pushing to ghcr repo." && exit 1)
else
	@echo "❌ Please provide a version number using 'make release-version VERSION=x.y'"
endif

test: lint pr-test

pr-test: test-env-start test-run-all test-env-stop

test-env-start: test-env-stop
	$(DOCKER_COMPOSE_CMD) up --no-deps --build --force-recreate --remove-orphans --detach

test-env-stop:
	$(DOCKER_COMPOSE_CMD) down --remove-orphans --volumes

test-run-sonar:
	sonar-scanner \
		-Dsonar.organization=${GLUETRANS_SONAR_ORGANIZATION} \
		-Dsonar.projectKey=${GLUETRANS_SONAR_PROJECT_KEY} \
		-Dsonar.sources=. \
		-Dsonar.host.url=https://sonarcloud.io

test-run-all:
	@test/run-smoke.sh && echo "✅ All smoke tests pass." || (echo "❌ Smoke tests failed." && exit 1)

.PHONY: all build lint release-dev release-latest release-version test test-env-start test-env-stop test-run-all
