# tidemo
#
#   make version  print the version: the commit count, as each release's tag
#                 has it (v<version>)
#   make test     run the tests (plain Lua 5.4 and bash, no Mac needed)
#   make test-install  run only the installer's tests (install/tide-setup)
#   make lint     check every Lua file parses
#   make install  copy the Hammerspoon modules to ~/.hammerspoon/tide
#   make check-tide   compare the copies of tide for Linux's geometry, direction,
#                 clocks, startup, clipboard, steps, layouts, input, fuzzy,
#                 workspaces, bar settings, bar layout, settings search and cities modules,
#                 character and city lists and key presets with a tide checkout
#                 (TIDE=../tide by default), and the layout defaults and standing
#                 workspaces tide restates with its
#   make check-tideco   compare the dashboard's copies of tide for Chrome's clock
#                 modules and launcher page with a tideco checkout
#                 (TIDECO=../tideco by default)
#   make icons    render tide's logo to hammerspoon/tide/icons/*.png (needs
#                 Node and Playwright's Chromium; skips with a note without them)
#   make mocks    render the bar in fixed states to mocks/*.png (needs Node
#                 and Playwright's Chromium; skips with a note without them)

LUA ?= $(shell command -v lua5.4 || command -v lua)
LUAC ?= $(shell command -v luac5.4 || command -v luac)
HAMMERSPOON_DIR ?= $(HOME)/.hammerspoon
TIDE ?= ../tide
TIDECO ?= ../tideco
# The files that are tide for Linux's, copied unchanged: its path=ours.
TIDE_COPIES := hypr/tide/geometry.lua=hammerspoon/tide/geometry.lua \
	hypr/tide/direction.lua=hammerspoon/tide/direction.lua \
	shell/lib/clocks.mjs=hammerspoon/tide/dashboard/tide-clocks.js \
	shell/lib/startup.mjs=hammerspoon/tide/dashboard/tide-startup.js \
	shell/lib/clipboard.mjs=hammerspoon/tide/dashboard/tide-clipboard.js \
	shell/lib/steps.mjs=hammerspoon/tide/dashboard/tide-steps.js \
	shell/lib/layouts.mjs=hammerspoon/tide/dashboard/tide-layouts.js \
	shell/lib/input.mjs=hammerspoon/tide/dashboard/tide-input.js \
	shell/lib/appearance.mjs=hammerspoon/tide/dashboard/tide-appearance.js \
	shell/lib/idle.mjs=hammerspoon/tide/dashboard/tide-idle.js \
	shell/lib/dnd.mjs=hammerspoon/tide/dashboard/tide-dnd.js \
	shell/lib/palette.mjs=hammerspoon/tide/dashboard/tide-palette.js \
	shell/lib/fuzzy.mjs=hammerspoon/tide/dashboard/tide-fuzzy.js \
	shell/lib/cities.mjs=hammerspoon/tide/dashboard/tide-cities.js \
	shell/cities/cities.tsv=hammerspoon/tide/cities.tsv \
	shell/lib/span.mjs=hammerspoon/tide/dashboard/tide-span.js \
	shell/lib/workspacenames.mjs=hammerspoon/tide/dashboard/tide-workspacenames.js \
	shell/lib/workspacepage.mjs=hammerspoon/tide/dashboard/tide-workspacepage.js \
	shell/lib/barsettings.mjs=hammerspoon/tide/dashboard/tide-barsettings.js \
	shell/lib/barlayout.mjs=hammerspoon/tide/dashboard/tide-barlayout.js \
	shell/lib/settingssearch.mjs=hammerspoon/tide/dashboard/tide-settingssearch.js \
	shell/chars/chars.tsv=hammerspoon/tide/chars.tsv \
	shell/icons/tide-symbolic.svg=hammerspoon/tide/icons/tide-symbolic.svg
# The dashboard files that are tide for Chrome's, copied unchanged.
TIDECO_FILES := clocks.js calendar.js clockview.js launcher.css \
	launcherview.js launcher.js extras.js keepawake.js platform.js apps.js workspaces.js unread.js watchers.js \
	barlayout.js barcolor.js
export LUA_PATH := hammerspoon/?.lua;hammerspoon/?/init.lua;tests/?.lua;;

