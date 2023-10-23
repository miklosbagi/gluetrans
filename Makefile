SHELL := /bin/bash
DOCKER_REPO := miklosbagi/gluetranspia
GHCR_REPO := ghcr.io/miklosbagi/gluetranspia
DOCKER_BUILD_CMD := docker buildx build --platform linux/amd64,linux/arm64

.PHONY: release-dev release-latest release-version all build

build:
	${DOCKER_BUILD_CMD} .

test: lint

lint: 
	@shellcheck entrypoint.sh && echo "✅ Entrypoint.sh linting passed." || (echo "❌ Entryppoint.sh linting failed." && exit 1)
	@hadolint Dockerfile && echo "✅ Dockerfile linting passed." || (echo "❌ Dockerfile linting failed." && exit 1)

release-dev: test
	@${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:dev --push . && echo "✅ Release dev built, tagged, and pushed to docker.io repo." || (echo "❌ Release dev failed to build docker repo package." && exit 1)
	@docker pull ${DOCKER_REPO}:dev && echo "✅ Release dev successfully pulled from docker.io repo." || (echo "❌ Release dev failed pulling back from docker repo" && exit 1)
	@docker tag ${DOCKER_REPO}:dev ${GHCR_REPO}:dev && echo "✅ Release dev tagged for ghcr repo." || (echo "❌ Release dev tagging for ghcr repo" && exit 1)
	@docker push ${GHCR_REPO}:dev && echo "✅ Release dev pushed to ghcr repo." || (echo "❌ Release dev failed pushing to ghcr repo" && exit 1)

release-latest: test
	@${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:latest --push . && echo "✅ Release latest built, tagged, and pushed to docker.io repo." || (echo "❌ Release latest failed to build docker repo package." && exit 1)
	@docker pull ${DOCKER_REPO}:latest && echo "✅ Release latest successfully pulled from docker.io repo." || (echo "❌ Release latest failed pulling back from docker repo" && exit 1)
	@docker tag ${DOCKER_REPO}:latest ${GHCR_REPO}:latest && echo "✅ Release latest tagged for ghcr repo." || (echo "❌ Release latest tagging for ghcr repo" && exit 1)
	@docker push ${GHCR_REPO}:latest && echo "✅ Release latest pushed to ghcr repo." || (echo "❌ Release latest failed pushing to ghcr repo" && exit 1)

release-version: test
ifdef VERSION
	@${DOCKER_BUILD_CMD} -t $(DOCKER_REPO):$(VERSION) --push . && echo "✅ Release ${VERSION} built, tagged, and pushed to docker.io repo." || (echo "❌ Release ${VERSION} failed to build docker repo package." && exit 1)
    @docker pull ${DOCKER_REPO}:${VERSION} && echo "✅ Release ${VERSION} successfully pulled from docker.io repo." || (echo "❌ Release ${VERSION} failed pulling back from docker repo" && exit 1)
	@docker tag $(DOCKER_REPO):$(VERSION) ${GHCR_REPO}:${VERSION} && echo "✅ Release ${VERSION} tagged for ghcr repo." || (echo "❌ Release ${VERSION} tagging for ghcr repo" && exit 1)
	@docker push ${GHCR_REPO}:${VERSION} && echo "✅ Release ${VERSION} pushed to ghcr repo." || (echo "❌ Release ${VERSION} failed pushing to ghcr repo" && exit 1)
else
	@echo "❌ Please provide a version number using 'make release-version VERSION=x.y'"
endif
