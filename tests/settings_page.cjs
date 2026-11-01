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
}

const ids = {};
const sent = [];
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= new Element(id)),
    addEventListener: () => {},
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

// The launcher's rows scroll to their section.
let revealed = null;
sandbox.document.getElementById("startup").scrollIntoView = () => {
  revealed = "startup";
};
sandbox.tilemo.reveal("startup");
assert.strictEqual(revealed, "startup");
sandbox.tilemo.reveal("nothing-by-this-id");

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

console.log("settings page: ok");
