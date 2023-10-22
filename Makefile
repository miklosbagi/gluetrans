SHELL := /bin/bash
DOCKER_REPO := miklosbagi/gluetranspia
DOCKER_BUILD_CMD := docker buildx build --platform linux/amd64,linux/arm64

.PHONY: release-dev release-latest release-version all build

build:
	${DOCKER_BUILD_CMD} .

release-dev:
	${DOCKER_BUILD_CMD} -t miklosbagi/gluetranspia:dev --push .

release-latest:
	${DOCKER_BUILD_CMD} -t miklosbagi/gluetranspia:latest --push .

release-version:
ifdef VERSION
	${DOCKER_BUILD_CMD} -t $(DOCKER_REPO):$(VERSION) --push .
else
	@echo "Please provide a version number using 'make release-version VERSION=x.y'"
endif
