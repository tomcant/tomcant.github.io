DOCKER = docker run --rm -it -v $(PWD):/src:rw,delegated
IMAGE = klakegg/hugo:0.82.0-alpine

.PHONY: run
run:
	$(DOCKER) -p 1313:1313 $(IMAGE) server

.PHONY: shell
shell:
	$(DOCKER) --entrypoint sh $(IMAGE)
