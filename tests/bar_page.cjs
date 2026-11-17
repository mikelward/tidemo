// Runs the bar's bundled script (tests/bar_test.lua writes it to the file
// named on the command line) against a small fake DOM, and checks
// tide.update() draws the chips, title, clocks and icons, and what clicks
// and scrolls send back.

const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

class Element {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.className = "";
    this.textContent = "";
    this.innerHTML = "";
    // Custom properties, as style.setProperty sets them, beside the rest.
    this.style = { setProperty: (k, v) => (this.style[k] = v) };
    // No layout: a test sets `rect` to give an element a box.
    this.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
    this.attrs = {};
    this.listeners = {};
    const classes = new Set();
    // As the DOM's: without a second argument, or with undefined, it flips.
    this.classList = {
      toggle: (c, on) => {
        const add = on === undefined ? !classes.has(c) : on;
        if (add) classes.add(c);
        else classes.delete(c);
        return add;
      },
      contains: (c) => classes.has(c),
    };
    this.classes = () => new Set([...this.className.split(" ").filter(Boolean), ...classes]);
  }
  append(...xs) {
    for (const x of xs) {
      if (typeof x !== "string") x.parent = this;
      this.children.push(typeof x === "string" ? { text: x } : x);
    }
  }
  // One compound selector: tag, #id and .classes.
  is(compound) {
    const tag = compound.match(/^[a-z]+/)?.[0];
    const id = compound.match(/#([\w-]+)/)?.[1];
    const classes = [...compound.matchAll(/\.([\w-]+)/g)].map((m) => m[1]);
    return (!tag || tag === this.tag) && (!id || id === this.id) && classes.every((c) => this.classes().has(c));
  }
  // Enough of the DOM's: compounds joined by " " and " > ".
  matches(selector) {
    return selector.split(",").some((sel) => {
      const parts = sel.trim().split(/\s+/);
      const at = (e, i) => {
        if (!e || !e.is(parts[i])) return false;
        if (i === 0) return true;
        if (parts[i - 1] === ">") return at(e.parent, i - 2);
        for (let a = e.parent; a; a = a.parent) if (at(a, i - 1)) return true;
        return false;
      };
      return at(this, parts.length - 1);
    });
  }
  closest(selector) {
    for (let e = this; e; e = e.parent) if (e.matches(selector)) return e;
    return null;
  }
  getBoundingClientRect() {
    return this.rect;
  }
  get parentNode() {
    return this.parent ?? null;
  }
  remove() {
    if (this.parent) this.parent.children = this.parent.children.filter((c) => c !== this);
    this.parent = undefined;
  }
  replaceChildren() {
    this.children = [];
  }
  setAttribute(k, v) {
    this.attrs[k] = v;
  }
  getAttribute(k) {
    return k in this.attrs ? this.attrs[k] : null;
  }
  addEventListener(type, fn) {
    this.listeners[type] = fn;
  }
}

