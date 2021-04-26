DOCKER = docker run --rm -it -v $(PWD):/src:rw,delegated
IMAGE = klakegg/hugo:0.82.0-alpine

.PHONY: run
run:
	$(DOCKER) -p 1313:1313 $(IMAGE) server --baseURL "http://$(shell ipconfig getifaddr en0):1313/blog/"

.PHONY: shell
shell:
	$(DOCKER) --entrypoint sh $(IMAGE)
