# What a Mac won't let tide fix

These are tide for Linux's behaviors that tide can't match. macOS has no public way
to do them, and tide uses no private calls and doesn't need SIP lowered
(SPEC.md §1). SPEC.md §13 has the workarounds, where there are any.

## Window frames

- **Rounded corners and title bars.** No public API removes or squares
  another app's frame, and macOS 26 rounds it at 16 pt. Content set right
  against the edge gets cut. The only fix is padding, app by app, as conf's
  kitty config does.
- **Exact tiles for every app.** An app can refuse a size, or round it,
  such as a terminal snapping to its character grid or a window with a
  minimum size bigger than its tile.
- **A new window's first frame.** It shows at its own size before tide
  hears of it and moves it.
- **A retile isn't atomic.** Each move is a round trip to its app, so one
  slow or hung app stalls the rest.

## Workspaces

- **Real workspaces.** Spaces, macOS's own, have no public API, so tide
  parks hidden windows off screen.
  - A 1 pt sliver of each parked window shows in a corner.
  - Cmd+Tab, the Dock, screenshot pickers and other apps' window lists
    still see every workspace's windows.
- **Native full screen** is a Space of its own, outside tide's
  workspaces.
- **macOS moves windows itself** when a display goes away and on wake,
  and tide can only follow up afterwards.

## Focus and attention

- **Nothing ever steals focus.** An app can bring itself to the front, and
  tide can only hand focus back afterwards.
- **Focus without raising.** Focusing a window brings it to the front.
- **Floats always on top.** There's no public way to set another app's
  window level.
- **Every window's attention request.** There's no signal for "this window
  wants attention", and other apps' notifications can't be read, so a
  banner a Focus hides marks nothing.

## The bar and drawing

- **One bar.** App menus, the Apple menu and other apps' status items stay
  in macOS's menu bar and can't be drawn in tide's.
- **Dimming exactly the inactive windows,** or any blur or opacity per
  window: tide can't draw inside another app's window, only over them
  all.
- **Picture-in-picture's place** is its app's, which moves it back.

## The system's own screens and settings

- **Lock and login screens.** They're macOS's; showing the hostname there
  is all that changes.
- **tide for Linux's exact input settings.** Trackpad, key repeat and left-handed
  settings take effect only at the next login, in macOS's own steps.
- **Natural scrolling for the trackpad alone** needs LinearMouse; macOS
  has one switch for both.
- **A share picker of tide's own.** There's nothing like Linux's portals,
  so sharing goes through macOS's picker or the app's.

## Permissions and updates

- **Accessibility, Karabiner's driver and Screen Recording** each need a
  person to grant them, and a managed Mac's IT can block them.
- **The Mac App Store.** Its sandbox forbids controlling other apps.
- **Keys during Secure Input.** While a password field or a terminal's
  secure keyboard entry is active, event taps don't see typed keys.
- **Undocumented behavior can change** with each macOS release:
  parking's sliver, the bar's level over the notch, and gestures if tide
  reads them.