const ids = {};
// The page's own elements, as bar.html has them.
const TAGS = { bar: "header", left: "div", logo: "button", workspaces: "nav", title: "span", "title-text": "span", right: "div", "icons-lead": "div", clocks: "ol", icons: "div" };
const byId = (id) => {
  const e = new Element(TAGS[id] ?? id);
  e.id = id;
  return e;
};
// What's under a point, as a test sets it.
let under = null;
const sent = [];
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= byId(id)),
    elementFromPoint: () => under,
    addEventListener: () => {},
    // The bar's colors are custom properties on the root (colorBar).
    documentElement: {
      style: {
        props: {},
        setProperty(k, v) {
          this.props[k] = v;
        },
        removeProperty(k) {
          delete this.props[k];
        },
      },
    },
  },
  // The page's clock tick, which fits the bar again.
  setInterval: (fn) => {
    sandbox.tick = fn;
    return 0;
  },
  Intl,
  Date,
  Math,
  Number,
  String,
  Object,
  Error,
  Map,
  Set,
};
sandbox.window = sandbox;
sandbox.webkit = { messageHandlers: { tide: { postMessage: (m) => sent.push(m) } } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

const ws = [
  { n: "in" },
  { n: "web", current: true },
  { n: "docs" },
  {
    n: "ABC-123 fix the login page",
    occupied: true,
    urgent: true,
    apps: ["com.a", "com.b", "com.a", "com.c", "com.d"],
    wins: [11, 12, 13, 14, 15],
    more: 2,
  },
];
sandbox.tide.update({
  uuid: "B",
  workspaces: ws,
  title: "Chat (1)",
  app_icons: { "com.a": "data:image/png;base64,QQ==", "com.b": "data:image/png;base64,Qg==", "com.c": false },
  icons: {
    source: { label: "DVO", name: "Dvorak" },
    awake: { on: false },
    camera: { in_use: true },
    mic: { muted: false },
    wifi: { on: true, bars: 2, name: "home" },
    network: { kind: "wifi" },
    volume: { level: "mute", muted: true },
    battery: { percent: 15, charging: false, text: "15%", tip: "Battery 15%, 0:40 left" },
  },
});

const chips = ids.workspaces.children;
assert.strictEqual(
  chips.map((b) => b.children[0].textContent).join("|"),
  "in|web|docs|ABC-123 fix the …",
  "every workspace, by name, a long one cut",
);
// The bar's window is never key, so WebKit would show no title attribute's
// tooltip: a tip is data-tip, which tide draws on hover (below).
assert.strictEqual(chips[3].attrs["data-tip"], "ABC-123 fix the login page", "the whole name on hover");
assert.strictEqual(chips[1].getAttribute("data-tip"), null, "a whole name has no tip");
for (const e of [...chips, ...ids.icons.children]) assert.ok(e.attrs.title === undefined && e.title === undefined, `${e.className || "a chip"} has no title attribute`);
// A chip's name, then one icon per window wanting attention, then how many
// more.
const parts = chips[3].children;
assert.deepStrictEqual(
  parts.map((c) => c.tag + "." + c.className),
  ["span.n", "img.app win", "img.app win", "img.app win", "span.app none win", "span.app none win", "span.more"],
);
assert.strictEqual(parts[1].src, "data:image/png;base64,QQ==");
assert.strictEqual(parts[3].src, parts[1].src, "one icon per window, so an app's second window repeats it");
assert.strictEqual(parts[6].textContent, "+2");
assert.strictEqual(chips[0].children.length, 1, "an empty chip is its name alone");
assert.ok(chips[1].classList.contains("current"));
assert.ok(!chips[2].classList.contains("current"), "one workspace shows, on every display");
assert.ok(chips[3].classList.contains("urgent"));
assert.strictEqual(ids["title-text"].textContent, "Chat (1)");
assert.ok(ids.clocks.children.length >= 1, "the clocks row");

const icons = ids.icons.children;
const byName = Object.fromEntries(icons.map((b) => [b.className.replace("icon ", ""), b]));
assert.deepStrictEqual(
  icons.map((b) => b.className),
  ["icon source", "icon awake", "icon camera", "icon mic", "icon volume", "icon wifi", "icon battery", "icon session"],
);
assert.strictEqual(byName.source.textContent, "DVO");
assert.strictEqual(byName.source.attrs["data-tip"], "Dvorak");
// Each icon is a line drawing, with its state in data-state.
const state = (b) => b.attrs["data-state"];
for (const b of icons) if (b.className !== "icon source") assert.ok(b.innerHTML.startsWith("<svg "), `${b.className} is drawn`);
assert.strictEqual(state(byName.awake), "off");
assert.strictEqual(byName.awake.attrs["data-tip"], "Not keeping awake", "what it's doing, in the sign's words");
assert.strictEqual(state(byName.camera), "in-use");
assert.strictEqual(byName.camera.attrs["data-tip"], "Camera in use");
assert.strictEqual(byName.mic.attrs["data-tip"], "Microphone");
assert.strictEqual(state(byName.mic), "on");
assert.ok(!byName.mic.innerHTML.includes("M2.5 2.5l11 11"), "no slash on a live microphone");
assert.strictEqual(state(byName.wifi), "bars-2");
assert.strictEqual(byName.wifi.innerHTML.split('opacity="0.3"').length - 1, 1, "two of three Wi-Fi arcs lit");
assert.strictEqual(byName.wifi.attrs["data-tip"], "home");
assert.strictEqual(state(byName.volume), "mute");
assert.ok(byName.volume.innerHTML.includes("M11 6.5l3 3"), "the speaker's cross");
assert.strictEqual(state(byName.battery), "low");
assert.strictEqual(byName.battery.attrs["data-tip"], "Battery 15%, 0:40 left");
assert.ok(byName.battery.innerHTML.includes('width="1.20"'), "a bar 15% full");
assert.strictEqual(byName.battery.children[0].textContent, "15%");

// No sizes in the fake DOM, so nothing counts as crowded.
assert.strictEqual(ids.clocks.classList.contains("compact"), false);

chips[2].listeners.click();
// An attention icon focuses its window, and the chip doesn't also show its
// workspace.
let stopped = false;
parts[3].listeners.click({ stopPropagation: () => (stopped = true) });
assert.ok(stopped, "the click stays with the icon");
parts[4].listeners.click({ stopPropagation() {} });
byName.wifi.listeners.click();
ids.clocks.listeners.click();
ids.logo.listeners.click();
ids.bar.listeners.dblclick({ target: ids.title });
// The free bar around the title is the title's too, but a double click on
// an item isn't.
ids.bar.listeners.dblclick({ target: ids.bar });
ids.bar.listeners.dblclick({ target: chips[0] });
const wheel = (deltaY) => ids.workspaces.listeners.wheel({ deltaY, preventDefault() {} });
wheel(20);
wheel(40);
wheel(-60);
byName.mic.listeners.click();
byName.volume.listeners.click();
byName.awake.listeners.click();
byName.source.listeners.click();
byName.battery.listeners.click();
const spin = (deltaY) => byName.volume.listeners.wheel({ deltaY, preventDefault() {} });
spin(-60);
spin(30);
spin(30);
assert.strictEqual(
  JSON.stringify(sent.filter((m) => !m.goodClocks)),
  JSON.stringify([
    { uuid: "B", show: "docs" },
    { uuid: "B", focus: 13 },
    { uuid: "B", focus: 14 },
    { uuid: "B", open: "wifi" },
    { uuid: "B", dashboard: true },
    { uuid: "B", switcher: true },
    { uuid: "B", maximize: true },
    { uuid: "B", maximize: true },
    { uuid: "B", step: 1 },
    { uuid: "B", step: -1 },
    { uuid: "B", toggle: "mic" },
    { uuid: "B", sound: { right: 0 } },
    { uuid: "B", toggle: "awake" },
    { uuid: "B", toggle: "source" },
    { uuid: "B", open: "battery" },
    { uuid: "B", volume: 1 },
    { uuid: "B", volume: -1 },
  ]),
  "every message names this bar's display",
);
sent.length = 0;

// A VPN's lock sits on the network icon, as tide's, and the tip says so.
for (const [network, wifi, cls, tip] of [
  [{ kind: "wifi", vpn: true }, { on: true, bars: 3, name: "home" }, "icon wifi", "home, VPN on"],
  [{ kind: "wired", vpn: true }, undefined, "icon wired", "Wired network, VPN on"],
  [{ kind: "wired" }, undefined, "icon wired", "Wired network"],
]) {
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { network, wifi } });
  const n = ids.icons.children[0];
  assert.strictEqual(n.className, cls);
  assert.strictEqual(n.attrs["data-tip"], tip);
  assert.strictEqual(n.innerHTML.includes("<circle "), !!network.vpn, `${tip}: the lock`);
  assert.strictEqual(n.attrs["data-vpn"], network.vpn ? "on" : undefined);
}

// The system monitor: CPU % after the battery, its tone as its state, and
// a click opens Activity Monitor.
for (const tone of ["normal", "warn", "danger"]) {
  sandbox.tide.update({
    uuid: "B",
    workspaces: ws,
    title: "",
    icons: { battery: { percent: 50, text: "50%" }, sysmon: { text: "23%", tone, tip: "CPU 23%" } },
  });
  const shown = ids.icons.children.map((c) => c.className);
  assert.deepStrictEqual(shown.slice(-3), ["icon battery", "icon sysmon", "icon session"], "after the battery");
  const s = ids.icons.children.at(-2);
  assert.strictEqual(s.attrs["data-state"], tone);
  assert.strictEqual(s.attrs["data-tip"], "CPU 23%");
  assert.strictEqual(s.children[0].textContent, "23%");
  assert.ok(s.innerHTML.startsWith("<svg "), "drawn");
  s.listeners.click();
  assert.strictEqual(JSON.stringify(sent.at(-1)), JSON.stringify({ uuid: "B", open: "sysmon" }));
}
sent.length = 0;

// The Bar page's icons: only those tide sends, in its order; an id the page
// doesn't know draws nothing. Other apps' icons shows the menu bar.
sandbox.tide.update({
  uuid: "B", workspaces: ws, title: "", iconOrder: ["session", "battery", "nonsense", "tray"],
  icons: { mic: { muted: false }, battery: { percent: 50, text: "50%" } },
});
{
  const shown = ids.icons.children.map((c) => c.className);
  assert.deepStrictEqual(shown, ["icon session", "icon battery", "icon tray"], "the mic and network are off");
  const tray = ids.icons.children[2];
  assert.strictEqual(tray.attrs["data-tip"], "Other apps' icons");
  sent.length = 0;
  tray.listeners.click();
  assert.strictEqual(JSON.stringify(sent), JSON.stringify([{ uuid: "B", tray: true }]));
}
sent.length = 0;

