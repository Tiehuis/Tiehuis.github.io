# A Simpler Blog
<div class="published"><time datetime="2019-05-13">13 May 2019</time></div>

Previously I was using Jekyll for this blog. It worked okay but I disliked
having the ruby dependencies and felt it was a bit too complicated for
my intended use-case.

This was my `Gemfile.lock` prior to the change:

```
GEM
  remote: https://rubygems.org/
  specs:
    addressable (2.5.0)
      public_suffix (~> 2.0, >= 2.0.2)
    colorator (1.1.0)
    ffi (1.9.17)
    forwardable-extended (2.6.0)
    jekyll (3.3.1)
      addressable (~> 2.4)
      colorator (~> 1.0)
      jekyll-sass-converter (~> 1.0)
      jekyll-watch (~> 1.1)
      kramdown (~> 1.3)
      liquid (~> 3.0)
      mercenary (~> 0.3.3)
      pathutil (~> 0.9)
      rouge (~> 1.7)
      safe_yaml (~> 1.0)
    jekyll-feed (0.9.2)
      jekyll (~> 3.3)
    jekyll-last-modified-at (1.0.1)
      jekyll (~> 3.3)
      posix-spawn (~> 0.3.9)
    jekyll-sass-converter (1.5.0)
      sass (~> 3.4)
    jekyll-watch (1.5.0)
      listen (~> 3.0, < 3.1)
    kramdown (1.13.2)
    liquid (3.0.6)
    listen (3.0.8)
      rb-fsevent (~> 0.9, >= 0.9.4)
      rb-inotify (~> 0.9, >= 0.9.7)
    mercenary (0.3.6)
    pathutil (0.14.0)
      forwardable-extended (~> 2.6)
    posix-spawn (0.3.13)
    public_suffix (2.0.5)
    rb-fsevent (0.9.8)
    rb-inotify (0.9.7)
      ffi (>= 0.5.0)
    rouge (1.11.1)
    safe_yaml (1.0.4)
    sass (3.4.23)

PLATFORMS
  ruby

DEPENDENCIES
  jekyll
  jekyll-feed
  jekyll-last-modified-at

BUNDLED WITH
1.15.2
```

I replaced all this with the following dependencies:
 - [cmark](https://github.com/commonmark/cmark)
 - make (GNU)
 - bash
 - inotify (optional)

All these are found on any typical linux installation except cmark, which is a
small C library/executable that only requires libc.

Github by default builds your Jekyll pages repository. Since I no longer use it, I
now need to run `make` and build the html pages prior to pushing, but I
consider this minimal extra cost. Further, it allows me to support mirroring
this blog automatically to [gitlab pages](https://tiehuis.gitlab.io), which
do not support Jekyll. This is a very simple setup. I added a `.gitlab-ci.yml`
file, then enabled auto-mirroring in gitlab and pointed it to the repository on
github. I finally configured Gitlab's CI to run on each commit.

I considered writing raw html directly and having no markdown to html step but
this seemed a bit too far. Minor things such as escaping code blocks and
maintaining open/end tags kept me with markdown. My index page currently is
raw html but I consider this a one-off (besides updating the index). The styling
also is slightly different to the standard post.

I briefly considered using a simple template system, but considering my needs I
decided against that and simply concatenate a few html files to build the
resulting posts. You can see this in the Makefile (which contains only one
essential step):

```
MD := $(wildcard ./blog/*.md)
TMPL := $(wildcard ./build/*)
HTML := $(MD:.md=.html)

build: $(HTML)

blog/%.html: blog/%.md $(TMPL)
	@echo $<
@bash -c 'cat ./build/1.html ./build/1.css ./build/2.html <(cmark --smart $<) ./build/3.html > $@'
```

Finally, a change I had been meaning to do for a while anyway was to adjust the
path of the blog entries behind the `/blog` path. I've kept the existing links
as extra html pages which perform a simple `http-equiv="refresh"` redirect to
the new pages so existing linked content will still continue to work.

I'm pretty happy with the result. There is less to go wrong here for me and I've
kept practically all of the same functionality (besides an auto-generated atom
feed) while minimizing dependencies. I'd strongly urge people to take a step
back every now and then and see if there current solution isn't too much for
them and if it can't be replaced. I spent a fair bit of time reading Jekyll
documentation, looking for plugins that I don't need and determining how the
templating system worked. At least for my use-case, all I really needed was to
generate html from markdown and cat some files together.
