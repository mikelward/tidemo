// Runs the settings page's bundled script (tests/settings_test.lua writes it
// to the file named on the command line) against a small fake DOM, and
// checks its changes reach tilemo as clocks.local.json's new text.

const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

class Element {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.textContent = "";
    this.value = "";
    this.disabled = false;
    this.attrs = {};
    this.listeners = {};
  }
  append(...xs) {
    for (const x of xs) this.children.push(x);
  }
  replaceChildren() {
    this.children = [];
  }
  setAttribute(k, v) {
    this.attrs[k] = v;
  }
  addEventListener(type, fn) {
    this.listeners[type] = fn;
  }
  getAttribute(k) {
    return this.attrs[k] ?? null;
  }
  // The keyboard's on it, as the document's activeElement says. A browser
  // won't focus a disabled control.
  focus() {
    if (!this.disabled) sandbox.document.activeElement = this;
  }
}

// The first element under any of the page's ids whose `name` attribute is
// `value`, as querySelector('[name="value"]') finds it.
function find(name, value) {
  const walk = (e) => {
    if (!e || typeof e !== "object") return null;
    if (e.attrs?.[name] === value) return e;
    for (const c of e.children ?? []) {
      const got = walk(c);
      if (got) return got;
    }
    return null;
  };
  for (const root of Object.values(ids)) {
    const got = walk(root);
    if (got) return got;
  }
  return null;
}

