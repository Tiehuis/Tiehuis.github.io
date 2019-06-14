MD   := $(wildcard ./blog/*.md)
TMPL := $(wildcard ./build/*)
HTML := $(MD:.md=.html)

build: $(HTML) atom.xml

blog/%.html: blog/%.md $(TMPL)
	@echo $@
	@bash -c 'cat 															\
		./build/1.html ./build/1.css ./build/2.html 						\
		<(cmark --unsafe --smart $< | sed "s/^/      /" | sed "s/[ ]*$$//") \
		./build/3.html > $@'

atom.xml: genfeed $(HTML)
	@echo $@
	@bash genfeed

watch:
	@while inotifywait -qq -e move -e modify -e create -e delete --exclude './blog/*.html' ./blog; do \
		make -s; \
	done

.PHONY: watch
