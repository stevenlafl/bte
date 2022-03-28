.PHONY: build

IMAGE := "stevenlafl/bte:latest"
IMAGE_INTERMEDIATE := "stevenlafl/bte:builder"

build:
	docker build -t ${IMAGE} --progress plain --target tools .

builder:
	docker build -t IMAGE_INTERMEDIATE --progress plain --target builder .

ssh-builder:
	docker run -it --entrypoint /bin/bash IMAGE_INTERMEDIATE

ssh:
	docker run -it --entrypoint /bin/bash ${IMAGE}