// The clocks move as an icon does: icons before them in the order go ahead
// of them, and without "clock" they're hidden.
sandbox.tide.update({
  uuid: "B", workspaces: ws, title: "", iconOrder: ["battery", "clock", "session"],
  icons: { battery: { percent: 50, text: "50%" } },
});
assert.deepStrictEqual(ids["icons-lead"].children.map((c) => c.className), ["icon battery"], "the battery left of the clocks");
assert.deepStrictEqual(ids.icons.children.map((c) => c.className), ["icon session"], "the session icon right of them");
assert.strictEqual(ids.clocks.hidden, false, "the clocks show");
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", iconOrder: ["battery"], icons: { battery: { percent: 50, text: "50%" } } });
assert.strictEqual(ids.clocks.hidden, true, "turned off, the clocks hide");
assert.strictEqual(ids["icons-lead"].children.length, 0);
assert.deepStrictEqual(ids.icons.children.map((c) => c.className), ["icon battery"]);

// Every icon off: tide's empty list comes through JSON as [] or {}, and
// either draws none, not the bar's own order.
for (const iconOrder of [[], {}]) {
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", iconOrder, icons: { battery: { percent: 50, text: "50%" } } });
  assert.strictEqual(ids.icons.children.length, 0, `none for ${JSON.stringify(iconOrder)}`);
}

// The session icon, last unless moved, sends where it is, so tide can hang
// macOS's menu under it.
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: {} });
{
  const s = ids.icons.children.at(-1);
  assert.strictEqual(s.className, "icon session");
  assert.strictEqual(s.attrs["data-tip"], "Lock, log out or power off");
  assert.ok(s.innerHTML.startsWith("<svg "), "drawn");
  s.rect = { left: 1880, right: 1906, top: 5, bottom: 31, width: 26, height: 26 };
  s.listeners.click();
  assert.strictEqual(JSON.stringify(sent.at(-1)), JSON.stringify({ uuid: "B", session: { x: 1880 } }));
  assert.strictEqual(sent.filter((m) => m.session).length, 1, "one message per click");
}
sent.length = 0;

// The speaker's level as a %, and an output with no volume control (a
// monitor's speakers): the full speaker with no %, no scrolling, and a
// click opens the popover under it all the same.
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { volume: { level: "mid", muted: false, text: "40%", tip: "Sound 40%" } } });
{
  const v = ids.icons.children[0];
  assert.strictEqual(v.children[0].textContent, "40%");
  assert.strictEqual(v.attrs["data-tip"], "Sound 40%");
}
for (const can_mute of [true, false]) {
  sandbox.tide.update({
    uuid: "B",
    workspaces: ws,
    title: "",
    icons: { volume: { level: "fixed", muted: false, fixed: true, can_mute, tip: "Sound: LG has no volume control" } },
  });
  const v = ids.icons.children[0];
  assert.strictEqual(v.className, "icon volume");
  assert.strictEqual(v.attrs["data-state"], "fixed");
  assert.strictEqual(v.children.length, 0, "no %");
  assert.strictEqual(v.innerHTML.split("<path ").length - 1, 4, "the speaker and all three waves");
  assert.strictEqual(v.attrs["data-tip"], "Sound: LG has no volume control");
  assert.strictEqual(v.listeners.wheel, undefined, "nothing to scroll");
  v.rect = { left: 1700, right: 1730, top: 0, bottom: 30, width: 30, height: 30 };
  v.listeners.click();
  assert.strictEqual(JSON.stringify(sent.at(-1)), JSON.stringify({ uuid: "B", sound: { right: 1730 } }), "the popover, which says it has no volume control");
}
sent.length = 0;

// Each connected Bluetooth audio device, beside the speaker, named on
// hover, and a click opens Bluetooth settings.
sandbox.tide.update({
  uuid: "B",
  workspaces: ws,
  title: "",
  icons: { headphones: { devices: [{ name: "Buds" }, { name: "Car" }] }, volume: { level: "high", muted: false }, network: { kind: "wired" } },
});
{
  const shown = ids.icons.children;
  assert.strictEqual(shown.map((b) => b.className).join("|"), "icon headphones|icon headphones|icon volume|icon wired|icon session", "no Bluetooth reading: no Bluetooth icon, headphones still");
  assert.strictEqual(shown.slice(0, 2).map((b) => b.attrs["data-tip"]).join("|"), "Buds|Car");
  assert.strictEqual(shown[0].attrs["aria-label"], "Buds");
  assert.ok(shown[0].innerHTML.startsWith("<svg "), "drawn");
  shown[1].listeners.click();
  assert.strictEqual(JSON.stringify(sent.at(-1)), JSON.stringify({ uuid: "B", open: "bluetooth" }));
  sent.length = 0;
}

// Bluetooth on or off: one glyph, faint while off (data-state "off", as
// keep awake), before the headphones, and a click opens its settings.
for (const on of [true, false]) {
  sandbox.tide.update({
    uuid: "B",
    workspaces: ws,
    title: "",
    icons: { bluetooth: { on }, headphones: { devices: [{ name: "Buds" }] }, network: { kind: "wired" } },
  });
  const shown = ids.icons.children;
  assert.strictEqual(shown.map((b) => b.className).join("|"), "icon bluetooth|icon headphones|icon wired|icon session");
  assert.strictEqual(shown[0].attrs["data-state"], on ? "on" : "off");
  assert.strictEqual(shown[0].attrs["data-tip"], on ? "Bluetooth on" : "Bluetooth off");
  assert.ok(shown[0].innerHTML.startsWith("<svg "), "drawn");
  shown[0].listeners.click();
  assert.strictEqual(JSON.stringify(sent.at(-1)), JSON.stringify({ uuid: "B", open: "bluetooth" }));
}
sent.length = 0;

// A wire, or no network at all.
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { network: { kind: "wired" } } });
assert.strictEqual(ids.icons.children[0].className, "icon wired");
ids.icons.children[0].listeners.click();
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { network: { kind: "none" } } });
assert.strictEqual(state(ids.icons.children[0]), "none");
assert.strictEqual(ids.icons.children[0].attrs["data-tip"], "No network");
assert.strictEqual(JSON.stringify(sent), JSON.stringify([{ uuid: "B", open: "network" }]));

// The title keeps 200 px or the clocks shrink to local time.
const { crowded } = vm.runInContext('modules["./bar.js"]', sandbox);
assert.strictEqual(crowded(1920, 300, 500), false);
assert.strictEqual(crowded(1200, 300, 500), true);

// A long title is held to the room between the chips and the right side,
// centered, so it can't run over either.
Object.assign(ids.bar, { clientWidth: 1200 });
// The logo and the chips together.
Object.assign(ids.left, { offsetWidth: 300 });
Object.assign(ids.right, { offsetWidth: 500 });
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "x".repeat(500), icons: {} });
const room = parseFloat(ids["title-text"].style.maxWidth);
assert.strictEqual(room, 1200 - 2 * 500 - 2 * 24);
assert.ok(1200 / 2 - room / 2 >= 300, "clear of the chips");
assert.ok(1200 / 2 + room / 2 <= 1200 - 500, "clear of the clocks and icons");
assert.ok(ids.clocks.classList.contains("compact"), "and the clocks shrank");