const ids = {};
const sent = [];
// The document's own listeners, such as keydown for Up and Down.
const docListeners = {};
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= new Element(id)),
    addEventListener: (type, fn) => {
      docListeners[type] = fn;
    },
    activeElement: null,
    querySelector: (sel) => {
      const m = sel.match(/^\[([\w-]+)="([^"]*)"\]$/);
      return m ? find(m[1], m[2]) : null;
    },
  },
  Intl,
  Date,
  Math,
  JSON,
  Number,
  String,
  Object,
  Array,
  Error,
  Map,
  Set,
};
sandbox.window = sandbox;
// The window's own listeners, such as focus for the Setup checklist.
const windowListeners = {};
sandbox.addEventListener = (type, fn) => {
  windowListeners[type] = fn;
};
sandbox.webkit = { messageHandlers: { tilemo: { postMessage: (m) => sent.push(JSON.parse(JSON.stringify(m))) } } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

const rows = () => ids["clock-list"].children.filter((li) => li.className !== "local");
const zones = () => rows().map((li) => li.children[0].textContent);
const press = (input, key) => input.listeners.keydown({ key, target: input });
const lastWrite = () => JSON.parse(sent[sent.length - 1].write);

// No files: tide's defaults, and local last.
sandbox.tilemo.update({ clockFiles: [] });
assert.deepStrictEqual(zones(), ["Australia/Sydney", "America/Los_Angeles", "America/New_York", "Europe/London"]);
assert.match(ids.source.textContent, /tide's defaults/);
assert.match(ids["clock-list"].children.at(-1).textContent, /\(local\)$/);

// Adding a zone copies the defaults into clocks.local.json, with the new
// one last, labeled with its city.
const add = ids["add-zone"];
add.value = "Asia/Tokyo";
press(add, "Enter");
assert.deepStrictEqual(lastWrite().map((c) => c.zone).at(-1), "Asia/Tokyo");
assert.deepStrictEqual(lastWrite().at(-1), { zone: "Asia/Tokyo", label: "Tokyo" });
assert.strictEqual(add.value, "", "the box empties once it's added");

// A zone Intl doesn't know, or one listed already, is refused, and nothing
// is written.
const before = sent.length;
add.value = "Mars/Base";
press(add, "Enter");
assert.match(ids.error.textContent, /unknown time zone Mars\/Base/);
add.value = "Europe/London";
press(add, "Enter");
assert.match(ids.error.textContent, /listed already/);
assert.strictEqual(sent.length, before);

// tilemo hands the saved file back; the page shows it.
const saved = JSON.stringify({ clocks: [{ zone: "Asia/Tokyo", label: "TYO" }, { zone: "Europe/London", label: "LON" }], hour24: false });
sandbox.tilemo.update({ clockFiles: { local: saved } });
assert.deepStrictEqual(zones(), ["Asia/Tokyo", "Europe/London"]);
assert.match(ids.source.textContent, /clocks\.local\.json/);
assert.strictEqual(ids.error.textContent, "");

// Relabel, move and remove, each keeping the file's switches. Each change
// redraws the rows, so each is found afresh.
const row = (zone) => rows().find((li) => li.children[0].textContent === zone);
assert.strictEqual(row("Asia/Tokyo").children[2].disabled, true, "the first can't move left");
row("Asia/Tokyo").children[1].value = "abbr";
press(row("Asia/Tokyo").children[1], "Enter");
assert.deepStrictEqual(lastWrite(), { clocks: [{ zone: "Asia/Tokyo", label: "abbr" }, { zone: "Europe/London", label: "LON" }], hour24: false });
row("Europe/London").children[2].listeners.click();
assert.deepStrictEqual(lastWrite().clocks.map((c) => c.zone), ["Europe/London", "Asia/Tokyo"]);
row("Asia/Tokyo").children[4].listeners.click();
assert.deepStrictEqual(lastWrite(), { clocks: [{ zone: "Europe/London", label: "LON" }], hour24: false });

// Two changes before tilemo hands the saved file back both stick: the page
// shows the first at once, and the second builds on it.
const three = [
  { zone: "Asia/Tokyo", label: "TYO" },
  { zone: "Europe/London", label: "LON" },
  { zone: "America/Denver", label: "DEN" },
];
sandbox.tilemo.update({ clockFiles: { local: JSON.stringify(three) } });
row("Asia/Tokyo").children[4].listeners.click();
row("Europe/London").children[4].listeners.click();
assert.deepStrictEqual(lastWrite(), [{ zone: "America/Denver", label: "DEN" }]);
assert.deepStrictEqual(zones(), ["America/Denver"]);

// A shared clocks.json, with no local file, is the list to start from.
sandbox.tilemo.update({ clockFiles: { shared: '[{"zone": "America/Denver", "label": "DEN"}]' } });
assert.deepStrictEqual(zones(), ["America/Denver"]);
assert.match(ids.source.textContent, /shared with tide/);

// A file that doesn't parse can't be changed here, and the page says so.
sandbox.tilemo.update({ clockFiles: { local: "[{" } });
assert.deepStrictEqual(zones(), []);
assert.match(ids.error.textContent, /clocks\.local\.json: line 1/);
assert.strictEqual(add.disabled, true);

// The muted apps and sites, each with an Unmute button that tells tilemo.
const muted = () => ids["muted-list"].children;
sandbox.tilemo.update({ clockFiles: [], muted: [] });
assert.strictEqual(muted().length, 1);
assert.strictEqual(muted()[0].textContent, "Nothing is muted.");
sandbox.tilemo.update({ clockFiles: [], muted: ["com.example.chat", "site:chat.example.com"] });
assert.deepStrictEqual(muted().map((li) => li.children[0].textContent), ["com.example.chat", "chat.example.com"]);
for (const li of muted()) assert.strictEqual(li.children.length, 2, "an entry and Unmute");
sent.length = 0;
muted()[1].children[1].listeners.click();
assert.deepStrictEqual(sent, [{ unmute: "site:chat.example.com" }]);
assert.strictEqual(muted()[1].children[1].attrs["aria-label"], "Unmute chat.example.com");

// Start at login: tide's startup.json and startup.local.json, through
// tide's own functions. No files: nothing runs, and the first command
// added saves startup.local.json.
const commands = () => ids["startup-list"].children.map((li) => li.children[0]?.textContent ?? li.textContent);
const lastStartup = () => JSON.parse(sent.filter((m) => m.writeStartup).at(-1).writeStartup);
sandbox.tilemo.update({ clockFiles: [], startupFiles: [], muted: [] });
assert.deepStrictEqual(commands(), ["Nothing runs at login."]);
assert.match(ids["startup-source"].textContent, /startup\.local\.json/);
const addCommand = ids["add-command"];
addCommand.value = "  google-calendar  ";
press(addCommand, "Enter");
assert.deepStrictEqual(lastStartup(), { commands: ["google-calendar"] });
assert.strictEqual(addCommand.value, "", "the box empties once it's added");
assert.deepStrictEqual(commands(), ["google-calendar"], "shown at once");

// A command with shell syntax, or one listed already, is refused, says
// why, and writes nothing.
sent.length = 0;
addCommand.value = "open -a $HOME/x";
press(addCommand, "Enter");
assert.match(ids["startup-error"].textContent, /no shell/);
addCommand.value = "google-calendar";
press(addCommand, "Enter");
assert.match(ids["startup-error"].textContent, /listed already/);
assert.deepStrictEqual(sent, []);

// A shared startup.json is the list to start from; the first change copies
// it into startup.local.json, keeping that file's other keys.
sandbox.tilemo.update({
  clockFiles: [],
  startupFiles: { shared: '{"commands": ["google-calendar", "google-chat"]}', local: '{"note": 1}' },
});
assert.deepStrictEqual(commands(), ["google-calendar", "google-chat"]);
assert.match(ids["startup-source"].textContent, /shared with tide/);
// settings_test.lua checks the stylesheet gives a row this many columns.
for (const li of ids["startup-list"].children) assert.strictEqual(li.children.length, 4, "a command, up, down and remove");
const cmdRow = (c) => ids["startup-list"].children.find((li) => li.children[0].textContent === c);
// Up, down and remove each drawn as tide's icon for it.
assert.deepStrictEqual(cmdRow("google-calendar").children.slice(1).map((b) => b.attrs["data-icon"]), ["up", "down", "delete"]);
assert.strictEqual(cmdRow("google-calendar").children[1].disabled, true, "the first can't move up");
cmdRow("google-chat").children[1].listeners.click();
assert.deepStrictEqual(lastStartup(), { note: 1, commands: ["google-chat", "google-calendar"] });
cmdRow("google-calendar").children[3].listeners.click();
assert.deepStrictEqual(lastStartup(), { note: 1, commands: ["google-chat"] });

// A startup file that doesn't parse can't be changed here.
sandbox.tilemo.update({ clockFiles: [], startupFiles: { local: "{" } });
assert.match(ids["startup-error"].textContent, /startup\.local\.json/);
assert.strictEqual(addCommand.disabled, true);

// Clipboard: tide's clipboard.json and clipboard.local.json, through
// tide's own functions. No files: tide's defaults.
const clip = (id) => sandbox.document.getElementById(id);
const lastClipboard = () => JSON.parse(sent.filter((m) => m.writeClipboard).at(-1).writeClipboard);
sandbox.tilemo.update({ clockFiles: [], startupFiles: [], clipboardFiles: [], clipboardCount: 3 });
assert.strictEqual(clip("clipboard-summary").textContent, "Keeps the newest 200 copies. 3 copies kept now.");
assert.strictEqual(clip("clipboard-history").textContent, "History on");
assert.strictEqual(clip("clipboard-max").textContent, "200");
assert.strictEqual(clip("clipboard-clear").disabled, false);
clip("clipboard-more").listeners.click();
assert.strictEqual(JSON.stringify(lastClipboard()), JSON.stringify({ maxItems: 500 }), "+ steps to the next mark");
assert.strictEqual(clip("clipboard-max").textContent, "500", "shown at once");
clip("clipboard-history").listeners.click();
assert.strictEqual(JSON.stringify(lastClipboard()), JSON.stringify({ maxItems: 500, history: false }), "builds on the change before");
assert.match(clip("clipboard-summary").textContent, /^Off: new copies aren't kept/);
// A shared file's keys apply, and the local file overrides them one by one.
sandbox.tilemo.update({ clockFiles: [], clipboardFiles: { shared: '{"maxItems": 25, "history": false}', local: '{"history": true}' }, clipboardCount: 0 });
assert.strictEqual(clip("clipboard-max").textContent, "25");
assert.strictEqual(clip("clipboard-history").textContent, "History on");
assert.strictEqual(clip("clipboard-fewer").disabled, true, "25 is the lowest mark");
assert.strictEqual(clip("clipboard-clear").disabled, true, "nothing to clear");
clip("clipboard-fewer").listeners.click();
// A file that's wrong is said, and nothing can change until it's fixed.
sandbox.tilemo.update({ clockFiles: [], clipboardFiles: { local: '{"maxItems": 0}' }, clipboardCount: 1 });
assert.match(clip("clipboard-error").textContent, /clipboard\.local\.json: maxItems must be a whole number/);
assert.strictEqual(clip("clipboard-more").disabled, true);
assert.strictEqual(clip("clipboard-history").disabled, true);
assert.strictEqual(clip("clipboard-summary").textContent, "Keeps the newest 200 copies. 1 copy kept now.", "no settings from tilemo: the defaults");
// tilemo keeps the last good settings in effect, and the page shows those,
// opened after the error or not.
sandbox.tilemo.update({ clockFiles: [], clipboardFiles: { local: "{" }, clipboardCount: 1, clipboardSettings: { history: false, maxItems: 25 } });
assert.match(clip("clipboard-error").textContent, /clipboard\.local\.json/);
assert.strictEqual(clip("clipboard-history").textContent, "History off");
assert.strictEqual(clip("clipboard-max").textContent, "25");
assert.match(clip("clipboard-summary").textContent, /^Off: new copies aren't kept/);
sent.length = 0;
clip("clipboard-clear").listeners.click();
assert.strictEqual(JSON.stringify(sent), JSON.stringify([{ clearClipboard: true }]));

// A copy made while the window is open: tilemo sends the count alone, and
// only the Clipboard section redraws, so a label being edited stays.
sandbox.tilemo.update({ clockFiles: { local: '[{"zone": "Asia/Tokyo", "label": "TYO"}]' }, clipboardFiles: [], clipboardCount: 0 });
assert.strictEqual(clip("clipboard-clear").disabled, true);
const editing = rows()[0];
editing.children[1].value = "Tok";
sandbox.tilemo.count(2);
assert.strictEqual(clip("clipboard-clear").disabled, false, "Clear is offered once there's something to clear");
assert.match(clip("clipboard-summary").textContent, /2 copies kept now/);
assert.strictEqual(rows()[0], editing, "the clocks aren't redrawn");
assert.strictEqual(rows()[0].children[1].value, "Tok");
sandbox.tilemo.count(0);
assert.strictEqual(clip("clipboard-clear").disabled, true);

// Sound, as tide's page: the output's mute, slider and level, then each
// output, the one in use lit; then the input's; and what each control asks.
{
  const out = () => ids["sound-output-volume"].children;
  const outputs = () => ids["sound-outputs"].children.map((li) => li.children[0]);
  const state = {
    output: {
      name: "MacBook Speakers", volume: 40, muted: false, can_mute: true, live: true,
      devices: [{ uid: "a", name: "MacBook Speakers", current: true }, { uid: "b", name: "Studio Display", current: false }],
    },
    input: { name: "MacBook Microphone", volume: 70, muted: true, can_mute: true, live: true, devices: [] },
  };
  sandbox.tilemo.update({ clockFiles: [], sound: state });
  assert.deepStrictEqual(out().map((c) => c.tag), ["button", "input", "span"]);
  assert.strictEqual(out()[0].attrs["data-icon"], "speaker-on");
  assert.strictEqual(out()[1].value, "40");
  assert.strictEqual(out()[2].textContent, "40%");
  assert.deepStrictEqual(outputs().map((b) => [b.textContent, b.attrs["aria-current"], b.attrs["data-icon"]]),
    [["MacBook Speakers", "true", "output"], ["Studio Display", "false", "output"]]);
  // The input's muted, and with no inputs listed, its heading goes.
  assert.strictEqual(ids["sound-input-volume"].children[0].attrs["data-icon"], "mic-off");
  assert.strictEqual(ids["sound-input-volume"].children[2].textContent, "0%");
  assert.strictEqual(ids["sound-input-heading"].hidden, true);
  sent.length = 0;
  outputs()[1].listeners.click();
  outputs()[0].listeners.click();
  out()[0].listeners.click();
  assert.deepStrictEqual(sent, [{ soundOutput: "b" }, { soundMute: true }], "the device in use isn't asked for again");
  // The slider sets it as it moves, and once more as it's let go; an
  // update meanwhile doesn't move it under you.
  sent.length = 0;
  const slider = out()[1];
  slider.value = "55";
  slider.listeners.input();
  assert.strictEqual(out()[2].textContent, "55%");
  sandbox.tilemo.sound({ ...state, output: { ...state.output, volume: 41 } });
  assert.strictEqual(out()[1], slider, "not redrawn while it's held");
  slider.listeners.change();
  assert.deepStrictEqual(sent, [{ soundVolume: 55 }, { soundVolume: 55 }]);
  sandbox.tilemo.sound({ ...state, output: { ...state.output, volume: 55 } });
  assert.strictEqual(out()[1].value, "55");
  // A monitor over DDC is set only once it's let go.
  sent.length = 0;
  sandbox.tilemo.sound({ ...state, output: { ...state.output, live: false } });
  out()[1].value = "20";
  out()[1].listeners.input();
  out()[1].listeners.change();
  assert.deepStrictEqual(sent, [{ soundVolume: 20 }]);
  // The same again draws nothing; a change draws again, keeping the
  // keyboard on the slider it was on, so arrow keys go on stepping it.
  const now = { ...state, output: { ...state.output, volume: 20, live: false } };
  sandbox.tilemo.sound(now);
  const before = out()[1];
  sandbox.tilemo.sound(JSON.parse(JSON.stringify(now)));
  assert.strictEqual(out()[1], before, "nothing new, nothing drawn");
  before.focus();
  sandbox.tilemo.sound({ ...now, output: { ...now.output, volume: 25 } });
  assert.notStrictEqual(out()[1], before);
  assert.strictEqual(sandbox.document.activeElement, out()[1], "the keyboard stays on the slider");
  outputs()[1].focus();
  sandbox.tilemo.sound({ ...now, output: { ...now.output, volume: 30 } });
  assert.strictEqual(sandbox.document.activeElement, outputs()[1], "and on a device");
  sandbox.document.activeElement = null;
  // A change while the slider's held is drawn once it's let go, even when
  // tilemo's answer is that same change: muted by a key mid-drag.
  out()[1].listeners.input();
  sandbox.tilemo.sound({ ...now, output: { ...now.output, volume: 30, muted: true } });
  assert.strictEqual(out()[0].textContent, "Mute", "held: not redrawn yet");
  out()[1].listeners.change();
  sandbox.tilemo.sound({ ...now, output: { ...now.output, volume: 30, muted: true } });
  assert.strictEqual(out()[0].textContent, "Unmute", "let go: the mute shows");
  // A level macOS refuses goes back to what it says, though that's what
  // was drawn before.
  const settled = { ...now, output: { ...now.output, volume: 40, muted: false, live: true } };
  sandbox.tilemo.sound(settled);
  out()[1].value = "41";
  out()[1].listeners.input();
  out()[1].listeners.change();
  sandbox.tilemo.sound(JSON.parse(JSON.stringify(settled)));
  assert.strictEqual(out()[1].value, "40", "back to macOS's level");
  assert.strictEqual(out()[2].textContent, "40%");
  // No volume control: no slider.
  sandbox.tilemo.sound({ output: { name: "HDMI", can_mute: false, devices: [] }, input: { devices: [] } });
  assert.strictEqual(ids["sound-output-volume"].hidden, true);
}

// Displays, as tide's page: each display's name, then its resolution and
// where it goes, ‹ and ›, Make main, and its brightness.
{
  const box = () => ids["display-list"].children;
  const row = (label) => box().find((r) => r.children?.[0]?.textContent === label);
  const state = {
    places: [
      { place: "right", label: "To the right" }, { place: "left", label: "To the left" },
      { place: "above", label: "Above" }, { place: "below", label: "Below" },
    ],
    displays: [
      { uuid: "mac", name: "Built-in", main: true, sizes: [{ w: 1147, h: 745 }, { w: 1512, h: 982, current: true }], brightness: 60 },
      { uuid: "ext", name: "LG", main: false, place: "right", sizes: [{ w: 2560, h: 1440, current: true }] },
    ],
  };
  sandbox.tilemo.update({ clockFiles: [], displays: state });
  assert.deepStrictEqual(box().filter((r) => r.tag === "h2").map((h) => h.textContent), ["Built-in · main", "LG"]);
  const sizeRows = box().filter((r) => r.children?.[0]?.textContent === "Resolution");
  assert.deepStrictEqual(sizeRows.map((r) => r.children[2].textContent), ["1512 × 982", "2560 × 1440"]);
  assert.deepStrictEqual(sizeRows.map((r) => [r.children[1].disabled, r.children[3].disabled]), [[false, true], [true, true]]);
  sent.length = 0;
  sizeRows[0].children[1].listeners.click();
  assert.deepStrictEqual(sent.at(-1), { displaySize: { uuid: "mac", w: 1147, h: 745 } });
  // Only the other display has a place, stepping round the four.
  assert.strictEqual(row("Place").children[2].textContent, "To the right");
  row("Place").children[3].listeners.click();
  assert.deepStrictEqual(sent.at(-1), { displayPlace: { uuid: "ext", place: "left" } });
  row("Place").children[1].listeners.click();
  assert.deepStrictEqual(sent.at(-1), { displayPlace: { uuid: "ext", place: "below" } });
  row("Main display").children[1].listeners.click();
  assert.deepStrictEqual(sent.at(-1), { displayMain: "ext" });
  // Brightness, where macOS can set it: the built-in display's alone.
  const bright = box().filter((r) => r.className === "row volume");
  assert.strictEqual(bright.length, 1);
  bright[0].children[1].value = "35";
  bright[0].children[1].listeners.input();
  assert.deepStrictEqual(sent.at(-1), { displayBrightness: { uuid: "mac", level: 35 } });
  sandbox.tilemo.displays({ ...state, displays: [] });
  assert.ok(box().length > 0, "not redrawn while the slider's held");
  bright[0].children[1].listeners.change();
  sandbox.tilemo.displays({ ...state, displays: [{ ...state.displays[1], place: undefined }] });
  assert.strictEqual(row("Place").children[2].textContent, "Elsewhere", "a mirror of the main display");
  // The same again draws nothing; a change draws again, keeping the
  // keyboard on the control it was on, so › and arrow keys go on working.
  sandbox.tilemo.displays(state);
  const next = row("Place").children[3];
  sandbox.tilemo.displays(JSON.parse(JSON.stringify(state)));
  assert.strictEqual(row("Place").children[3], next, "nothing new, nothing drawn");
  next.focus();
  sandbox.tilemo.displays({ ...state, displays: [state.displays[0], { ...state.displays[1], place: "left" }] });
  assert.notStrictEqual(row("Place").children[3], next);
  assert.strictEqual(sandbox.document.activeElement, row("Place").children[3], "the keyboard stays on ›");
  const brightness = () => box().find((r) => r.className === "row volume").children[1];
  brightness().focus();
  sandbox.tilemo.displays({ ...state, displays: [{ ...state.displays[0], brightness: 65 }, state.displays[1]] });
  assert.strictEqual(brightness().value, "65");
  assert.strictEqual(sandbox.document.activeElement, brightness(), "and on the brightness slider");
  sandbox.document.activeElement = null;
  // A level macOS refuses goes back to what it says.
  const lit = { ...state, displays: [{ ...state.displays[0], brightness: 65 }, state.displays[1]] };
  brightness().value = "70";
  brightness().listeners.input();
  brightness().listeners.change();
  sandbox.tilemo.displays(JSON.parse(JSON.stringify(lit)));
  assert.strictEqual(brightness().value, "65", "back to macOS's level");
}

// Bluetooth, as tide's popover: On or Off, then the paired devices while
// it's on, each lit while connected, and what a click asks.
{
  const power = () => ids["bluetooth-power"].children;
  const devices = () => ids["bluetooth-devices"].children.map((li) => li.children[0]);
  const state = {
    on: true, switching: false,
    devices: [
      { address: "aa-bb-cc-dd-ee-ff", name: "Buds", connected: true, busy: false, status: "Connected" },
      { address: "11-22-33-44-55-66", name: "Mouse", connected: false, busy: false, status: "" },
    ],
  };
  sandbox.tilemo.update({ clockFiles: [], bluetooth: state });
  assert.strictEqual(ids["bluetooth-power"].hidden, false);
  assert.deepStrictEqual(power().map((c) => c.textContent), ["Bluetooth", "On"]);
  assert.strictEqual(power()[1].attrs["aria-pressed"], "true");
  assert.deepStrictEqual(devices().map((b) => [b.textContent, b.attrs["aria-current"], b.attrs["data-icon"]]),
    [["Buds · Connected", "true", "bluetooth"], ["Mouse", "false", "bluetooth"]]);
  assert.strictEqual(ids["bluetooth-devices-heading"].hidden, false);
  sent.length = 0;
  devices()[0].listeners.click();
  devices()[1].listeners.click();
  power()[1].listeners.click();
  assert.deepStrictEqual(sent, [
    { bluetoothDisconnect: "aa-bb-cc-dd-ee-ff" }, { bluetoothConnect: "11-22-33-44-55-66" }, { bluetoothPower: false },
  ]);
  // One connecting waits, and keeps the keyboard across the redraw.
  devices()[1].focus();
  sandbox.tilemo.bluetooth({ ...state, devices: [state.devices[0], { ...state.devices[1], busy: true, status: "Connecting…" }] });
  assert.strictEqual(devices()[1].textContent, "Mouse · Connecting…");
  assert.strictEqual(devices()[1].attrs["aria-disabled"], "true", "waiting, but still focusable");
  assert.strictEqual(sandbox.document.activeElement, devices()[1], "the keyboard stays on the device");
  const before = sent.length;
  devices()[1].listeners.click();
  assert.strictEqual(sent.length, before, "a busy device asks nothing");
  sandbox.document.activeElement = null;
  // Off: no devices; unread: no switch, and why.
  sandbox.tilemo.bluetooth({ on: false, switching: false, devices: [] });
  assert.strictEqual(power()[1].textContent, "Off");
  assert.strictEqual(devices().length, 0);
  assert.strictEqual(ids["bluetooth-devices-heading"].hidden, true);
  // A change that failed says why.
  sandbox.tilemo.bluetooth({ ...state, problem: "Couldn't connect Mouse: Failed to connect" });
  assert.strictEqual(ids["bluetooth-error"].textContent, "Couldn't connect Mouse: Failed to connect");
  sandbox.tilemo.bluetooth({ switching: false, devices: [], problem: "blueutil isn't installed" });
  assert.strictEqual(ids["bluetooth-power"].hidden, true);
  assert.strictEqual(ids["bluetooth-error"].textContent, "blueutil isn't installed");
}

// Network and Power: Wi-Fi's switch and where it's joined, how the Mac's
// online, and the battery.
{
  const power = () => ids["wifi-power"].children;
  const state = {
    network: { wifi: { on: true, line: "Joined to Home" }, online: "Online over Wi-Fi" },
    power: { battery: "Battery 84%, 2:15 left" },
  };
  sandbox.tilemo.update({ clockFiles: [], netpower: state });
  assert.deepStrictEqual(power().map((c) => c.textContent), ["Wi-Fi", "On"]);
  assert.strictEqual(ids["network-status"].textContent, "Joined to Home. Online over Wi-Fi.");
  assert.strictEqual(ids["battery-status"].textContent, "Battery 84%, 2:15 left");
  sent.length = 0;
  power()[1].listeners.click();
  assert.deepStrictEqual(sent, [{ wifiPower: false }]);
  power()[1].focus();
  sandbox.tilemo.netpower({ network: { wifi: { on: false, line: "Off" }, online: "Online over a wire" }, power: {} });
  assert.strictEqual(power()[1].textContent, "Off");
  assert.strictEqual(sandbox.document.activeElement, power()[1], "the keyboard stays on the switch");
  sandbox.document.activeElement = null;
  assert.strictEqual(ids["network-status"].textContent, "Online over a wire.", "no line for Wi-Fi that's off");
  assert.strictEqual(ids["battery-status"].textContent, "This Mac has no battery");
  sandbox.tilemo.netpower({ network: { online: "Offline" }, power: {} });
  assert.strictEqual(ids["wifi-power"].hidden, true, "no Wi-Fi, no switch");
}

// Idle, as tide's page: tide's timeline Off with nothing set; On writes
// its timings, each stepped along tide's ladder, and Suspend on AC too.
{
  const lastIdle = () => JSON.parse(sent.filter((m) => m.writeIdle).at(-1).writeIdle);
  const timeline = () => ids["idle-timeline"].children;
  const steps = () => ids["idle-steps"].children;
  sandbox.tilemo.update({ clockFiles: [], idleFiles: {} });
  assert.deepStrictEqual(timeline().map((c) => c.textContent), ["tide's timeline", "Off"]);
  assert.strictEqual(steps().length, 0, "macOS's own has no steps");
  timeline()[1].listeners.click();
  assert.deepStrictEqual(lastIdle(), { dim: 150, lock: 300, displaysOff: 330, suspend: 1800, suspendOnAC: false });
  assert.deepStrictEqual(steps().map((li) => [li.children[0].textContent, li.children[2]?.textContent ?? li.children[1].textContent]), [
    ["Dim the screen", "2 min 30 s"], ["Lock", "5 min"], ["Turn off displays", "5 min 30 s"], ["Suspend, on battery", "30 min"],
    ["Suspend on AC too", "Off"],
  ]);
  steps()[1].children[3].listeners.click();
  assert.strictEqual(lastIdle().lock, 330);
  steps()[4].children[1].listeners.click();
  assert.strictEqual(lastIdle().suspendOnAC, true);
  timeline()[1].listeners.click();
  assert.deepStrictEqual(lastIdle(), {}, "Off empties this Mac's file");
  // What the shared file sets can't be turned off here.
  sandbox.tilemo.update({ clockFiles: [], idleFiles: { shared: '{"lock": 600}' } });
  assert.strictEqual(timeline()[1].textContent, "On");
  assert.strictEqual(timeline()[1].disabled, true);
  assert.strictEqual(steps()[1].children[2].textContent, "10 min");
  // A file that's wrong is said, and nothing changes until it's fixed.
  sandbox.tilemo.update({ clockFiles: [], idleFiles: { local: '{"lock": 0}' } });
  assert.match(ids["idle-error"].textContent, /lock must be a whole number/);
  sandbox.tilemo.update({ clockFiles: [], idleFiles: {} });
}

// Appearance's wallpapers, light and dark, in tide's appearance files: the
// one set shows, Enter sets a typed path, the choose button asks tilemo for
// macOS's file dialog, and its answer is set as a typed one.
{
  const lastAppearance = () => JSON.parse(sent.filter((m) => m.writeAppearance).at(-1).writeAppearance);
  const walls = () => ids.wallpapers.children;
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { shared: '{"darkWallpaper": "~/night.png"}' } });
  assert.deepStrictEqual(walls().map((li) => li.children[0].textContent), ["Light wallpaper", "Dark wallpaper"]);
  assert.deepStrictEqual(walls().map((li) => li.children[1].value), ["", "~/night.png"]);
  assert.strictEqual(walls()[0].children[1].placeholder, "macOS's own");
  sent.length = 0;
  walls()[0].children[1].value = " ~/Pictures/day.jpg ";
  walls()[0].children[1].listeners.keydown({ key: "Enter" });
  assert.deepStrictEqual(lastAppearance(), { lightWallpaper: "~/Pictures/day.jpg" }, "only this Mac's own, in appearance.local.json");
  assert.strictEqual(walls()[0].children[1].value, "~/Pictures/day.jpg", "shown at once");
  walls()[1].children[2].listeners.click();
  assert.deepStrictEqual(sent.at(-1), { pickWallpaper: "darkWallpaper" });
  assert.strictEqual(walls()[1].children[2].attrs["data-icon"], "folder");
  sandbox.tilemo.setWallpaper("darkWallpaper", "/Library/Desktop Pictures/Sky.heic");
  assert.deepStrictEqual(lastAppearance(), { lightWallpaper: "~/Pictures/day.jpg", darkWallpaper: "/Library/Desktop Pictures/Sky.heic" });
  // A path tide wouldn't take is refused, saying why, and nothing's saved.
  const before = sent.length;
  walls()[0].children[1].value = "day.jpg";
  walls()[0].children[1].listeners.keydown({ key: "Enter" });
  assert.strictEqual(sent.length, before);
  assert.match(ids["appearance-error"].textContent, /lightWallpaper must be a file's path/);
  // A color, which tide takes, is refused here: a Mac can't show one.
  walls()[0].children[1].value = "#1a1d2e";
  walls()[0].children[1].listeners.keydown({ key: "Enter" });
  assert.strictEqual(sent.length, before);
  assert.match(ids["appearance-error"].textContent, /A solid color is tide's only/);
  // A file that's wrong is said, and nothing can be changed until it's fixed.
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { local: "{" } });
  assert.match(ids["appearance-error"].textContent, /appearance\.local\.json/);
  assert.strictEqual(walls()[0].children[1].disabled, true);
  assert.strictEqual(walls()[0].children[2].disabled, true);
}

// Appearance's dim, as tide's page has it: tide's 7% until a file sets it,
// − and + a point at a time into appearance.local.json, keeping what else
// it says, and none at the bottom.
{
  const lastAppearance = () => JSON.parse(sent.filter((m) => m.writeAppearance).at(-1).writeAppearance);
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { local: '{"lightWallpaper": "~/day.jpg"}' } });
  assert.strictEqual(ids["dim-strength"].textContent, "7%");
  ids["dim-more"].listeners.click();
  assert.deepStrictEqual(lastAppearance(), { lightWallpaper: "~/day.jpg", dimStrength: 0.08 });
  assert.strictEqual(ids["dim-strength"].textContent, "8%", "shown at once");
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { shared: '{"dimStrength": 0.01}' } });
  assert.strictEqual(ids["dim-strength"].textContent, "1%", "the shared file's");
  assert.strictEqual(ids["dim-less"].disabled, false);
  ids["dim-less"].listeners.click();
  assert.deepStrictEqual(lastAppearance(), { dimStrength: 0 });
  assert.strictEqual(ids["dim-strength"].textContent, "0%");
  assert.strictEqual(ids["dim-less"].disabled, true, "none is the least");
  // A file that's wrong holds both until it's fixed.
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { local: "{" } });
  assert.strictEqual(ids["dim-more"].disabled, true);
}