LUA_FILES := $(wildcard hammerspoon/tide/*.lua hammerspoon/tilemo/*.lua hammerspoon/timo/*.lua tests/*.lua ci/*.lua)
TESTS := $(wildcard tests/*_test.lua)

.PHONY: test test-install lint install sync check-tide check-geometry check-tideco mocks icons version unshallow-check

# The version is the number of commits, so each push to main is a higher
# one, released by CI as v<version> (.github/workflows/release.yml).
version: unshallow-check
	@git rev-list --count HEAD

# A shallow clone counts only the commits it has, which would make a lower
# version than one already released.
unshallow-check:
	@if test "$$(git rev-parse --is-shallow-repository)" != false; then \
		echo "the history is shallow, so the commit count is wrong; run git fetch --unshallow" >&2; exit 1; fi

test: test-install
	@status=0; for t in $(TESTS); do $(LUA) $$t || status=1; done; exit $$status

# The installer's own tests mock Homebrew, defaults and make, so they run off
# a Mac too.
test-install:
	install/tide-setup_test
	ci/committed_test

lint:
	@for f in $(LUA_FILES); do $(LUAC) -p $$f || exit 1; done

# An init.lua from before a rename says require("tilemo") or require("timo"):
# each shim takes the place of that name's own init.lua and loads tide. The
# rest of an old ~/.hammerspoon/tilemo stays, unused.
install:
	mkdir -p $(HAMMERSPOON_DIR)/tide
	cp hammerspoon/tide/*.lua $(HAMMERSPOON_DIR)/tide/
	cp hammerspoon/tide/chars.tsv hammerspoon/tide/LICENSE-UNICODE $(HAMMERSPOON_DIR)/tide/
	cp hammerspoon/tide/cities.tsv $(HAMMERSPOON_DIR)/tide/
	cp hammerspoon/tide/compose.tsv hammerspoon/tide/LICENSE-X11 $(HAMMERSPOON_DIR)/tide/
	mkdir -p $(HAMMERSPOON_DIR)/tide/icons
	cp hammerspoon/tide/icons/*.png $(HAMMERSPOON_DIR)/tide/icons/
	mkdir -p $(HAMMERSPOON_DIR)/tide/karabiner
	cp hammerspoon/tide/karabiner/*.json $(HAMMERSPOON_DIR)/tide/karabiner/
	mkdir -p $(HAMMERSPOON_DIR)/tide/dashboard
	cp hammerspoon/tide/dashboard/* $(HAMMERSPOON_DIR)/tide/dashboard/
	mkdir -p $(HAMMERSPOON_DIR)/tilemo $(HAMMERSPOON_DIR)/timo
	cp hammerspoon/tilemo/init.lua $(HAMMERSPOON_DIR)/tilemo/
	cp hammerspoon/timo/init.lua $(HAMMERSPOON_DIR)/timo/
	@echo "Add to $(HAMMERSPOON_DIR)/init.lua:"
	@echo '  tide = require("tide")'
	@echo '  tide.start({})'

# geometry.lua is tide for Linux's, copied unchanged, so a workspace looks the
# same on both desktops; so is its clocks module, so this reads and writes tide
# for Linux's clocks files as it does, and its startup, clipboard and input modules, for startup.json, clipboard.json and input.json, and its Workspaces page's, for workspaces.json; so is the picker's character list, the Appearance page's city picker and its list, and
# the logo, which `make icons` renders. The bar's chips and the settings
# window take tide for Linux's palette's colors. layout.lua's defaults and
# wm.lua's standing workspaces restate tide for Linux's, so they're compared
# too (ci/check_defaults.lua), deliberate differences listed there.
check-tide:
	$(foreach p,$(TIDE_COPIES),cmp $(TIDE)/$(word 1,$(subst =, ,$(p))) $(word 2,$(subst =, ,$(p))) &&) true
	$(LUA) ci/check_chip_colors.lua $(TIDE)/theme/palette.json hammerspoon/tide/dashboard/bar.html
	$(LUA) ci/check_settings_colors.lua $(TIDE)/theme/palette.json hammerspoon/tide/dashboard/settings.html
	$(LUA) ci/check_keymaps.lua $(TIDE)/shell/lib/keymaps.mjs
	$(LUA) ci/check_defaults.lua $(TIDE)

check-geometry: check-tide

# CI checks the copies against the tide for Linux and tide for Chrome commits
# in UPSTREAM, so a change there can't turn a pull request here red. `make
# sync` copies the files afresh from your checkouts, records their commits,
# and checks the rest: the launcher page's markup and ci/'s checks still
# need a hand where they differ.
sync:
	ci/committed.sh $(TIDE) $(TIDECO)
	$(foreach p,$(TIDE_COPIES),cp $(TIDE)/$(word 1,$(subst =, ,$(p))) $(word 2,$(subst =, ,$(p))) &&) true
	$(foreach f,$(TIDECO_FILES),cp $(TIDECO)/src/$(f) hammerspoon/tide/dashboard/$(f) &&) true
	printf '%s\n' "# The tide for Linux and tide for Chrome commits copied here (make sync)." \
		"tide $$(git -C $(TIDE) rev-parse HEAD)" "tideco $$(git -C $(TIDECO) rev-parse HEAD)" > UPSTREAM
	$(MAKE) --no-print-directory check-tide check-tideco

# The dashboard's clocks, calendar and styles are tide for Chrome's, so the two
# dashboards agree; so is the dashboard launcher's page and what it imports.
check-tideco:
	@for f in $(TIDECO_FILES); do cmp $(TIDECO)/src/$$f hammerspoon/tide/dashboard/$$f || exit 1; done
	@# The launcher page's markup is launcher.html's body, around tide's script.
	@dir=$$(mktemp -d) || exit 1; \
	sed -n '/^<body>$$/,/^<\/body>$$/p' $(TIDECO)/src/launcher.html | sed '1d;$$d' > "$$dir/theirs"; \
	sed -n '/^<body>$$/,/^<script>$$/p' hammerspoon/tide/dashboard/launcherpage.html | sed '1d;$$d' > "$$dir/ours"; \
	if test -s "$$dir/theirs" && cmp "$$dir/theirs" "$$dir/ours"; then status=0; else \
		echo "dashboard/launcherpage.html: its body isn't tide for Chrome's launcher.html's"; status=1; fi; \
	rm -rf "$$dir"; exit $$status

# The bar's page as tide builds it, rendered in fixed states. The page is
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

# tide's logo as tide shows it (brand.lua), from the copy of tide's SVG.
icons:
	NODE_PATH="$$(npm root -g)" node hammerspoon/tide/icons/render.cjs