// Over a notch, chips that would reach the bar's clear middle hide behind a
// "+n" chip, the current one always showing.
const { notchChips, NOTCH_ROOM } = vm.runInContext('modules["./bar.js"]', sandbox);
const list = (...a) => JSON.parse(JSON.stringify(notchChips(...a)));
// Chips start at 40, each 60 wide with 4 after; the limit is 380, and the
// "+n" chip takes 40.
assert.deepStrictEqual(list(40, [60, 60, 60], 4, 380, 40), [0, 1, 2], "all fit");
assert.deepStrictEqual(list(40, [60, 60, 60, 60, 60, 60], 4, 380, 40), [0, 1, 2, 3], "four, then +2");
assert.deepStrictEqual(list(40, [60, 60, 60, 60, 60, 60], 4, 380, 40, 5), [0, 1, 2, 5], "the current one in place of the last");
assert.deepStrictEqual(list(40, [60, 60, 60, 60, 60, 60], 4, 380, 40, 2), [0, 1, 2, 3], "already shown");
assert.deepStrictEqual(list(40, [400, 60], 4, 380, 40, 1), [1], "a chip too wide for the room still leaves the current one");
assert.ok(NOTCH_ROOM >= 200, "at least the title's 200 px");

{
  const many = Array.from({ length: 6 }, (_, i) => ({ n: `w${i}`, current: i === 5, occupied: true }));
  Object.assign(ids.bar, { clientWidth: 1000 });
  ids.bar.rect = { left: 0, right: 1000, top: 0, bottom: 36, width: 1000, height: 36 };
  sandbox.tide.update({ uuid: "B", workspaces: many, title: "", icons: {}, notch: true });
  const chips = ids.workspaces.children;
  // limit = 1000/2 - NOTCH_ROOM/2 = 390: chips at 40, 104, 168, ... 60 wide.
  chips.forEach((c, i) => (c.rect = { left: 40 + 64 * i, right: 100 + 64 * i, top: 5, bottom: 31, width: 60, height: 26 }));
  sandbox.tick();
  const shown = ids.workspaces.children.filter((c) => c.style.display !== "none" && c.className !== "more-ws").map((c) => c.children[0].textContent);
  assert.deepStrictEqual(shown, ["w0", "w1", "w2", "w5"], "the current one stays");
  const more = ids.workspaces.children.at(-1);
  assert.strictEqual(more.className, "more-ws");
  assert.strictEqual(more.textContent, "+2");
  more.listeners.click();
  assert.strictEqual(JSON.stringify(sent.at(-1)), JSON.stringify({ uuid: "B", workspaces: true }));
  // Without a notch, every chip shows and there's no "+n".
  sandbox.tide.update({ uuid: "B", workspaces: many, title: "", icons: {}, notch: false });
  ids.workspaces.children.forEach((c, i) => (c.rect = { left: 40 + 64 * i, right: 100 + 64 * i, top: 5, bottom: 31, width: 60, height: 26 }));
  sandbox.tick();
  assert.ok(ids.workspaces.children.every((c) => c.style.display !== "none" && c.className !== "more-ws"));
  sent.length = 0;
  ids.bar.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
}

// Click targets: each item reaches the bar's top and bottom and halfway to
// each neighbor, a group's outer end reaches the bar's edge, and the room
// between the groups is left to the title.
const { hitInsets } = vm.runInContext('modules["./bar.js"]', sandbox);
const barBox = { left: 0, right: 400, top: 0, bottom: 36 };
const box = (left, right, top = 5, bottom = 31) => ({ left, right, top, bottom });
const lefts = [box(10, 40), box(44, 80), box(84, 120)];
// From the page's realm, so compared as plain data.
const hits = (...args) => JSON.parse(JSON.stringify(hitInsets(...args)));
const leftHits = hits(barBox, lefts, { start: true });
assert.deepStrictEqual(leftHits[0], { top: 5, bottom: 5, left: 10, right: 2 });
assert.deepStrictEqual(leftHits[1], { top: 5, bottom: 5, left: 2, right: 2 });
assert.deepStrictEqual(leftHits[2], { top: 5, bottom: 5, left: 2, right: 0 }, "stops short of the title's room");
// The clocks' line is shorter than the icons, and 14px from them.
const rights = [box(200, 300, 10, 26), box(314, 340), box(342, 390)];
const rightHits = hits(barBox, rights, { end: true });
assert.deepStrictEqual(rightHits[0], { top: 10, bottom: 10, left: 0, right: 7 });
assert.deepStrictEqual(rightHits[2], { top: 5, bottom: 5, left: 1, right: 10 });
// Every point from a group's outer edge to its last item's far side, top to
// bottom, is in exactly one item's target.
const owners = (items, hits, x, y) =>
  items.filter((r, i) => x >= r.left - hits[i].left && x < r.right + hits[i].right && y >= r.top - hits[i].top && y < r.bottom + hits[i].bottom).length;
for (const [items, hits, from, to] of [
  [lefts, leftHits, 0, 120],
  [rights, rightHits, 200, 400],
]) {
  for (let x = from; x < to; x += 0.5) {
    for (const y of [0, 4, 18, 35.5]) assert.strictEqual(owners(items, hits, x, y), 1, `one target at ${x},${y}`);
  }
}
assert.strictEqual(hits(barBox, [box(10, 50), box(45, 90)])[0].right, 0, "overlapping items reach no further");

// fit() gives each shown item its reach, as the --reach-* its ::before uses.
sandbox.tide.update({ uuid: "B", workspaces: [{ n: "in" }, { n: "web" }], title: "", icons: { mic: { muted: false } } });
ids.bar.rect = { ...barBox, width: 400, height: 36 };
const [inChip, webChip] = ids.workspaces.children;
inChip.rect = { ...box(10, 40), width: 30 };
webChip.rect = { ...box(44, 80), width: 36 };
ids.clocks.rect = { ...box(200, 300, 10, 26), width: 100 };
const micItem = ids.icons.children[0];
micItem.rect = { ...box(314, 390), width: 76 };
sandbox.tick();
const reachOf = (e) => ["top", "bottom", "left", "right"].map((k) => e.style[`--reach-${k}`]).join(" ");
assert.strictEqual(reachOf(inChip), "5px 5px 10px 2px");
assert.strictEqual(reachOf(webChip), "5px 5px 2px 0px");
assert.strictEqual(reachOf(ids.clocks), "10px 10px 0px 7px");
assert.strictEqual(reachOf(micItem), "5px 5px 7px 10px");
// The title's target is the free bar between the groups: here from the
// "web" chip's right edge to the clocks.
assert.strictEqual(reachOf(ids.title), "0px 0px 0px 0px", "no target with no title");
const { titleInsets } = vm.runInContext('modules["./bar.js"]', sandbox);
assert.strictEqual(JSON.stringify(titleInsets(barBox, box(150, 170, 10, 26), 80, 200)), '{"top":10,"bottom":10,"left":70,"right":30}');
sandbox.tide.update({ uuid: "B", workspaces: [{ n: "in" }, { n: "web" }], title: "Notes", icons: { mic: { muted: false } } });
const [inChip2, webChip2] = ids.workspaces.children;
inChip2.rect = { ...box(10, 40), width: 30 };
webChip2.rect = { ...box(44, 80), width: 36 };
ids.icons.children[0].rect = { ...box(314, 390), width: 76 };
ids.title.rect = { ...box(150, 170, 10, 26), width: 20 };
sandbox.tick();
assert.strictEqual(reachOf(ids.title), "10px 10px 70px 30px");