// Appearance's light or dark, as tide's page: what shows now and until
// when, with its switch; the mode, macOS's own first, then tide's; By the
// clock's times; and the place Sunrise and sunset needs.
{
  const lastAppearance = () => JSON.parse(sent.filter((m) => m.writeAppearance).at(-1).writeAppearance);
  const mode = () => ids["theme-mode"].children;
  const times = () => ids["theme-times"].children;
  const place = () => ids["theme-place"].children;
  ids["appearance-error"].textContent = "";
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: {}, theme: { chosen: false, dark: true } });
  assert.deepStrictEqual(ids["theme-now"].children.map((c) => c.textContent), ["Dark", "Light now"]);
  assert.deepStrictEqual(mode().map((c) => c.textContent), ["Mode", "‹", "macOS's own", "›"]);
  assert.strictEqual(mode()[1].disabled, true, "nothing before macOS's own");
  assert.strictEqual(times().length + place().length, 0, "macOS's own has no times or place");
  sent.length = 0;
  ids["theme-now"].children[1].listeners.click();
  assert.deepStrictEqual(sent, [{ themeFlip: true }]);
  // › chooses tide's first, By the clock, with its times.
  mode()[3].listeners.click();
  assert.deepStrictEqual(lastAppearance(), { mode: "schedule" });
  assert.strictEqual(mode()[2].textContent, "By the clock");
  assert.deepStrictEqual(times().map((li) => [li.children[0].textContent, li.children[2].textContent]),
    [["Light from", "07:00"], ["Dark from", "19:00"]]);
  times()[0].children[1].listeners.click();
  assert.deepStrictEqual(lastAppearance(), { mode: "schedule", light: "06:45" });
  // A time steps past the other one, as the same time isn't a schedule.
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { local: '{"mode": "schedule", "light": "18:45", "dark": "19:00"}' } });
  times()[0].children[3].listeners.click();
  assert.strictEqual(lastAppearance().light, "19:15");
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { local: '{"mode": "schedule", "light": "06:45"}' } });
  // Sunrise and sunset is stepped past until there's a place.
  mode()[3].listeners.click();
  assert.strictEqual(lastAppearance().mode, "light");
  assert.deepStrictEqual(place().map((li) => li.children[0].textContent), ["Latitude", "Longitude"]);
  for (const [i, v] of [[0, "53.35"], [1, "-6.26"]]) {
    place()[i].children[1].value = v;
    place()[i].children[1].listeners.keydown({ key: "Enter" });
  }
  assert.deepStrictEqual(lastAppearance(), { mode: "light", light: "06:45", latitude: 53.35, longitude: -6.26 });
  mode()[1].listeners.click();
  assert.strictEqual(lastAppearance().mode, "sun");
  place()[0].children[1].value = "north";
  const before = sent.length;
  place()[0].children[1].listeners.keydown({ key: "Enter" });
  assert.strictEqual(sent.length, before);
  assert.match(ids["appearance-error"].textContent, /latitude must be a number/);
  // Back to macOS's own takes the mode out of appearance.local.json.
  mode()[1].listeners.click();
  mode()[1].listeners.click();
  assert.strictEqual("mode" in lastAppearance(), false);
  assert.strictEqual(mode()[2].textContent, "macOS's own");
  // A mode in the shared file can't be taken out here.
  sandbox.tilemo.update({ clockFiles: [], appearanceFiles: { shared: '{"mode": "schedule"}' } });
  assert.strictEqual(mode()[1].disabled, true);
  // Until a change, from tilemo.
  sandbox.tilemo.theme({ chosen: true, dark: false, next: Date.UTC(2026, 10, 4, 18, 0) });
  assert.match(ids["theme-now"].children[0].textContent, /^Light until \d\d:\d\d$/);
  assert.strictEqual(ids["theme-now"].children[1].textContent, "Dark now");
}

