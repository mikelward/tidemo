#!/bin/bash
#
# install-check.sh: run tide's installer for real on a fresh macOS runner,
# then again, and check what it leaves (CI's macOS `install` job). Exits 1
# on anything missing or wrong, saying what.

set -u

repo=$(cd "$(dirname "$0")/.." && pwd)
failed=0
fail() {
    echo "FAIL $*"
    failed=1
}
ok() {
    echo "ok $*"
}

if test -e "$HOME/.hammerspoon"; then
    echo "install-check: $HOME/.hammerspoon exists; this is for a fresh runner" >&2
    exit 1
fi

# The default Super key, left Option, which installs Karabiner and tide's rule.
if "$repo/install/tide-setup" --verbose --super option; then
    ok "the installer finished"
else
    fail "the installer exited $?"
fi

for app in Hammerspoon LinearMouse Karabiner-Elements; do
    if test -d "/Applications/$app.app"; then ok "$app installed"; else fail "no /Applications/$app.app"; fi
done
if command -v blueutil >/dev/null; then ok "blueutil installed"; else fail "no blueutil"; fi
ddc=ddcctl
test "$(uname -m)" = arm64 && ddc=m1ddc
if command -v "$ddc" >/dev/null; then ok "$ddc installed"; else fail "no $ddc"; fi

init=$HOME/.hammerspoon/init.lua
if grep -q 'require("tide")' "$init" 2>/dev/null; then ok "init.lua starts tide"; else fail "init.lua doesn't start tide: $(cat "$init" 2>&1)"; fi
if test -f "$HOME/.hammerspoon/tide/init.lua"; then ok "tide copied in"; else fail "no ~/.hammerspoon/tide/init.lua"; fi

hotkey() {
    plutil -extract "AppleSymbolicHotKeys.$1.enabled" raw "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist" 2>&1
}
test "$(hotkey 64)" = true && ok "Spotlight on Cmd+Space" || fail "Spotlight's hotkey (64) is $(hotkey 64)"
for id in 79 81 118 126; do
    test "$(hotkey "$id")" = false && ok "hotkey $id off" || fail "hotkey $id is $(hotkey "$id")"
done
test "$(defaults read NSGlobalDomain _HIHideMenuBar 2>&1)" = 0 && ok "menu bar shown" || fail "_HIHideMenuBar is $(defaults read NSGlobalDomain _HIHideMenuBar 2>&1)"

rule=$HOME/.config/karabiner/assets/complex_modifications/tide.json
if cmp -s "$rule" "$repo/hammerspoon/tide/karabiner/tide-option.json"; then ok "tide's left Option rule in Karabiner's folder"; else fail "$rule isn't tide-option.json"; fi

# Again, as a second run of setup would: nothing to do, and nothing undone.
before=$(cat "$init" 2>/dev/null)
if "$repo/install/tide-setup" --super option >/dev/null; then ok "a second run finished"; else fail "a second run exited $?"; fi
test "$(cat "$init" 2>/dev/null)" = "$before" && ok "init.lua as it was" || fail "a second run changed init.lua"
cmp -s "$rule" "$repo/hammerspoon/tide/karabiner/tide-option.json" && ok "the rule as it was" || fail "a second run changed $rule"

# The installer starts Hammerspoon; nothing here needs it.
killall Hammerspoon 2>/dev/null || true
exit $failed