// tide's logo comes first: it reaches the bar's left edge, so the corner
// opens the switcher, and splits the gap to the first chip with it.
ids.logo.rect = { ...box(10, 36), width: 26 };
inChip2.rect = { ...box(40, 70), width: 30 };
webChip2.rect = { ...box(74, 110), width: 36 };
sandbox.tick();
assert.strictEqual(reachOf(ids.logo), "5px 5px 10px 2px");
assert.strictEqual(reachOf(inChip2), "5px 5px 2px 2px", "the first chip no longer reaches the edge");
ids.logo.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };

// The Apple logo comes first of all, as on a Mac's menu bar: it reaches the
// bar's left edge, and tide's logo then splits the gaps on both sides.
ids.apple.rect = { ...box(6, 30), width: 24 };
ids.logo.rect = { ...box(34, 60), width: 26 };
inChip2.rect = { ...box(64, 94), width: 30 };
webChip2.rect = { ...box(98, 134), width: 36 };
sandbox.tick();
assert.strictEqual(reachOf(ids.apple), "5px 5px 6px 2px");
assert.strictEqual(reachOf(ids.logo), "5px 5px 2px 2px", "tide's logo no longer reaches the edge");
sent.length = 0;
ids.apple.listeners.click();
assert.strictEqual(JSON.stringify(sent), JSON.stringify([{ uuid: "B", menubar: { x: ids.apple.getBoundingClientRect().left } }]),
  "a click opens the Apple menu under the logo");
assert.strictEqual(ids.apple.attrs?.["data-tip"] ?? "Apple menu", "Apple menu");
sent.length = 0;
ids.apple.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
ids.logo.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };

// Hover: tide says where the pointer is, and the target under it, its
// innermost, is marked .hover, one at a time, until the pointer leaves.
ids["title-text"].parent = ids.title;
sandbox.tide.update({
  uuid: "B",
  workspaces: [{ n: "in", apps: ["com.a", "com.b"], wins: [7] }],
  title: "Notes",
  app_icons: {},
  icons: { mic: { muted: false } },
});
const chip = ids.workspaces.children[0];
const [, winIcon, plainIcon] = chip.children;
const hoverOf = () =>
  [ids.apple, ids.logo, chip, winIcon, plainIcon, ids.title, ids.clocks, ids.icons.children[0]].filter((e) => e.classList.contains("hover"));
const point = (e) => {
  under = e;
  sandbox.tide.pointer(1, 1);
  return hoverOf();
};
assert.deepStrictEqual(point(winIcon), [winIcon], "a window icon, not its chip");
assert.deepStrictEqual(point(plainIcon), [chip], "an icon with no window to focus is the chip's");
assert.deepStrictEqual(point(chip.children[0]), [chip], "the chip's name");
sent.length = 0;
ids["title-text"].rect = { left: 150, right: 250, top: 10, bottom: 26, width: 100, height: 16 };
assert.deepStrictEqual(point(ids["title-text"]), [ids.title]);
// The page can't draw past its strip, so tide draws the uncut title's tip,
// centered on the title; once, however often the pointer moves.
point(ids["title-text"]);
assert.strictEqual(JSON.stringify(sent.filter((m) => m.tip)), JSON.stringify([{ uuid: "B", tip: { text: "Notes", x: 200 } }]));
assert.deepStrictEqual(point(ids.clocks), [ids.clocks]);
assert.strictEqual(JSON.stringify(sent.filter((m) => m.tip).pop()), JSON.stringify({ uuid: "B", tip: { text: "" } }), "gone off the title");
assert.deepStrictEqual(point(ids.icons.children[0]), [ids.icons.children[0]]);
assert.deepStrictEqual(point(ids.logo), [ids.logo], "tide's logo");
assert.deepStrictEqual(point(ids.apple), [ids.apple], "the Apple logo");
assert.deepStrictEqual(point(ids.bar), [], "the bar itself is no target");
point(chip);
sandbox.tide.pointer(null);
assert.deepStrictEqual(hoverOf(), [], "gone once the pointer leaves");
// A title changing under the pointer changes the tip: it's always uncut.
point(ids["title-text"]);
const long = "x".repeat(500);
sandbox.tide.update({ uuid: "B", workspaces: [{ n: "in" }], title: long, icons: {} });
assert.strictEqual(sent.filter((m) => m.tip).pop().tip.text, long);
// An empty title is no target, and has no tip.
sandbox.tide.update({ uuid: "B", workspaces: [{ n: "in" }], title: "", icons: {} });
assert.strictEqual(JSON.stringify(sent.filter((m) => m.tip).pop().tip), JSON.stringify({ text: "" }));
assert.deepStrictEqual(point(ids.title), []);
sandbox.tide.pointer(null);
// A status item's tip, a cut chip's whole name and the camera's tip take
// the title's path, centered on the item; a window icon and a whole name
// have none.
sandbox.tide.update({
  uuid: "B",
  workspaces: [{ n: "in", apps: ["com.a"], wins: [7] }, { n: "ABC-123 fix the login page" }],
  title: "",
  app_icons: {},
  icons: { camera: { in_use: true }, mic: { muted: true } },
});
const tipOf = () => JSON.stringify(sent.filter((m) => m.tip).pop().tip);
const [shortChip, cutChip] = ids.workspaces.children;
const [camera, mutedMicIcon] = ids.icons.children;
cutChip.children[0].parent = cutChip;
cutChip.rect = { left: 40, right: 140, top: 4, bottom: 32, width: 100, height: 28 };
point(cutChip.children[0]);
assert.strictEqual(tipOf(), JSON.stringify({ text: "ABC-123 fix the login page", x: 90 }));
mutedMicIcon.rect = { left: 1800, right: 1820, top: 10, bottom: 26, width: 20, height: 16 };
point(mutedMicIcon);
assert.strictEqual(tipOf(), JSON.stringify({ text: "Microphone muted", x: 1810 }));
point(shortChip);
assert.strictEqual(tipOf(), JSON.stringify({ text: "" }), "a whole name has no tip");
point(shortChip.children[1]);
assert.strictEqual(tipOf(), JSON.stringify({ text: "" }), "nor a window icon");
camera.parent = ids.icons;
camera.rect = { left: 1770, right: 1786, top: 10, bottom: 26, width: 16, height: 16 };
assert.deepStrictEqual(point(camera).length, 0, "the camera is no target");
assert.ok(!camera.classList.contains("hover"));
assert.strictEqual(tipOf(), JSON.stringify({ text: "Camera in use", x: 1778 }), "but has a tip");
sandbox.tide.pointer(null);
assert.strictEqual(tipOf(), JSON.stringify({ text: "" }), "gone once the pointer leaves");
under = null;