// The sidebar, as tide's settings panel's: each group's heading, then its
// pages, with one page showing at a time.
{
  const sidebar = {
    rows: [
      { heading: "Hardware" },
      { page: "displays", label: "Displays" },
      { page: "keyboard", label: "Keyboard" },
      { heading: "General" },
      { page: "clocks", label: "Clocks" },
      { page: "startup", label: "Start at login" },
    ],
    parts: { shortcuts: "keyboard" },
  };
  const nav = () => ids.sidebar.children;
  const showing = () => ["displays", "keyboard", "clocks", "startup"].filter((p) => !ids[`page-${p}`].hidden);
  // The launcher's row for a page shows it, even when it comes before the
  // sidebar does.
  sandbox.tilemo.reveal("startup");
  sandbox.tilemo.update({ clockFiles: [], sidebar });
  assert.deepStrictEqual(nav().map((c) => `${c.tag} ${c.textContent}`), [
    "h3 Hardware", "button Displays", "button Keyboard", "h3 General", "button Clocks", "button Start at login",
  ]);
  assert.deepStrictEqual(showing(), ["startup"]);
  // Each page with its icon, as tide's sidebar has them.
  assert.deepStrictEqual(nav().filter((c) => c.tag === "button").map((c) => c.attrs["data-icon"]),
    ["displays", "keyboard", "clocks", "startup"]);
  assert.deepStrictEqual(nav().filter((c) => c.attrs["aria-current"] === "page").map((c) => c.textContent), ["Start at login"]);
  // A click on a page shows it alone, at its top.
  ids.content.scrollTop = 40;
  nav()[4].listeners.click();
  assert.deepStrictEqual(showing(), ["clocks"]);
  assert.strictEqual(ids.content.scrollTop, 0);
  // Up and Down pass over the headings and stop at either end, but are a
  // field's own while typing there.
  const key = (k, target = {}) => docListeners.keydown({ key: k, target, preventDefault() {} });
  key("ArrowUp");
  assert.deepStrictEqual(showing(), ["keyboard"]);
  key("ArrowUp");
  key("ArrowUp");
  assert.deepStrictEqual(showing(), ["displays"]);
  key("ArrowDown", { tagName: "INPUT" });
  assert.deepStrictEqual(showing(), ["displays"]);
  for (let i = 0; i < 4; i++) key("ArrowDown");
  assert.deepStrictEqual(showing(), ["startup"]);
  // A part of a page shows its page, scrolled to the part.
  let revealed = null;
  sandbox.document.getElementById("shortcuts").scrollIntoView = () => {
    revealed = "shortcuts";
  };
  sandbox.tilemo.reveal("shortcuts");
  assert.deepStrictEqual(showing(), ["keyboard"]);
  assert.strictEqual(revealed, "shortcuts");
  // A new update keeps the page showing; an id it doesn't have shows the
  // first page.
  sandbox.tilemo.update({ clockFiles: [], sidebar });
  assert.deepStrictEqual(showing(), ["keyboard"]);
  sandbox.tilemo.reveal("nothing-by-this-id");
  assert.deepStrictEqual(showing(), ["displays"]);
}

