include ../includes.mk

# the filepath to this repository, relative to $GOPATH/src
repo_path = github.com/hkloudou/deis/router

GO_FILES = $(wildcard *.go)
GO_PACKAGES = cmd/boot logger tests
GO_PACKAGES_REPO_PATH = $(addprefix $(repo_path)/,$(GO_PACKAGES))

SHELL_SCRIPTS = $(shell find "." -name '*.sh') $(wildcard rootfs/bin/*)

COMPONENT = $(notdir $(repo_path))
IMAGE = $(IMAGE_PREFIX)$(COMPONENT):$(BUILD_TAG)
DEV_IMAGE = $(REGISTRY)$(IMAGE)
BUILD_IMAGE = $(COMPONENT)-build
BINARY_DEST_DIR = rootfs/bin

git:
	-git add .
	-git commit -m 'build auto commit'
	-git tag -f 0.1.0
	-git push origin master -f --tags
build: check-docker
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 godep go build -a -installsuffix -v -ldflags '-s' -o $(BINARY_DEST_DIR)/boot cmd/boot/boot.go || exit 1
	@$(call check-static-binary,rootfs/bin/boot)
	echo $(IMAGE)
	
	#build confd
	#hkloudou/gobuilder:alpine3.7-go1.10.1
	@docker run --rm --privileged=true -w /go/src/code/ hkloudou/gobuilder:alpine3.7-go1.10.1 go version
	docker run --rm --privileged=true -v $(GOPATH)/src/:/go/src/ -v $(PWD)/rootfs/usr/local/bin/:/go/bin/ -w /code/ hkloudou/gobuilder:alpine3.7-go1.10.1 go build -ldflags "-X main.GitSHA=${GIT_SHA}" -o /go/bin/confd github.com/hkloudou/confd
	
	#build router
	docker build -t $(IMAGE) .
	rm rootfs/bin/boot
	rm rootfs/usr/local/bin/confd
clean: check-docker check-registry
	docker rmi $(IMAGE)

full-clean: check-docker check-registry
	docker images -q $(IMAGE_PREFIX)$(COMPONENT) | xargs docker rmi -f

install: check-deisctl
	deisctl scale $(COMPONENT)=3

uninstall: check-deisctl
	deisctl scale $(COMPONENT)=0

start: check-deisctl
	deisctl start $(COMPONENT)@*

stop: check-deisctl
	deisctl stop $(COMPONENT)@*

restart: stop start

run: install start

dev-release: push set-image

push: check-registry
	docker tag $(IMAGE) $(DEV_IMAGE)
	docker push $(DEV_IMAGE)

set-image: check-deisctl
	deisctl config $(COMPONENT) set image=$(DEV_IMAGE)

release:
	docker push $(IMAGE)

deploy: build dev-release restart

test: test-style test-unit test-functional

test-functional:
	@$(MAKE) -C ../tests/ test-etcd
	GOPATH=`cd ../tests/ && godep path`:$(GOPATH) go test -v ./tests/...

test-style:
# display output, then check
	$(GOFMT) $(GO_PACKAGES) $(GO_FILES)
	@$(GOFMT) $(GO_PACKAGES) $(GO_FILES) | read; if [ $$? == 0 ]; then echo "gofmt check failed."; exit 1; fi
	$(GOVET) $(GO_PACKAGES_REPO_PATH)
	$(GOLINT) ./...
	shellcheck $(SHELL_SCRIPTS)

test-unit:
	@echo no unit tests