// Off, Wi-Fi shows its bars dimmed and no name.
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { wifi: { on: false, bars: 0 } } });
assert.strictEqual(state(ids.icons.children[0]), "off");
assert.strictEqual(ids.icons.children[0].attrs["data-tip"], "Wi-Fi off");
// Lua's JSON leaves out a field that's nil: a chip that's only occupied
// mustn't come out current or urgent.
sandbox.tide.update({ uuid: "B", workspaces: [{ n: 4, occupied: true }], title: "", icons: {} });
const only = ids.workspaces.children[0];
assert.ok(only.classList.contains("occupied"));
for (const k of ["current", "urgent"]) assert.ok(!only.classList.contains(k), `not ${k}`);
// Nor a microphone that's only said not to be muted come out muted.
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { mic: { muted: false } } });
const mic = ids.icons.children[0];
assert.strictEqual(mic.className, "icon mic");
assert.strictEqual(state(mic), "on", "not muted");
// Muted, the microphone is struck through; charging, the battery has its bolt.
sandbox.tide.update({
  uuid: "B",
  workspaces: ws,
  title: "",
  icons: { mic: { muted: true }, battery: { percent: 60, charging: true, text: "60%" } },
});
const [mutedMic, , charging] = ids.icons.children;
assert.strictEqual(state(mutedMic), "muted");
assert.ok(mutedMic.innerHTML.includes("M2.5 2.5l11 11"), "the slash");
assert.strictEqual(state(charging), "charging");
assert.strictEqual(charging.innerHTML.split("<svg ").length - 1, 2, "the bolt and the battery");
// Presenting, keep awake says so in words, and a click ends presenter mode
// rather than turning keep awake off alone.
sent.length = 0;
sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { awake: { on: true, presenting: true } } });
const presenting = ids.icons.children[0];
assert.strictEqual(presenting.className, "icon awake");
assert.strictEqual(state(presenting), "presenting");
assert.strictEqual(presenting.attrs["data-tip"], "Presenting: Do Not Disturb and keep awake");
assert.strictEqual(presenting.children[0].textContent, "Presenting");
presenting.listeners.click();
assert.strictEqual(JSON.stringify(sent.filter((m) => !m.goodClocks)), JSON.stringify([{ uuid: "B", toggle: "presenter" }]));