// An app or site typed at the Muted list's foot goes to tilemo, which
// checks it with the mute module and mutes it, or says why not.
{
  const input = sandbox.document.getElementById("add-muted");
  sandbox.tilemo.update({ clockFiles: [], muted: [] });
  sent.length = 0;
  input.value = "  site:mail.example.com ";
  press(input, "Enter");
  assert.strictEqual(JSON.stringify(sent), JSON.stringify([{ mute: "site:mail.example.com" }]));
  assert.strictEqual(input.value, "", "the box empties once it's sent");
  input.value = "";
  press(input, "Enter");
  assert.strictEqual(sent.length, 1, "nothing typed: nothing sent");
  sandbox.tilemo.mutedError("com.example.chat is muted already", "com.example.chat");
  assert.strictEqual(sandbox.document.getElementById("muted-error").textContent, "com.example.chat is muted already");
  assert.strictEqual(input.value, "com.example.chat", "back in the box to fix");
  sandbox.tilemo.update({ clockFiles: [], muted: ["com.example.chat"] });
  assert.strictEqual(sandbox.document.getElementById("muted-error").textContent, "", "new files: the error was about the old ones");
}

// Layouts: tide's layouts.json and layouts.local.json, through tide's own
// rows and steps; only layouts.local.json is written, key by key.
{
  const box = () => sandbox.document.getElementById("layout-rows");
  // Each row is [name, less, value, more]; headings are h2s.
  const layoutRow = (name) => box().children.find((r) => r.tag === "div" && r.children[0].textContent === name);
  const lastLayouts = () => JSON.parse(sent.filter((m) => m.writeLayouts).at(-1).writeLayouts);
  sandbox.tilemo.update({ clockFiles: [], layoutFiles: [] });
  assert.match(sandbox.document.getElementById("layouts-source").textContent, /tide's defaults/);
  assert.strictEqual(layoutRow("Ultrawides start in").children[2].textContent, "Three columns");
  assert.strictEqual(layoutRow("Other monitors start in").children[2].textContent, "Tile");
  assert.strictEqual(layoutRow("New windows go").children[2].textContent, "End of stack");
  assert.ok(box().children.some((r) => r.tag === "h2" && r.textContent === "MASTER WIDTH"));
  // "Tile" names a master width and a master count; the first is the width.
  const tile = () => box().children.filter((r) => r.tag === "div" && r.children[0].textContent === "Tile");
  assert.strictEqual(tile()[0].children[2].textContent, "55%");
  assert.strictEqual(tile()[1].children[2].textContent, "1");
  sent.length = 0;
  tile()[0].children[3].listeners.click();
  assert.deepStrictEqual(lastLayouts(), { modes: { tile: { mfact: 0.6 } } }, "+ steps the master width to the next mark");
  assert.strictEqual(tile()[0].children[2].textContent, "60%", "shown at once");
  layoutRow("New windows go").children[3].listeners.click();
  assert.deepStrictEqual(lastLayouts(), { modes: { tile: { mfact: 0.6 } }, newWindow: "top" }, "builds on the change before");
  layoutRow("Ultrawides start in").children[1].listeners.click();
  assert.strictEqual(lastLayouts().defaultMode.ultrawide, "tile", "‹ steps back through the modes");
  // A lone window's width sets the whole list, as a list is set whole.
  layoutRow("Aspect 2.1 and up").children[1].listeners.click();
  assert.deepStrictEqual(lastLayouts().single, [{ minAspect: 2.1, width: 0.75 }, { minAspect: 3.2, width: 0.6 }]);

  // The shared file's settings show, and a change keeps them out of the
  // local file, which says only what it changes.
  sandbox.tilemo.update({ clockFiles: [], layoutFiles: { shared: '{"modes": {"twocol": {"nmaster": 3}}}' } });
  assert.match(sandbox.document.getElementById("layouts-source").textContent, /layouts\.json, shared with tide/);
  const twocol = () => box().children.filter((r) => r.tag === "div" && r.children[0].textContent === "Two columns");
  assert.strictEqual(twocol()[1].children[2].textContent, "3");
  sent.length = 0;
  twocol()[1].children[1].listeners.click();
  assert.deepStrictEqual(lastLayouts(), { modes: { twocol: { nmaster: 2 } } });
  // Two columns takes one master at fewest, so − stops there.
  sandbox.tilemo.update({ clockFiles: [], layoutFiles: { local: '{"modes": {"twocol": {"nmaster": 1}}}' } });
  assert.match(sandbox.document.getElementById("layouts-source").textContent, /layouts\.local\.json/);
  assert.strictEqual(twocol()[1].children[1].disabled, true);

  // start()'s own layout is what the files lay over: the page shows it, and
  // steps from it, writing only the change.
  const base = { modes: { tile: { mfact: 0.7, nmaster: 1 } }, single: [{ minAspect: 2.5, width: 0.9 }] };
  sandbox.tilemo.update({ clockFiles: [], layoutFiles: [], layoutBase: base });
  assert.strictEqual(tile()[0].children[2].textContent, "70%");
  sent.length = 0;
  tile()[0].children[3].listeners.click();
  assert.deepStrictEqual(lastLayouts(), { modes: { tile: { mfact: 0.75 } } }, "+ widens from what's in effect");
  layoutRow("Aspect 2.5 and up").children[1].listeners.click();
  assert.deepStrictEqual(lastLayouts().single, [{ minAspect: 2.5, width: 0.85 }], "the base's lone-window rules, not tide's");
  sandbox.tilemo.update({ clockFiles: [], layoutFiles: { local: '{"modes": {"tile": {"mfact": 0.6}}}' }, layoutBase: base });
  assert.strictEqual(tile()[0].children[2].textContent, "60%", "the files over the base");

  // A file that's wrong is named, and nothing can change until it's fixed.
  sandbox.tilemo.update({ clockFiles: [], layoutFiles: { local: '{"modes": {"tile": {"mfact": 2}}}' } });
  assert.match(sandbox.document.getElementById("layouts-error").textContent, /layouts\.local\.json: modes\.tile\.mfact must be a number from 0\.1 to 0\.9/);
  assert.strictEqual(layoutRow("New windows go").children[3].disabled, true);
}

// Floating: the rules tilemo hands over, each with up, down and remove,
// which ask tilemo to make the change; Floating now's Always float fills
// the fields, and Enter or Add asks tilemo to add it.
{
  const get = (id) => sandbox.document.getElementById(id);
  const rules = () => get("floating-list").children;
  const now = () => get("floating-now").children;
  const fill = {
    app: "com.example.viewer",
    name: "Viewer",
    title: "^Info %(1%)$",
    covered: "rule 1, com.example.viewer, floats it",
    about: [{ label: "Role", value: "AXWindow" }, { label: "Subrole", value: "AXDialog" }],
  };
  sandbox.tilemo.update({ clockFiles: [], floating: { rules: [], now: [] } });
  assert.strictEqual(rules()[0].textContent, "No rules of your own yet.");
  assert.match(now()[0].textContent, /^None/);
  assert.match(get("floating-source").textContent, /None yet/);
  sandbox.tilemo.update({
    clockFiles: [],
    floating: {
      rules: [{ app: "com.example.a", title: "" }, { app: "com.example.b", title: "^Save" }],
      source: "floating-macos.local.json",
      now: [{ ...fill, covered: undefined, about: [] }],
    },
  });
  assert.match(get("floating-source").textContent, /this Mac's own list/);
  assert.deepStrictEqual(rules().map((li) => li.children.map((c) => c.textContent)),
    [["com.example.a", "every window", "↑", "↓", "✕"], ["com.example.b", "^Save", "↑", "↓", "✕"]]);
  assert.strictEqual(rules()[0].children[2].disabled, true, "the first can't move up");
  assert.strictEqual(rules()[1].children[3].disabled, true, "the last can't move down");
  sent.length = 0;
  rules()[1].children[2].listeners.click();
  rules()[1].children[4].listeners.click();
  assert.deepStrictEqual(sent, [
    { floatMove: { index: 2, app: "com.example.b", title: "^Save", step: -1 } },
    { floatRemove: { index: 2, app: "com.example.b", title: "^Save" } },
  ]);
  // Always float fills the fields, adding nothing yet.
  assert.deepStrictEqual(now()[0].children.map((c) => c.textContent), ["Viewer", "^Info %(1%)$", "Always float"]);
  sent.length = 0;
  now()[0].children[2].listeners.click();
  assert.deepStrictEqual(sent, []);
  assert.strictEqual(get("floating-app").value, "com.example.viewer");
  assert.strictEqual(get("floating-title").value, "^Info %(1%)$");
  assert.strictEqual(get("floating-about").hidden, true, "nothing more to say, no section");
  // Enter adds it; tilemo answers, and the fields clear.
  get("floating-title").listeners.keydown({ key: "Enter", target: get("floating-title") });
  assert.deepStrictEqual(sent, [{ floatAdd: { app: "com.example.viewer", title: "^Info %(1%)$" } }]);
  sandbox.tilemo.floatingDone(true);
  assert.strictEqual(get("floating-app").value, "");
  // The key's fill-in: what covers it and what macOS says of it.
  sandbox.tilemo.floatingFill(fill);
  assert.strictEqual(get("floating-covered").textContent, "Already floating: rule 1, com.example.viewer, floats it.");
  assert.strictEqual(get("floating-about").hidden, false);
  assert.deepStrictEqual(get("floating-about-rows").children.map((c) => c.textContent), ["Role", "AXWindow", "Subrole", "AXDialog"]);
  // An error from tilemo shows; Esc clears the fields, and doesn't close.
  sandbox.tilemo.floatingError("the title isn't a Lua pattern: malformed pattern");
  assert.match(get("floating-error").textContent, /isn't a Lua pattern/);
  const esc = { key: "Escape", target: get("floating-app") };
  get("floating-app").listeners.keydown(esc);
  assert.strictEqual(esc.handled, true);
  assert.strictEqual(get("floating-title").value, "");
  assert.strictEqual(get("floating-error").textContent, "");
  assert.strictEqual(get("floating-about").hidden, true);
  // An empty app is refused here, sending nothing.
  sent.length = 0;
  get("floating-add-button").listeners.click();
  assert.deepStrictEqual(sent, []);
  assert.match(get("floating-error").textContent, /bundle ID/);
  // A file that's wrong: named, and nothing changes here until it's fixed.
  sandbox.tilemo.update({ clockFiles: [], floating: { rules: [{ app: "com.example.a", title: "" }], now: [], error: "floating-macos.local.json: rules[2] names no app" } });
  assert.match(get("floating-error").textContent, /rules\[2\] names no app\. Fix the file/);
  assert.strictEqual(get("floating-app").disabled, true);
  assert.strictEqual(rules()[0].children[4].disabled, true);
}

// Each section's buttons, as tilemo lists them: shown in its row, by
// label, and a click sends back only the button's name.
{
  const links = [
    { section: "mouse", name: "mouse", label: "Mouse settings" },
    { section: "mouse", name: "linearmouse", label: "LinearMouse settings" },
    { section: "idle", name: "lock_screen", label: "Lock Screen settings" },
  ];
  sandbox.tilemo.update({ clockFiles: [], links, mouse: { problem: "" } });
  const mouse = ids["mouse-links"].children;
  assert.deepStrictEqual(mouse.map((b) => b.textContent), ["Mouse settings", "LinearMouse settings"]);
  assert.deepStrictEqual(ids["idle-links"].children.map((b) => b.textContent), ["Lock Screen settings"]);
  // Each a row that opens another window, as tide's advanced row.
  assert.deepStrictEqual(mouse.map((b) => b.attrs["data-icon"]), ["open", "open"]);
  sent.length = 0;
  mouse[1].listeners.click();
  assert.deepStrictEqual(sent, [{ open: "linearmouse" }]);
  // Drawn again, not added to.
  sandbox.tilemo.update({ clockFiles: [], links, mouse: { problem: "" } });
  assert.strictEqual(ids["mouse-links"].children.length, 2);
  // What's wrong with LinearMouse shows only when something is.
  assert.strictEqual(ids["mouse-error"].textContent, "");
  sandbox.tilemo.update({ clockFiles: [], links, mouse: { problem: "LinearMouse isn't running." } });
  assert.strictEqual(ids["mouse-error"].textContent, "LinearMouse isn't running.");
  sandbox.tilemo.update({ clockFiles: [], links, mouse: { problem: "" } });
  assert.strictEqual(ids["mouse-error"].textContent, "");
}

// The Keyboard section: each of conf's Karabiner rules with On or Off, and a
// click asks tilemo to switch it; what's wrong shows only when something is.
{
  const rules = [
    { description: "Ctrl+Tab goes to the next tab, not the application switcher (PC)", label: "Ctrl+Tab goes to the next tab, not the application switcher", on: false },
    { description: "tilemo: Win is Super", label: "tilemo: Win is Super", on: true },
  ];
  sandbox.tilemo.update({ clockFiles: [], keyboard: { rules, problem: "" } });
  const rows = ids["karabiner-rules"].children;
  assert.deepStrictEqual(rows.map((li) => li.children.map((c) => c.textContent)), [
    ["Ctrl+Tab goes to the next tab, not the application switcher", "Off"],
    ["tilemo: Win is Super", "On"],
  ]);
  assert.strictEqual(rows[0].children[1].attrs["aria-pressed"], "false");
  assert.strictEqual(rows[1].children[1].attrs["aria-pressed"], "true");
  sent.length = 0;
  rows[0].children[1].listeners.click();
  assert.deepStrictEqual(sent, [{ karabinerRule: { description: rules[0].description, on: true } }]);
  sent.length = 0;
  rows[1].children[1].listeners.click();
  assert.deepStrictEqual(sent, [{ karabinerRule: { description: rules[1].description, on: false } }]);
  assert.strictEqual(ids["keyboard-error"].textContent, "");
  sandbox.tilemo.update({ clockFiles: [], keyboard: { rules: [], problem: "Karabiner-Elements isn't running." } });
  assert.strictEqual(ids["karabiner-rules"].children.length, 0);
  assert.strictEqual(ids["keyboard-error"].textContent, "Karabiner-Elements isn't running.");
  sandbox.tilemo.keyboardError("karabiner.json isn't JSON");
  assert.strictEqual(ids["keyboard-error"].textContent, "karabiner.json isn't JSON");
}

// Keyboard's Shortcuts: each binding's keys and what it does, in tilemo's
// order, resize mode's prefixed, one with no description saying so; then
// the keys that didn't register, and why. Nothing is sent: they're
// read-only.
{
  sent.length = 0;
  sandbox.tilemo.update({
    clockFiles: [],
    shortcuts: {
      binds: [
        { keys: "Super+J", does: "Focus down the stack", submap: "" },
        { keys: "Super+Q", does: "", submap: "" },
        { keys: "H", does: "Narrower", submap: "Resize mode" },
      ],
      failed: [{ keys: "Super+Print", does: "Screenshot of a region", why: "the same keys as Alt+Print (Screenshot of the window)" }],
    },
  });
  const rows = ids["shortcut-list"].children;
  assert.deepStrictEqual(rows.map((li) => li.children.map((c) => c.textContent)), [
    ["Super+J", "Focus down the stack"],
    ["Super+Q", "no description"],
    ["Resize mode: H", "Narrower"],
  ]);
  assert.strictEqual(rows[1].className, "undescribed");
  assert.match(ids["shortcuts-error"].textContent, /didn't register/);
  assert.deepStrictEqual(ids["shortcut-failed"].children.map((li) => li.children.map((c) => c.textContent)), [
    ["Super+Print", "Screenshot of a region: the same keys as Alt+Print (Screenshot of the window)"],
  ]);
  assert.deepStrictEqual(sent.filter((m) => !m.write), []);
  // Every key registered: no failures, and nothing said.
  sandbox.tilemo.update({ clockFiles: [], shortcuts: { binds: [], failed: [] } });
  assert.strictEqual(ids["shortcut-list"].children.length, 0);
  assert.strictEqual(ids["shortcuts-error"].textContent, "");
  assert.strictEqual(ids["shortcut-failed"].children.length, 0);
}

// The Mouse section: the Mac's own Speed and Acceleration, sent for
// LinearMouse's config; then tide's Scroll speed and Natural scrolling
// rows, each change written to input.local.json, keeping what else it says.
{
  const all = () => ids["mouse-rows"].children;
  // tide's rows, after the Mac's two.
  const rows = () => all().slice(2);
  const lastInput = () => JSON.parse(sent[sent.length - 1].writeInput);
  sandbox.tilemo.update({ clockFiles: [], mouse: { problem: "" } });
  assert.deepStrictEqual(all().map((r) => r.children[0].textContent), ["Speed", "Acceleration", "Scroll speed", "Natural scrolling"]);
  // Left to macOS: said so, and the first step lands on setup-macos's.
  assert.strictEqual(all()[0].children[2].textContent, "macOS's");
  sent.length = 0;
  all()[0].children[3].listeners.click();
  all()[1].children[1].listeners.click();
  assert.deepStrictEqual(sent, [{ mousePointer: { key: "speed", value: 0.35 } }, { mousePointer: { key: "acceleration", value: 1.5 } }]);
  // As LinearMouse has them, stepped along the Mac's ladders.
  sandbox.tilemo.update({ clockFiles: [], mouse: { problem: "", pointer: { speed: 0.35, acceleration: 1.5 } } });
  assert.strictEqual(all()[0].children[2].textContent, "0.35");
  assert.strictEqual(all()[1].children[2].textContent, "1.5");
  sent.length = 0;
  all()[0].children[3].listeners.click();
  all()[1].children[1].listeners.click();
  assert.deepStrictEqual(sent, [{ mousePointer: { key: "speed", value: 0.4 } }, { mousePointer: { key: "acceleration", value: 1.25 } }]);
  sandbox.tilemo.update({ clockFiles: [], mouse: { problem: "", pointer: { speed: 1, acceleration: 0 } } });
  assert.strictEqual(all()[0].children[3].disabled, true, "the fastest");
  assert.strictEqual(all()[1].children[1].disabled, true, "no acceleration");
  sandbox.tilemo.update({ clockFiles: [], mouse: { problem: "" } });
  // tide's defaults for a mouse: 3x, natural scrolling off.
  assert.strictEqual(rows()[0].children[2].textContent, "3×");
  assert.strictEqual(rows()[1].children[2].textContent, "Off");
  assert.strictEqual(rows()[1].children[2].attrs["aria-pressed"], "false");
  sent.length = 0;
  rows()[0].children[3].listeners.click();
  assert.deepStrictEqual(lastInput(), { mouse: { scrollSpeed: 4 } });
  // Shown at once, and the next change builds on it.
  assert.strictEqual(rows()[0].children[2].textContent, "4×");
  rows()[1].children[2].listeners.click();
  assert.deepStrictEqual(lastInput(), { mouse: { scrollSpeed: 4, naturalScroll: true } });
  // The local file over the shared one, and the rest of the local file kept.
  const shared = JSON.stringify({ mouse: { scrollSpeed: 1 } });
  const local = JSON.stringify({ keyboard: { repeatDelay: 300 }, mouse: { naturalScroll: true } });
  sandbox.tilemo.update({ clockFiles: [], inputFiles: { shared, local }, mouse: { problem: "" } });
  assert.strictEqual(rows()[0].children[2].textContent, "1×");
  assert.strictEqual(rows()[1].children[2].textContent, "On");
  rows()[0].children[1].listeners.click();
  assert.deepStrictEqual(lastInput(), { mouse: { scrollSpeed: 0.75, naturalScroll: true }, keyboard: { repeatDelay: 300 } });
  // At the end of the ladder, the button is off.
  sandbox.tilemo.update({ clockFiles: [], inputFiles: { local: JSON.stringify({ mouse: { scrollSpeed: 5 } }) }, mouse: { problem: "" } });
  assert.strictEqual(rows()[0].children[3].disabled, true);
  // A file that's wrong: named with LinearMouse's problem, and nothing
  // changes here until it's fixed.
  sandbox.tilemo.update({ clockFiles: [], inputFiles: { local: '{"mouse": {"scrollSpeed": "fast"}}' }, mouse: { problem: "LinearMouse isn't running." } });
  assert.match(ids["mouse-error"].textContent, /^LinearMouse isn't running\. input\.local\.json: mouse\.scrollSpeed must be a number\. Fix the file/);
  assert.strictEqual(rows()[0].children[1].disabled, true);
  assert.strictEqual(rows()[1].children[2].disabled, true);
}

// The Workspaces section, as tide's Workspaces page: the standing
// workspaces, home's apps and the name patterns, each change written to
// workspaces.local.json with the file's other settings kept.
{
  const items = (key) => ids[`ws-list-${key}`].children.map((li) => li.children.map((c) => c.textContent));
  const lastWs = () => JSON.parse(sent.filter((m) => m.writeWorkspaces).at(-1).writeWorkspaces);
  const base = { standing: ["in", "re", "oc", "me"], inApps: ["Mail", "Gmail"] };
  // No files: what's in effect, start()'s lists or tilemo's defaults.
  sandbox.tilemo.update({ clockFiles: [], workspaceBase: base });
  assert.match(ids["workspaces-source"].textContent, /The defaults/);
  assert.deepStrictEqual(items("standing")[0], ["in", "home", "↑", "↓", "✕"]);
  assert.deepStrictEqual(items("inApps"), [["Mail", "✕"], ["Gmail", "✕"]]);
  assert.deepStrictEqual(ids["ws-list-namePatterns"].children.map((li) => li.textContent), ["None yet."]);
  assert.strictEqual(ids["ws-add-inApps"].placeholder, "Add a program or web address, such as gmail");

  // The first change copies the list in effect, keeping `muted`.
  sandbox.tilemo.update({ clockFiles: [], workspaceBase: base, workspaceFiles: { local: '{"muted": ["com.example.chat"]}' } });
  sent.length = 0;
  const add = ids["ws-add-inApps"];
  add.value = "Google Chat";
  press(add, "Enter");
  assert.deepStrictEqual(lastWs(), { muted: ["com.example.chat"], inApps: ["Mail", "Gmail", "Google Chat"] });
  assert.strictEqual(add.value, "", "the box empties once it's added");
  // One listed already, ignoring case, is refused, and nothing is written.
  const before = sent.length;
  add.value = "mail";
  press(add, "Enter");
  assert.match(ids["workspaces-error"].textContent, /listed already/);
  assert.strictEqual(sent.length, before);

  // Moving one first makes it home; taking out the last is refused.
  sandbox.tilemo.update({ clockFiles: [], workspaceBase: base, workspaceFiles: { shared: '{"standing": ["in", "re"]}' } });
  assert.match(ids["workspaces-source"].textContent, /shared with tide/);
  ids["ws-list-standing"].children[1].children[2].listeners.click();
  assert.deepStrictEqual(lastWs(), { standing: ["re", "in"] });
  assert.deepStrictEqual(items("standing").map((r) => r.slice(0, 2)), [["re", "home"], ["in", ""]]);
  sandbox.tilemo.update({ clockFiles: [], workspaceBase: base, workspaceFiles: { local: '{"standing": ["in"]}' } });
  ids["ws-list-standing"].children[0].children[4].listeners.click();
  assert.match(ids["workspaces-error"].textContent, /at least one workspace/);

  // A pattern that doesn't compile or has no capture group is refused.
  const pat = ids["ws-add-namePatterns"];
  pat.value = "([A-Z]+";
  press(pat, "Enter");
  assert.notStrictEqual(ids["workspaces-error"].textContent, "");
  pat.value = "[A-Z]+-[0-9]+";
  press(pat, "Enter");
  assert.match(ids["workspaces-error"].textContent, /capture group/);
  pat.value = "\\b([A-Z]+-[0-9]+)\\b";
  press(pat, "Enter");
  assert.deepStrictEqual(lastWs().namePatterns, ["\\b([A-Z]+-[0-9]+)\\b"]);

  // A file that's wrong can't be changed here, and the page says so.
  sandbox.tilemo.update({ clockFiles: [], workspaceBase: base, workspaceFiles: { local: '{"standing": []}' } });
  assert.match(ids["workspaces-error"].textContent, /workspaces\.local\.json: standing must name/);
  assert.strictEqual(ids["ws-add-standing"].disabled, true);
  assert.deepStrictEqual(items("standing"), []);
}

// The Setup checklist: each permission's state and an Open for its pane;
// each setting with its tick, and a click on either sends only a name.
{
  const setup = {
    permissions: [
      { id: "accessibility", title: "Accessibility for Hammerspoon", how: "Turn it on.", ref: "§11.1", link: "privacy_accessibility", state: "off", label: "Off" },
      { id: "screen_recording", title: "Screen Recording", how: "Leave it off.", ref: "§11.1", link: "privacy_screen_recording", state: "not_needed", label: "Not needed" },
    ],
    items: [
      { id: "lock", title: "Ask for the password at once", how: "Immediately.", ref: "§10", link: "lock_screen", done: true },
      { id: "minimize", title: "Minimize into the app's icon", how: "Scale effect.", ref: "§6", link: "desktop_dock", done: false },
    ],
    left: 1,
  };
  sandbox.tilemo.update({ clockFiles: [], setup });
  const perms = ids["setup-permissions"].children;
  assert.deepStrictEqual(perms.map((li) => li.children.map((c) => c.textContent)), [
    ["Accessibility for Hammerspoon", "Off", "Open", "Turn it on. (§11.1)"],
    ["Screen Recording", "Not needed", "Open", "Leave it off. (§11.1)"],
  ]);
  assert.strictEqual(perms[0].children[1].className, "off");
  const items = ids["setup-items"].children;
  assert.deepStrictEqual(items.map((li) => [li.children[0].checked, li.children[1].textContent]), [
    [true, "Ask for the password at once"],
    [false, "Minimize into the app's icon"],
  ]);
  assert.strictEqual(ids["setup-summary"].textContent, "1 of 2 still to do.");
  sent.length = 0;
  perms[0].children[2].listeners.click();
  items[1].children[2].listeners.click();
  assert.deepStrictEqual(sent, [{ open: "privacy_accessibility" }, { open: "desktop_dock" }]);
  sent.length = 0;
  items[1].children[0].checked = true;
  items[1].children[0].listeners.change();
  assert.deepStrictEqual(sent, [{ setupTick: { id: "minimize", on: true } }]);
  // tilemo answers with the checklist alone, drawn again, not added to.
  sandbox.tilemo.setup({ ...setup, items: setup.items.map((i) => ({ ...i, done: true })), left: 0 });
  assert.strictEqual(ids["setup-items"].children.length, 2);
  assert.strictEqual(ids["setup-summary"].textContent, "All done.");
  // Coming back to the window asks for the permissions as they are now.
  sent.length = 0;
  windowListeners.focus();
  assert.deepStrictEqual(sent, [{ setupRefresh: true }]);
}

// The Switcher row: the launcher in use, with ‹ and › to the other, which
// asks tilemo to switch.
{
  const choices = [
    { value: "chooser", label: "tide's switcher" },
    { value: "dashboard", label: "tileco's launcher" },
  ];
  sandbox.tilemo.update({ clockFiles: [], launcher: { value: "chooser", choices } });
  const row = ids["launcher-choice"].children;
  assert.deepStrictEqual(row.map((c) => c.textContent), ["Switcher", "‹", "tide's switcher", "›"]);
  sent.length = 0;
  row[3].listeners.click();
  assert.deepStrictEqual(sent, [{ launcher: "dashboard" }]);
  sent.length = 0;
  row[1].listeners.click();
  assert.deepStrictEqual(sent, [{ launcher: "dashboard" }], "two choices: either way is the other");
  sandbox.tilemo.update({ clockFiles: [], launcher: { value: "dashboard", choices } });
  assert.strictEqual(ids["launcher-choice"].children[2].textContent, "tileco's launcher");
}

// The Appearance page's Menu bar switch: on unless tilemo says it's off,
// and a click asks for the other.
{
  sandbox.tilemo.update({ clockFiles: [], menuBar: { hidden: true } });
  const toggle = ids["menubar-hidden"];
  assert.strictEqual(toggle.textContent, "Menu bar kept hidden");
  assert.strictEqual(toggle.attrs["aria-pressed"], "true");
  sent.length = 0;
  toggle.listeners.click();
  assert.deepStrictEqual(sent, [{ keepMenuBarHidden: false }]);
  sandbox.tilemo.update({ clockFiles: [], menuBar: { hidden: false } });
  assert.strictEqual(toggle.textContent, "Menu bar shows at the top edge");
  sent.length = 0;
  toggle.listeners.click();
  assert.deepStrictEqual(sent, [{ keepMenuBarHidden: true }]);
}

console.log("settings page: ok");
