SHELL := /bin/bash
DOCKER_REPO := miklosbagi/gluetranspia
GHCR_REPO := ghcr.io/miklosbagi/gluetranspia
DOCKER_BUILD_CMD := docker buildx build --platform linux/amd64,linux/arm64

.PHONY: release-dev release-latest release-version all build

build:
	${DOCKER_BUILD_CMD} .

test: lint

lint: 
	shellcheck entrypoint.sh || (echo "Linting failed, exiting." && exit 1)

release-dev: test
	${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:dev --push .
	docker pull ${DOCKER_REPO}:dev
	docker tag ${DOCKER_REPO}:dev ${GHCR_REPO}:dev
	docker push ${GHCR_REPO}:dev

release-latest: test
	${DOCKER_BUILD_CMD} -t ${DOCKER_REPO}:latest --push .
	docker pull ${DOCKER_REPO}:latest
	docker tag ${DOCKER_REPO}:latest ${GHCR_REPO}:latest
	docker push ${GHCR_REPO}:latest

release-version: test
ifdef VERSION
	${DOCKER_BUILD_CMD} -t $(DOCKER_REPO):$(VERSION) --push .
        docker pull ${DOCKER_REPO}:${VERSION}
	docker tag $(DOCKER_REPO):$(VERSION) ${GHCR_REPO}:${VERSION}
	docker push ${GHCR_REPO}:${VERSION}
else
	@echo "Please provide a version number using 'make release-version VERSION=x.y'"
endif