// A clock set bar: false stays in the dashboard's panel and out of the bar
// (tide SPEC.md §7.3); every other one is in it, then local time.
sandbox.tide.update({
  uuid: "B", workspaces: ws, title: "", icons: {},
  clockFiles: { local: JSON.stringify([{ zone: "Asia/Tokyo", label: "TYO" }, { zone: "America/Denver", label: "DEN", bar: false }]) },
});
{
  const labels = ids.clocks.children.map((li) => li.children[0].textContent);
  assert.strictEqual(labels.length, 2, `Tokyo and local: ${labels.join(", ")}`);
  assert.strictEqual(labels[0], "TYO");
  assert.ok(!labels.includes("DEN"), "Denver is out of the bar");
}
// A right-click on an item opens its settings page, by tide's map with
// tide's page ids (tide SPEC.md §7.1), and keeps WebKit's menu away;
// off every item it opens the Bar page.
{
  sandbox.tide.update({
    uuid: "B", workspaces: ws, title: "Doc", icons: {
      source: { name: "U.S.", label: "US" }, awake: { on: false }, mic: { muted: false }, bluetooth: { on: true },
      headphones: { devices: [{ name: "Buds" }] }, volume: { level: "high", text: "50%" }, wifi: { on: true, bars: 3, name: "home" },
      battery: { percent: 50, text: "50%" }, sysmon: { text: "5%" },
    },
  });
  const pages = (target) => {
    sent.length = 0;
    let stopped = false;
    ids.bar.listeners.contextmenu({ target, preventDefault: () => (stopped = true) });
    const m = sent.filter((x) => x.settings !== undefined);
    assert.strictEqual(stopped, m.length === 1, "WebKit's menu stays away only for an item");
    return m.length ? m[0].settings : null;
  };
  const named = Object.fromEntries(ids.icons.children.map((c) => [c.className.replace("icon ", ""), c]));
  const chipsNow = ids.workspaces.children;
  assert.strictEqual(pages(chipsNow[0]), "workspaces");
  assert.strictEqual(pages(ids.title), "floating");
  assert.strictEqual(pages(ids.clocks), "clocks");
  assert.strictEqual(pages(ids.logo), "bar", "the Bar page, as tide's logo");
  assert.strictEqual(pages(ids.apple), "bar");
  assert.strictEqual(pages(named.source), "keyboard");
  assert.strictEqual(pages(named.awake), "idle");
  assert.strictEqual(pages(named.mic), "sound");
  assert.strictEqual(pages(named.bluetooth), "bluetooth");
  assert.strictEqual(pages(named.headphones), "bluetooth");
  assert.strictEqual(pages(named.volume), "sound");
  assert.strictEqual(pages(named.wifi), "network");
  assert.strictEqual(pages(named.battery), "power");
  assert.strictEqual(pages(named.sysmon), "bar");
  assert.strictEqual(pages(named.session), "idle");
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", iconOrder: ["tray"], icons: {} });
  assert.strictEqual(pages(ids.icons.children[0]), "bar", "other apps' icons opens the Bar page");
  assert.strictEqual(pages(ids.bar), "bar", "the bar off every item opens the Bar page");
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: { awake: { on: true, presenting: true } } });
  assert.strictEqual(pages(ids.icons.children[0]), "muted", "Presenting opens Notifications, tide's muted page");
}
// The Bar page's layout (SPEC.md §8): each item's elements in its zone, in
// order, and an item that's off, or has nothing to show, unplaced.
{
  const { arrangement, centerAt, titleSpace } = vm.runInContext('modules["./bar.js"]', sandbox);
  const plain = (x) => JSON.parse(JSON.stringify(x));
  assert.deepStrictEqual(plain(arrangement(undefined)), {
    left: ["apple", "logo", "workspaces"],
    center: ["title"],
    right: ["icons-lead", "clocks", "icons"],
    unplaced: [],
  }, "unless set, the bar as it's always been");
  const custom = [
    { id: "icons", zone: "left", shown: true },
    { id: "workspaces", zone: "center", shown: true },
    { id: "title", zone: "left", shown: true },
    { id: "logo", zone: "right", shown: false },
  ];
  assert.deepStrictEqual(plain(arrangement(custom)), {
    left: ["icons-lead", "clocks", "icons", "title"],
    center: ["workspaces"],
    right: [],
    unplaced: ["apple", "logo"],
  }, "the Apple logo goes with tide's, the clocks with the icons");
  assert.deepStrictEqual(plain(arrangement(undefined, { has: { title: false } })).unplaced, ["title"], "no title takes no room");
  const notched = plain(arrangement(custom, { notch: true }));
  assert.deepStrictEqual(notched.center, ["workspaces"], "over a notch the center stays the center, either side of it");
  assert.deepStrictEqual(notched.left, ["icons-lead", "clocks", "icons"], "and a title at a side, under the notch, waits");
  assert.ok(notched.unplaced.includes("title"));
  const both = [{ id: "workspaces", zone: "center", shown: true }, { id: "title", zone: "center", shown: true }];
  assert.deepStrictEqual(plain(arrangement(both, { notch: true })).center, ["workspaces", "title"], "a centered title shows beside it");

  // The center zone's pivot (SPEC.md §8): the point on the bar's middle.
  const { pivotOf, afterNotch, titleShare, centerTitleRoom, NOTCH_ROOM: ROOM } = vm.runInContext('modules["./bar.js"]', sandbox);
  const box = (left, right) => ({ left, right });
  assert.strictEqual(pivotOf([box(0, 300)]), 150, "one item: its middle");
  assert.strictEqual(pivotOf([box(0, 300), box(308, 708)]), 304, "two: between them, so the first ends at the middle");
  assert.strictEqual(pivotOf([box(0, 100), box(108, 508), box(516, 616)]), 308, "three: the middle one's middle");
  assert.strictEqual(pivotOf([box(0, 300), box(300 + ROOM, 700 + ROOM)], true), 300 + ROOM / 2, "over a notch, its middle between the halves");
  assert.strictEqual(pivotOf([box(0, 300)], true), 300 + ROOM / 2, "one item ends at the notch");
  assert.strictEqual(afterNotch(2, true), 1, "the second half's first keeps the notch's room");
  assert.strictEqual(afterNotch(3, true), 2, "an odd middle one goes left of it");
  assert.strictEqual(afterNotch(1, true), -1);
  assert.strictEqual(afterNotch(2, false), -1, "without a notch, the usual gap");
  assert.strictEqual(titleShare(2, 1), 0, "second of two: all after the middle");
  assert.strictEqual(titleShare(1, 0), 0.5, "alone: centered");
  assert.strictEqual(titleShare(2, 0), 1);
  // The workspaces 300 then a title 500 on a 1200 bar, sides 100 and 200:
  // the title runs from the middle to 24 px short of the right side.
  const room2 = centerTitleRoom(1200, 100, 200, { pivot: 304, center: 808, title: 500, share: 0 });
  assert.strictEqual(room2, 1200 - 200 - 24 - (600 + 4));
  // A first half too wide to end at the middle moves the zone over, and
  // the title takes what's left: workspaces 700 then a title 400 on a 1280
  // bar, sides 40 and 200.
  const wide = centerTitleRoom(1280, 40, 200, { pivot: 704, center: 1108, title: 400, share: 0 });
  assert.strictEqual(wide, (1280 - 200 - 24) - (40 + 24) - 708);
  // Over a notch the zone never moves: a wide right side leaves the title
  // right of the notch no room, rather than sliding it under the notch.
  // A 1512 bar, sides 50 and 700, workspaces 200 then the title.
  assert.strictEqual(centerTitleRoom(1512, 50, 700, { pivot: 310, center: 420, title: 0, share: 0, fixed: true }), 0);
  assert.strictEqual(centerAt(1512, 50, 700, 420, 24, 310, true), 756 - 310, "the notch's gap stays on the notch");
  // Alone, as before: twice the room to the nearer side.
  assert.strictEqual(centerTitleRoom(1200, 300, 500, { pivot: 250, center: 500, title: 500, share: 0.5 }), 1200 - 2 * 500 - 2 * 24);
  // The pivot on the middle, as far as the sides let it.
  assert.strictEqual(centerAt(1200, 100, 200, 508, 24, 304), 600 - 304, "the first item ends at the middle");

  // The center zone on the bar's middle, moved over only as far as it must
  // to clear the sides, which keep their whole width.
  assert.strictEqual(centerAt(1000, 100, 100, 200), 400, "centered");
  const at = centerAt(1000, 100, 600, 200);
  assert.strictEqual(at, 176, "moved left of a side wider than its half");
  assert.ok(at + 200 + 24 <= 1000 - 600, "clear of the right side, whole");
  assert.ok(at >= 100 + 24, "and of the left");
  assert.strictEqual(centerAt(1000, 600, 100, 200), 624, "moved right of a wide left side");
  assert.strictEqual(centerAt(1000, 500, 500, 200), 524, "too crowded for both: clear of the left");
  // Centered, the title's room is titleRoom's, less the center's other
  // items; at a side, up to the center zone.
  assert.strictEqual(titleSpace(1200, { left: 300, right: 500 }, "center"), 1200 - 2 * 500 - 2 * 24);
  assert.strictEqual(titleSpace(1200, { left: 100, center: 92, right: 100 }, "center"), 1200 - 200 - 48 - 100);
  assert.strictEqual(titleSpace(1000, { left: 30, center: 200, right: 100 }, "left"), 400 - 24 - 38);
  assert.strictEqual(titleSpace(1000, { left: 30, center: 0, right: 100 }, "right"), 1000 - 108 - 24 - 30);
  assert.strictEqual(titleSpace(1000, { left: 30, right: 100 }, null), Infinity, "a title turned off needs no room");

  // tide's layout reaches the page: the elements move to their zones, and
  // the center zone moves over to clear a wide right side.
  const reset = () => {
    for (const id of ["left", "center", "right", "unplaced"]) ids[id].children.forEach((c) => (c.parent = undefined));
    for (const id of ["left", "center", "right", "unplaced"]) ids[id].children = [];
  };
  reset();
  Object.assign(ids.bar, { clientWidth: 1000 });
  Object.assign(ids.left, { offsetWidth: 30 });
  Object.assign(ids.right, { offsetWidth: 600 });
  Object.assign(ids.center, { offsetWidth: 200 });
  // The workspaces fill the center zone, so its pivot is their middle.
  ids.center.rect = { left: 400, right: 600, top: 5, bottom: 31, width: 200, height: 26 };
  ids.workspaces.rect = { left: 400, right: 600, top: 5, bottom: 31, width: 200, height: 26 };
  const layout = [
    { id: "logo", zone: "left", shown: true },
    { id: "workspaces", zone: "center", shown: true },
    { id: "title", zone: "left", shown: false },
    { id: "icons", zone: "right", shown: true },
  ];
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "Notes", icons: { mic: { muted: false } }, barLayout: layout });
  const kids = (id) => ids[id].children.map((c) => c.id);
  assert.deepStrictEqual(kids("left"), ["apple", "logo"]);
  assert.deepStrictEqual(kids("center"), ["workspaces"]);
  assert.deepStrictEqual(kids("right"), ["icons-lead", "clocks", "icons"]);
  assert.deepStrictEqual(kids("unplaced"), ["title"], "turned off");
  assert.ok(ids.workspaces.classList.contains("item-start") && ids.apple.classList.contains("item-start"));
  assert.ok(!ids.logo.classList.contains("item-start") && !ids.clocks.classList.contains("item-start"));
  assert.strictEqual(ids.center.style.left, "176px", "moved over, so the icons keep their width");
  assert.strictEqual(ids.center.style.transform, "none");
  assert.strictEqual(ids.clocks.classList.contains("compact"), false, "no title to make room for");
  // A narrower right side leaves it centered, as bar.html centers it.
  Object.assign(ids.right, { offsetWidth: 300 });
  sandbox.tick();
  assert.strictEqual(ids.center.style.left, "");
  assert.strictEqual(ids.center.style.transform, "");
  // The title at the left: its room runs to the center zone. The left
  // zone is 30 px of logos, 8 of gap and 100 of title.
  layout[2].shown = true;
  Object.assign(ids.left, { offsetWidth: 138 });
  Object.assign(ids.title, { offsetWidth: 100 });
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "Notes", icons: { mic: { muted: false } }, barLayout: layout });
  assert.deepStrictEqual(kids("left"), ["apple", "logo", "title"]);
  assert.ok(ids.title.classList.contains("item-start"));
  assert.strictEqual(parseFloat(ids["title-text"].style.maxWidth), titleSpace(1000, { left: 30, center: 200, right: 300 }, "left"));

  // Over a notch, workspaces at the right give way from their start, so the
  // zone stays clear of the notch: chips 60 wide, 4 apart, ending at 900,
  // the notch's right edge at 1000/2 + NOTCH_ROOM/2 = 610.
  const many = Array.from({ length: 6 }, (_, i) => ({ n: `w${i}`, current: i === 5, occupied: true }));
  const right = [
    { id: "workspaces", zone: "right", shown: true },
    { id: "icons", zone: "right", shown: true },
  ];
  ids.bar.rect = { left: 0, right: 1000, top: 0, bottom: 36, width: 1000, height: 36 };
  ids.clocks.rect = { left: 910, right: 990, top: 10, bottom: 26, width: 80, height: 16 };
  sandbox.tide.update({ uuid: "B", workspaces: many, title: "", icons: {}, notch: true, barLayout: right });
  assert.strictEqual(ids.workspaces.parent, ids.right);
  ids.workspaces.children.forEach((c, i) => (c.rect = { left: 520 + 64 * i, right: 580 + 64 * i, top: 5, bottom: 31, width: 60, height: 26 }));
  ids.workspaces.rect = { left: 520, right: 900, top: 5, bottom: 31, width: 380, height: 26 };
  sandbox.tick();
  const shownChips = ids.workspaces.children.filter((c) => c.style.display !== "none" && c.className !== "more-ws").map((c) => c.children[0].textContent);
  assert.deepStrictEqual(shownChips, ["w0", "w1", "w5"], "the current one stays");
  assert.strictEqual(ids.workspaces.children.at(-1).textContent, "+3");
  // Something before them in the zone takes from their room: 80 px more.
  ids.logo.rect = { left: 440, right: 470, top: 5, bottom: 31, width: 30, height: 26 };
  sandbox.tide.update({ uuid: "B", workspaces: many, title: "", icons: {}, notch: true, barLayout: [{ id: "logo", zone: "right", shown: true }, ...right] });
  ids.workspaces.children.forEach((c, i) => (c.rect = { left: 520 + 64 * i, right: 580 + 64 * i, top: 5, bottom: 31, width: 60, height: 26 }));
  sandbox.tick();
  assert.strictEqual(ids.workspaces.children.filter((c) => c.style.display !== "none" && c.className !== "more-ws").length, 2);

  // Back to the default, for anything after.
  ids.logo.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
  ids.workspaces.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
  ids.clocks.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
  ids.bar.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
  for (const id of ["left", "right", "center", "title"]) ids[id].offsetWidth = undefined;
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: {} });
  assert.deepStrictEqual(kids("left"), ["apple", "logo", "workspaces"]);
  sent.length = 0;
}
// The Bar page's colors (SPEC.md §8): each mode's as the bar's --bar-light
// and --bar-dark, and the bar's own again without one.
{
  const props = sandbox.document.documentElement.style.props;
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: {}, barColors: { darkBarColor: "#13303a" } });
  assert.deepStrictEqual(props, { "--bar-dark": "#13303a" });
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: {}, barColors: { lightBarColor: "#dfe3ee" } });
  assert.deepStrictEqual(props, { "--bar-light": "#dfe3ee" });
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "", icons: {} });
  assert.deepStrictEqual(props, {});
  sent.length = 0;
}
// A title the last fit held to 0 px still counts where it is: 500 px of
// centered workspaces on a 1200 bar, sides 50 and 400, leave it 172.
{
  const both = [
    { id: "logo", zone: "left", shown: true },
    { id: "workspaces", zone: "center", shown: true },
    { id: "title", zone: "center", shown: true },
    { id: "icons", zone: "right", shown: true },
  ];
  Object.assign(ids.bar, { clientWidth: 1200 });
  Object.assign(ids.left, { offsetWidth: 50 });
  Object.assign(ids.right, { offsetWidth: 400 });
  Object.assign(ids.center, { offsetWidth: 508 });
  ids.center.rect = { left: 96, right: 604, top: 5, bottom: 31, width: 508, height: 26 };
  ids.workspaces.rect = { left: 96, right: 596, top: 5, bottom: 31, width: 500, height: 26 };
  ids.title.rect = { left: 604, right: 604, top: 5, bottom: 31, width: 0, height: 26 };
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "Notes", icons: {}, notch: false, barLayout: both });
  assert.strictEqual(ids["title-text"].style.maxWidth, "172px");
}

