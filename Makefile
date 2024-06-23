# SPDX-FileCopyrightText: 2019-present Open Networking Foundation <info@opennetworking.org>
#
# SPDX-License-Identifier: Apache-2.0

export CGO_ENABLED=1
export GO111MODULE=on

.PHONY: build

TARGET := onos-kpimon
TARGET_TEST := onos-kpimon-test
DOCKER_TAG ?= latest # If the DOCKER_TAG variable is not assigned a value from the parent files (master.yml, push.yml), it defaults to 'latest'.
ONOS_PROTOC_VERSION := v0.6.6
BUF_VERSION := 0.27.1

build: # @HELP build the Go binaries and run all validations (default)
build:
	GOPRIVATE="github.com/onosproject/*" go build -o build/_output/${TARGET} ./cmd/${TARGET}

build-tools:=$(shell if [ ! -d "./build/build-tools" ]; then cd build && git clone https://github.com/onosproject/build-tools.git; fi)
include ./build/build-tools/make/onf-common.mk

test: # @HELP run the unit tests and source code validation
test: build deps linters license
	go test -race github.com/onosproject/${TARGET}/pkg/...
	go test -race github.com/onosproject/${TARGET}/cmd/...

#jenkins-test:  # @HELP run the unit tests and source code validation producing a junit style report for Jenkins
#jenkins-test: deps license linters
#	TEST_PACKAGES=github.com/onosproject/${TARGET}/... ./build/build-tools/build/jenkins/make-unit

buflint: #@HELP run the "buf check lint" command on the proto files in 'api'
	docker run -it -v `pwd`:/go/src/github.com/onosproject/${TARGET} \
		-w /go/src/github.com/onosproject/${TARGET}/api \
		bufbuild/buf:${BUF_VERSION} check lint

protos: # @HELP compile the protobuf files (using protoc-go Docker)
protos:
	docker run -it -v `pwd`:/go/src/github.com/onosproject/${TARGET} \
		-w /go/src/github.com/onosproject/${TARGET} \
		--entrypoint build/bin/compile-protos.sh \
		onosproject/protoc-go:${ONOS_PROTOC_VERSION}

helmit-kpm: integration-test-namespace # @HELP run MHO tests locally
	helmit test -n test ./cmd/${TARGET_TEST} --timeout 30m --no-teardown --suite kpm

helmit-ha: integration-test-namespace # @HELP run MHO HA tests locally
	helmit test -n test ./cmd/${TARGET_TEST} --timeout 30m --no-teardown --suite ha

integration-tests: helmit-kpm helmit-ha # @HELP run all MHO integration tests locally

docker-build: # @HELP build target Docker image
docker-build:
	@go mod vendor
	docker build . -f build/${TARGET}/Dockerfile \
		-t ${DOCKER_REPOSITORY}${TARGET}:${DOCKER_TAG}
	@rm -rf vendor

images: # @HELP build all Docker images
images: build docker-build

docker-push:
	docker push ${DOCKER_REPOSITORY}${TARGET}:${DOCKER_TAG}

kind: # @HELP build Docker images and add them to the currently configured kind cluster
kind: images
	@if [ "`kind get clusters`" = '' ]; then echo "no kind cluster found" && exit 1; fi
	kind load docker-image ${DOCKER_REPOSITORY}${TARGET}:${DOCKER_TAG}

all: build images

publish: # @HELP publish version on github and dockerhub
	./build/build-tools/publish-version ${VERSION} ${DOCKER_REPOSITORY}${TARGET}

#jenkins-publish: jenkins-tools # @HELP Jenkins calls this to publish artifacts
#	./build/bin/push-images
#	./build/build-tools/release-merge-commit

clean:: # @HELP remove all the build artifacts
	rm -rf ./build/_output ./vendor ./cmd/${TARGET}/${TARGET} ./cmd/onos/onos
	go clean -testcache github.com/onosproject/${TARGET}/...
