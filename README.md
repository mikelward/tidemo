# tilemo

tide's tiling desktop, and tileco's launcher and dashboard, on macOS:
[tide](https://github.com/mikelward/tide) is the Linux desktop and
[tileco](https://github.com/mikelward/tileco) the chromeOS one.

**Status: exploration, with a first Hammerspoon version.** [SPEC.md](SPEC.md)
says what macOS allows for each of their features, how well, and at what
cost, and lists the open questions that decide what tilemo becomes.
[TODO.md](TODO.md) says what's next.

## The Hammerspoon version

It brings tide's desktop to macOS:
- tide's layouts and window keys (SPEC.md §5, §7.2);
- the mouse: edge drags, Super+drag and resize mode;
- focus follows mouse;
- named workspaces, each spanning every display with a layout of its own
  on each, in the order you made them, with "in" first for the apps you keep open all day (§6). An empty one
  goes once you leave it. A state saved with timo's or tilemo's old numbered
  workspaces is read once into ones named "1" to "9";
- the switcher, with Tab moving between apps and commands, the workspaces,
  open tabs, and the windows wanting attention: Super+Space opens it on
  apps, a lone Super tap on apps too and Super+A on attention (§9);
- Super+Return to go to a workspace by name and Super+Shift+Return to move
  a window to one, Super+Tab to flip between "in" and the last workspace,
  Super+End to the last one other than "in", Super+1…9 to the Nth
  workspace on the bar (Super+1 is "in") and Super+Shift+1…9 to send a
  window there, and Alt+Tab to swap with the master, with conf's Karabiner
  rule (§7.2);
- Super+Left and Right to select the window that way, going on to the next
  display at the edge, and Super+Shift+Left and Right to move it there;
  Super+PgUp and PgDn for the previous and next workspace with windows,
  with Shift to move the window there (§7.2);
- tide's bar along the top: tide's logo, opening the switcher, the
  workspaces, the window's title, the clocks
  and tilemo's own status items (input source, keep awake, camera,
  microphone, Bluetooth on or off with `blueutil`, Bluetooth headphones,
  speaker, opening a volume popover with a slider, mute and the outputs,
  and a monitor's own speakers over DDC with `m1ddc` or `ddcctl`, the
  volume keys included, network with a lock while a VPN is up, battery, CPU %, and a
  session menu to lock, log out, sleep, restart or shut down), with
  Super+Shift+M to mute the microphone
  (§7.2, §8, §14.2);
- Super+S to keep the display awake, and Super+P for presenter mode, Do
  Not Disturb and keep awake together (§10). Do Not Disturb needs two
  shortcuts you make in the Shortcuts app, "Do Not Disturb On" and "Do Not
  Disturb Off", each one Set Focus action; tilemo says so if they're
  missing, and keep awake works without them;
- tide's picker on Super+V: what you've copied since tilemo started,
  never a password manager's copy, and emoji and symbols by name (§9.1),
  with tide's Clipboard settings: the history on or off, how many copies it
  keeps, and Clear history (§15);
- the picker straight on its Characters tab with Super+;;
- the picker's Fill tab on Super+Shift+V: your snippets
  (`~/.config/tide/snippets.json`) and Bitwarden's logins through rbw
  (`brew install rbw`, then `rbw config set email` and `rbw login`), one
  row per field, typed where you were (§9.1);
- tileco's dashboard on Super+Shift+Space;
- a settings window, from the launcher or the dashboard, with tide's
  Clocks, Start at login and Clipboard settings, sharing tide's
  `~/.config/tide/clocks*.json`, `startup*.json` and `clipboard*.json`, and
  the muted apps and sites, and a Floating section for the rules that
  float an app's windows by bundle ID and title pattern, with the floating
  windows no rule covers yet; each section has its own launcher row (§15).
  Super+Shift+I opens Floating for the focused window, and floating a
  window with Super+Shift+F asks once whether to always float its app.
  The window has a page for each of tide's settings pages, in tide's
  order, under its sidebar's groups, Hardware, Windows and General: where the settings are macOS's or a helper's, its buttons open
  the System Settings pane, LinearMouse or Karabiner (§1, §15). Its
  Keyboard section turns conf's Karabiner rules, such as Ctrl+Tab's next
  tab, on and off itself, keeps them up to date with conf, and turns a new
  one on once. Its Mouse section has tide's Scroll speed and Natural
  scrolling, which tilemo sets in LinearMouse's config as it starts, after
  a device is plugged in or a wake, and when tide's settings change. Its
  last section, the Setup checklist, shows each permission's state and
  links each to its list in Privacy & Security, and lists the Desktop &
  Dock, Lock Screen and Notifications settings to change, to tick off
  (§10, §15);
- a notification, and a line in the doctor, when LinearMouse isn't
  installed or isn't running, since without it a mouse wheel notch
  scrolls a line or so (§10).

With [mikelward/scripts](https://github.com/mikelward/scripts), a plain
`setup` (or `setup-macos`) does all of this: it installs Hammerspoon and
tilemo, pulling an existing checkout first so each run keeps it current,
writes the `init.lua` below if there isn't one, frees the keys tilemo needs
(SPEC.md §7.3), and stops the menu bar hiding, so tilemo's bar covers it. `--wm amethyst` sets up Amethyst
instead. Grant Hammerspoon Accessibility,
and add conf's `tilemo:` Karabiner rule for a Super key that leaves Option
alone (§7.1). By hand:

1. Install [Hammerspoon](https://www.hammerspoon.org) and grant it
   Accessibility.
2. `make install`, then add to `~/.hammerspoon/init.lua`:

   ```lua
   tilemo = require("tilemo")
   tilemo.start({})
   ```

3. Stop the menu bar hiding: System Settings › Control Center ›
   "Automatically hide and show the menu bar": Never. tilemo's bar covers
   it, so it no longer slides in when the pointer reaches the top; the
   Apple logo's **Show Menu Bar** brings it back until Esc, Return, or a
   click below it.
4. Reload Hammerspoon's config.

To update, `git pull` and `make install` again (or run `setup`): tilemo
reloads itself a second after the new copy lands in
`~/.hammerspoon/tilemo`, so there's no reload to do by hand.

`tilemo.start({ bar = false })` leaves the bar out and shows tide's logo and
the workspaces in the menu bar instead.

The Switcher row under Keyboard in tide's settings swaps the `hs.chooser`
switcher for tileco's dashboard page, still being tried, at once (SPEC.md
§9.2). Until it's chosen there, `tilemo.start({ launcher = "dashboard" })`
does; the default is `launcher = "chooser"`.

On screen it's tide: notifications, window titles, the switcher's own
commands and the settings page say tide and show tide's wave logo. The code
keeps the name tilemo, so `require("tilemo")`, `start()`'s options and what
it has saved are unchanged. `make icons` renders the logo's PNGs from tide's
SVG with Playwright's Chromium.

`workspaces` names the standing workspaces, which are always on the bar and
never removed. It defaults to `{ "in", "re", "oc", "me" }`. The first is the
home workspace, made at start, where Super+Home goes; each of the rest is
made the first time you go to it or send a window there.

`home_apps` names the apps whose windows always open on the home workspace,
by app name. It defaults to mail, chat, calendar and music, as both the Mac's
apps and Google's web apps. A list you set also starts at login, once a
login, in the background, skipping any app that's running:

```lua
tilemo.start({ home_apps = { "Mail", "Messages", "Calendar", "Music" } })
```

`workspace_settings` is each workspace's own, as tide's `workspaceSettings`:
whether a new window there asks for a name (`askForName`), and the apps,
by app name, whose windows stay open there (`pinnedApps`). Unset, home asks
and nothing is pinned; set, a workspace it doesn't list, or a field it
leaves out, is off:

```lua
tilemo.start({ workspace_settings = { ["in"] = { askForName = true, pinnedApps = { "Gmail", "Google Chat" } } } })
```

tide's `standing`, `inApps` and `workspaceSettings`, in
`~/.config/tide/workspaces.json` and `workspaces.local.json`, take the place
of `workspaces`, `home_apps` and `workspace_settings` where a file sets them,
and the settings window's Workspaces section edits them.
`inApps` can name Mac apps alongside tide's entries: names match ignoring
case, with hyphens as spaces, and at login only the ones that are Mac apps
start.

Any other window opening on a workspace whose `askForName` is on, "in" by
default, asks for a workspace name, and so does a launch from there: Enter
makes or uses the workspace and moves there, the one it's on included, and
Esc closes the window or cancels the launch. Home's apps never ask. Any
window can be sent to "in". A pinned app's window stays open on its
workspace: Super+Backspace and the prompt's Esc leave it open, and while it
has focus Cmd+W, Cmd+Shift+W and Cmd+Q never reach it, with a notification
saying it's pinned there. Its close button and its menus still close it,
since tilemo can't see those. The default name comes from
the window's title: its first word, or a match of tide's `namePatterns` in
`~/.config/tide/workspaces.json`, which are JavaScript regular expressions.
Apps tilemo starts get the workspace's name, letters and digits only (in
any script, NFC-normalized), as `TIDE_WORKSPACE`. Scripts read the current one with
`cat ~/Library/Caches/tilemo/workspace`, a file only you can read, which
tilemo rewrites whenever the workspace changes. tilemo doesn't load
`hs.ipc`, since its port runs any Lua a local process sends it.

`start()` takes float rules, checked when it starts:

```lua
tilemo.start({ rules = { { app = "com.apple.finder", title = "^Info$", action = "float" } } })
```

Each title is a Lua pattern, found anywhere in the title. They come before
the rules the settings window's Floating section keeps in
`~/.config/tide/floating-macos.local.json`, which only float (SPEC.md §15).

tilemo was called timo. An install from then keeps working after
`make install`: `require("timo")` still loads tilemo, with a note in the
console to change it to `require("tilemo")`; a Karabiner rule described
`timo:` still counts; and the workspaces and launcher history timo saved are
read the first time tilemo finds none of its own. The old modules in
`~/.hammerspoon/timo/` are no longer used, and can go once `init.lua` says
`require("tilemo")`.

Super is the PC keyboard's Win key. With conf's Karabiner rule, it arrives
as Ctrl+Option+Command, so Option keeps its own meanings. Without it, tilemo
falls back to Option, and says so once (SPEC.md §7.1).

## Testing

`make test lint` runs everything in plain Lua 5.4, against a fake of macOS
(`tests/fake.lua`). The dashboard and bar pages' tests also need Node, and
skip with a note without it.

CI also runs `ci/hs-smoke.sh` on a macOS runner. It installs Hammerspoon from
Homebrew, checks that every `hs.*` name tilemo uses exists in it, then starts
tilemo, checks its bar is up along the top, opens and closes the dashboard,
and opens three TextEdit windows to check tilemo tiles them below the bar,
where its layout says. That's one layout on one
display; the checklists in SPEC.md §5.1 and §5.2 are what to try on a real
Mac.