// Over a notch, the workspaces and the title both centered sit either side
// of it: the title keeps the notch's room from the workspaces.
{
  const { NOTCH_ROOM: ROOM } = vm.runInContext('modules["./bar.js"]', sandbox);
  const both = [
    { id: "logo", zone: "left", shown: true },
    { id: "workspaces", zone: "center", shown: true },
    { id: "title", zone: "center", shown: true },
    { id: "icons", zone: "right", shown: true },
  ];
  ids.center.rect = { left: 300, right: 900, top: 5, bottom: 31, width: 600, height: 26 };
  ids.workspaces.rect = { left: 300, right: 500, top: 5, bottom: 31, width: 200, height: 26 };
  ids.title.rect = { left: 720, right: 900, top: 5, bottom: 31, width: 180, height: 26 };
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "Notes", icons: {}, notch: true, barLayout: both });
  assert.deepStrictEqual(ids.center.children.map((c) => c.id), ["workspaces", "title"], "the title shows beside the notch");
  assert.strictEqual(ids.title.style.marginLeft, `${ROOM}px`, "with the notch between");
  assert.strictEqual(ids.workspaces.style.marginLeft, "");
  // Without the notch, the usual gap.
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "Notes", icons: {}, notch: false, barLayout: both });
  assert.strictEqual(ids.title.style.marginLeft, "");
  // Moved to a side, an item leaves the notch's room behind.
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "Notes", icons: {}, notch: true, barLayout: both });
  assert.strictEqual(ids.title.style.marginLeft, `${ROOM}px`);
  const moved = both.map((e) => (e.id === "title" ? { ...e, zone: "right" } : e));
  sandbox.tide.update({ uuid: "B", workspaces: ws, title: "Notes", icons: {}, notch: false, barLayout: moved });
  assert.strictEqual(ids.title.parent, ids.right);
  assert.strictEqual(ids.title.style.marginLeft, "", "no 220 px gap at the side");
}
console.log("bar page: ok");
