#!/bin/sh
#
# karabiner-lint.sh: check tide's and conf's Karabiner rule files with
# Karabiner-Elements' own checker, `karabiner_cli
# --lint-complex-modifications`, as each file is and as tide copies it for
# its modifier swap (dashboard/karabiner.js's swapRule, SPEC.md §7.1).
# macOS only; CI's macOS job runs it.
#
#   karabiner-lint.sh CONF_CHECKOUT
#
# Karabiner isn't installed: its latest release's disk image is opened, its
# installer package unpacked, and karabiner_cli run from there, so nothing
# needs an admin or a system extension. Unpinned, so a release that checks
# more turns this red until the rules meet it; the version is printed.

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
conf=${1:?usage: karabiner-lint.sh CONF_CHECKOUT}
dir=$(mktemp -d)
trap 'hdiutil detach "$dir/mnt" >/dev/null 2>&1 || true; rm -rf "$dir"' EXIT

gh release download --repo pqrs-org/Karabiner-Elements --pattern '*.dmg' --dir "$dir"
dmg=$(find "$dir" -maxdepth 1 -name '*.dmg' | head -n 1)
hdiutil attach -nobrowse -readonly -mountpoint "$dir/mnt" "$dmg" >/dev/null
pkg=$(find "$dir/mnt" -maxdepth 1 -name '*.pkg' | head -n 1)
pkgutil --expand-full "$pkg" "$dir/pkg"
cli=$(find "$dir/pkg" -name karabiner_cli -type f -perm -u+x | head -n 1)
if test -z "$cli"; then
    echo "karabiner-lint: no karabiner_cli in $(basename "$dmg")" >&2
    exit 1
fi
echo "karabiner-lint: $("$cli" --version)"

# The files as they are, and as tide copies them once Karabiner swaps the
# modifiers.
mkdir "$dir/files" "$dir/swapped"
cp "$repo"/hammerspoon/tide/karabiner/*.json "$conf"/config/karabiner/assets/complex_modifications/*.json "$dir/files/"
cp "$repo/hammerspoon/tide/dashboard/karabiner.js" "$dir/karabiner.mjs"
node "$repo/ci/karabiner_swapped.mjs" "$dir/karabiner.mjs" "$dir/files" "$dir/swapped"

"$cli" --lint-complex-modifications "$dir"/files/*.json "$dir"/swapped/*.json
