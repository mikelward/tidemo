# tilemo
#
#   make test     run the tests (plain Lua 5.4, no Mac needed)
#   make lint     check every Lua file parses
#   make install  copy the Hammerspoon modules to ~/.hammerspoon/tilemo
#   make check-tide   compare tilemo's copies of tide's geometry, direction, clocks,
#                 startup, clipboard, steps, layouts, input, fuzzy and workspaces modules and character list with a tide checkout (TIDE=../tide
#                 by default)
#   make check-tileco   compare the dashboard's copies of tileco's clock
#                 modules and launcher page with a tileco checkout
#                 (TILECO=../tileco by default)
#   make icons    render tide's logo to hammerspoon/tilemo/icons/*.png (needs
#                 Node and Playwright's Chromium; skips with a note without them)
#   make mocks    render the bar in fixed states to mocks/*.png (needs Node
#                 and Playwright's Chromium; skips with a note without them)

LUA ?= $(shell command -v lua5.4 || command -v lua)
LUAC ?= $(shell command -v luac5.4 || command -v luac)
HAMMERSPOON_DIR ?= $(HOME)/.hammerspoon
TIDE ?= ../tide
TILECO ?= ../tileco
# The dashboard files that are tileco's, copied unchanged.
TILECO_FILES := clocks.js calendar.js clockview.js launcher.css \
	launcherview.js launcher.js extras.js keepawake.js platform.js apps.js workspaces.js unread.js watchers.js
export LUA_PATH := hammerspoon/?.lua;hammerspoon/?/init.lua;tests/?.lua;;

LUA_FILES := $(wildcard hammerspoon/tilemo/*.lua hammerspoon/timo/*.lua tests/*.lua ci/*.lua)
TESTS := $(wildcard tests/*_test.lua)

.PHONY: test lint install check-tide check-geometry check-tileco mocks icons

test:
	@status=0; for t in $(TESTS); do $(LUA) $$t || status=1; done; exit $$status

lint:
	@for f in $(LUA_FILES); do $(LUAC) -p $$f || exit 1; done

# An init.lua from before the rename says require("timo"): the shim takes
# the place of timo's own init.lua and loads tilemo.
install:
	mkdir -p $(HAMMERSPOON_DIR)/tilemo
	cp hammerspoon/tilemo/*.lua $(HAMMERSPOON_DIR)/tilemo/
	cp hammerspoon/tilemo/chars.tsv hammerspoon/tilemo/LICENSE-UNICODE $(HAMMERSPOON_DIR)/tilemo/
	mkdir -p $(HAMMERSPOON_DIR)/tilemo/icons
	cp hammerspoon/tilemo/icons/*.png $(HAMMERSPOON_DIR)/tilemo/icons/
	mkdir -p $(HAMMERSPOON_DIR)/tilemo/dashboard
	cp hammerspoon/tilemo/dashboard/* $(HAMMERSPOON_DIR)/tilemo/dashboard/
	mkdir -p $(HAMMERSPOON_DIR)/timo
	cp hammerspoon/timo/init.lua $(HAMMERSPOON_DIR)/timo/
	@echo "Add to $(HAMMERSPOON_DIR)/init.lua:"
	@echo '  tilemo = require("tilemo")'
	@echo '  tilemo.start({})'

# geometry.lua is tide's, copied unchanged, so a workspace looks the same on
# both desktops; so is its clocks module, so tilemo reads and writes tide's
# clocks files as tide does, and its startup, clipboard and input modules, for startup.json, clipboard.json and input.json, and its Workspaces page's, for workspaces.json; so is the picker's character list, and
# the logo, which `make icons` renders.
check-tide:
	cmp $(TIDE)/hypr/tide/geometry.lua hammerspoon/tilemo/geometry.lua
	cmp $(TIDE)/hypr/tide/direction.lua hammerspoon/tilemo/direction.lua
	cmp $(TIDE)/shell/lib/clocks.mjs hammerspoon/tilemo/dashboard/tide-clocks.js
	cmp $(TIDE)/shell/lib/startup.mjs hammerspoon/tilemo/dashboard/tide-startup.js
	cmp $(TIDE)/shell/lib/clipboard.mjs hammerspoon/tilemo/dashboard/tide-clipboard.js
	cmp $(TIDE)/shell/lib/steps.mjs hammerspoon/tilemo/dashboard/tide-steps.js
	cmp $(TIDE)/shell/lib/layouts.mjs hammerspoon/tilemo/dashboard/tide-layouts.js
	cmp $(TIDE)/shell/lib/input.mjs hammerspoon/tilemo/dashboard/tide-input.js
	cmp $(TIDE)/shell/lib/fuzzy.mjs hammerspoon/tilemo/dashboard/tide-fuzzy.js
	cmp $(TIDE)/shell/lib/workspacenames.mjs hammerspoon/tilemo/dashboard/tide-workspacenames.js
	cmp $(TIDE)/shell/lib/workspacepage.mjs hammerspoon/tilemo/dashboard/tide-workspacepage.js
	cmp $(TIDE)/shell/chars/chars.tsv hammerspoon/tilemo/chars.tsv
	cmp $(TIDE)/shell/icons/tide-symbolic.svg hammerspoon/tilemo/icons/tide-symbolic.svg

check-geometry: check-tide

# The dashboard's clocks, calendar and styles are tileco's, so the two
# dashboards agree; so is the dashboard launcher's page and what it imports.
check-tileco:
	@for f in $(TILECO_FILES); do cmp $(TILECO)/src/$$f hammerspoon/tilemo/dashboard/$$f || exit 1; done
	@# The launcher page's markup is launcher.html's body, around tide's script.
	@dir=$$(mktemp -d) || exit 1; \
	sed -n '/^<body>$$/,/^<\/body>$$/p' $(TILECO)/src/launcher.html | sed '1d;$$d' > "$$dir/theirs"; \
	sed -n '/^<body>$$/,/^<script>$$/p' hammerspoon/tilemo/dashboard/launcherpage.html | sed '1d;$$d' > "$$dir/ours"; \
	if test -s "$$dir/theirs" && cmp "$$dir/theirs" "$$dir/ours"; then status=0; else \
		echo "dashboard/launcherpage.html: its body isn't tileco's launcher.html's"; status=1; fi; \
	rm -rf "$$dir"; exit $$status

# The bar's page as tilemo builds it, rendered in fixed states. The page is
# written to a temporary directory (as .html, so the browser reads it as a
# page), removed whether the render works or not.
mocks:
	@dir=$$(mktemp -d) || exit 1; \
	if $(LUA) mocks/page.lua > "$$dir/bar.html"; then \
		NODE_PATH="$$(npm root -g)" node mocks/render.cjs "$$dir/bar.html"; status=$$?; \
	else \
		status=1; \
	fi; \
	rm -rf "$$dir"; exit $$status

# tide's logo as tilemo shows it (brand.lua), from the copy of tide's SVG.
icons:
	NODE_PATH="$$(npm root -g)" node hammerspoon/tilemo/icons/render.cjs
