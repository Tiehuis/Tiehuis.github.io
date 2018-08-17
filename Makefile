MD := $(wildcard ./blog/*.md)
HTML := $(MD:.md=.html)

build: $(HTML)

blog/%.html: blog/%.md
	@echo $<
	@bash -c 'cat ./build/1.html ./build/1.css ./build/2.html <(cmark --smart $<) ./build/3.html > $@'

watch:
	@while inotifywait -qq -e move -e modify -e create -e delete --exclude './blog/*.html' ./blog; do \
		make -s; \
	done

.PHONY: watch
