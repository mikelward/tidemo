// tide's bar (SPEC.md §8): tide's bar along the top of each display, with
// the workspaces left, the focused window's title in the middle, and the
// status icons and clocks right, unless the Bar page's Layout places them
// otherwise (state.barLayout). tide fills it with tide.update(state),
// says where the pointer is with tide.pointer(x, y), and hears back through the "tide" message handler: { uuid, show: n },
// { uuid, step: 1 or -1 }, { uuid, focus: window id } from an attention icon,
// { open: "battery" | "wifi" | "network" | "volume" | "bluetooth" | "sysmon" },
// { toggle: "mic" | "volume" | "awake" | "presenter" | "source" },
// { sound: { right } } from the speaker, its right edge,
// { volume: 1 or -1 }, { session: { x } } from the session icon at x,
// { settings: page } from a right-click, "" for the first page,
// { dashboard: true }, { switcher: true } from the logo, { menubar: { x } } from the Apple logo at x, { maximize: true }, { tip: { text, x } } while
// an item with a tip is hovered and { tip: { text: "" } } once none is, { clockErrors } naming a clocks file that's wrong, or
// { goodClocks }, the clocks to keep while one is.

import { renderClocks } from "./clockview.js";
import { DEFAULT_SETTINGS, nextSettings } from "./settings.js";
import { page as tidePage } from "./tide-barsettings.js";
import { layoutList } from "./tide-barlayout.js";

// Each bar item, by the selector its element matches and its name in
// tide's map (tide-barsettings.js), first match winning. The Apple logo
// opens what tide's logo does, the Bar page, and the camera what tide's
// sharing pill does, the Bar page too; the bar itself, off every item,
// is last.
const ITEMS = [
  ["#apple", "logo"],
  ["#logo", "logo"],
  ["#workspaces", "workspaces"],
  ["#title", "title"],
  ["#clocks", "clocks"],
  [".source", "keyboard"],
  [".awake", "keepawake"],
  [".camera", "sharing"],
  [".mic", "mic"],
  [".bluetooth", "bluetooth"],
  [".headphones", "bluetooth"],
  [".volume", "volume"],
  [".wifi, .wired", "network"],
  [".battery", "battery"],
  [".sysmon", "sysmon"],
  [".session", "session"],
  [".tray", "bar"],
  ["#bar", "bar"],
];
// tide's ids for tide's pages, where they differ.
const PAGE_IDS = { notifications: "muted" };

// The settings page a right-click on `target` opens (tide §7.1): tide's
// id for it, "" for the first page, or null off the bar.
export function settingsPage(target) {
  for (const [selector, item] of ITEMS) {
    const e = target?.closest?.(selector);
    if (!e) continue;
    const name = item === "keepawake" && e.getAttribute("data-state") === "presenting" ? "presenter" : item;
    const id = tidePage(name);
    return PAGE_IDS[id] ?? id;
  }
  return null;
}

// Every message names this bar's display, so tide acts there.
const send = (msg) => window.webkit?.messageHandlers?.tide?.postMessage({ uuid, ...msg });

// tide's rule (tide §7.3): below this the clocks shrink to local time.
export const MIN_TITLE = 200;

// The room the centered title has between the two sides: the bar's width
// less twice the wider side, and a gap each side.
export function titleRoom(width, left, right, gap = 24) {
  return width - 2 * Math.max(left, right) - 2 * gap;
}

// The bar's layout (SPEC.md §8): each item in a zone, left, center or
// right, as tide's barLayout (tide-barlayout.js), and the elements of
// bar.html each item moves. The Apple logo goes with tide's logo. The
// clocks are an item of their own, as on tide for Linux.
const ELEMENTS = {
  logo: ["apple", "logo"],
  workspaces: ["workspaces"],
  title: ["title"],
  icons: ["icons"],
  clocks: ["clocks"],
};
// The gap between two items in a zone, as tide's (bar.html's .item-start).
export const ITEM_GAP = 8;

// Where each of bar.html's elements goes, as { left, center, right,
// unplaced }, each a list of element ids in order, from a stored barLayout:
// an item that's off, or that `has` says has nothing to show (has[id] ===
// false), is unplaced, so it takes no room. Over a notch the center zone
// sits either side of it (pivotOf), and the title shows only there: at a
// side it would run under the notch.
export function arrangement(stored, { notch = false, has = {} } = {}) {
  const out = { left: [], center: [], right: [], unplaced: [] };
  for (const z of ["left", "center", "right"]) {
    for (const e of layoutList(stored)) {
      if (e.zone !== z) continue;
      const hidden = !e.shown || has[e.id] === false || (notch && e.id === "title" && z !== "center");
      const zone = hidden ? "unplaced" : z;
      out[zone].push(...ELEMENTS[e.id]);
    }
  }
  return out;
}

// The zone the title goes in, unless it's turned off (null).
function titleZone(stored) {
  const e = layoutList(stored).find((i) => i.id === "title");
  return e.shown ? e.zone : null;
}

// Where the center zone starts on a bar `width` wide, holding `center` px,
// between sides `left` and `right` px wide (from the bar's edges): its
// `pivot` (pivotOf; its middle unless given) on the bar's middle, moved over
// only as far as it must to keep `gap` from each side, since the sides
// never shrink. Too crowded to clear both, it keeps clear of the left.
// Over a notch (`fixed`) it never moves: the notch doesn't, and what would
// reach a side gives way instead (fitNotch, centerTitleRoom).
export function centerAt(width, left, right, center, gap = 24, pivot = center / 2, fixed = false) {
  if (fixed) return width / 2 - pivot;
  const lo = left > 0 ? left + gap : gap;
  const hi = width - (right > 0 ? right + gap : gap);
  return Math.max(lo, Math.min(width / 2 - pivot, hi - center));
}

// Where the center zone's items split either side of the bar's middle: the
// index of the first one after it. With an odd number and no notch, the
// middle one is on the middle itself, so it's in neither half; over a
// notch it goes left of it, as Middle of menu bar draws the workspaces.
function splitAt(n, notch) {
  return notch ? Math.ceil(n / 2) : Math.floor(n / 2);
}

// The point in the center zone that goes on the bar's middle (SPEC.md §8),
// from its items' boxes ({ left, right }, from the zone's start, in
// order): with an odd number, the middle one's middle; with an even
// number, halfway across the gap between the halves, so the first ends at
// the middle and the second starts there. Over a notch, the gap is the
// notch (the second half's first item keeps NOTCH_ROOM from the first
// half), and with nothing after it the first half ends at its left edge.
export function pivotOf(boxes, notch = false) {
  const n = boxes.length;
  if (n === 0) return 0;
  const s = splitAt(n, notch);
  if (!notch && n % 2 === 1) return (boxes[s].left + boxes[s].right) / 2;
  if (s >= n) return boxes[n - 1].right + NOTCH_ROOM / 2;
  return (boxes[s - 1].right + boxes[s].left) / 2;
}

// The index of the center item that starts the second half over a notch,
// so it keeps NOTCH_ROOM from the first, or -1 with none.
export function afterNotch(n, notch) {
  const s = splitAt(n, notch);
  return notch && s < n ? s : -1;
}

// How much of the title's width falls before the center zone's pivot when
// it's the `i`th of `n` center items: all of it in the first half, half as
// the middle item, none in the second half.
export function titleShare(n, i, notch = false) {
  const s = splitAt(n, notch);
  if (!notch && n % 2 === 1 && i === s) return 0.5;
  return i < s ? 1 : 0;
}

// The room a centered title has, as tide's barlayout.mjs gives it: it grows
// only until the zone reaches a side, so the pivot stays on the middle.
// `pivot` and `center` are the zone's now, with the title `title` px wide,
// `share` of it before the pivot (titleShare).
// Over a notch (`fixed`), the zone never moves, so the title gets only what
// its half leaves, none if that's nothing.
export function centerTitleRoom(width, left, right, { pivot, center, title, share, fixed = false }, gap = 24) {
  const lo = left > 0 ? left + gap : gap;
  const hi = width - (right > 0 ? right + gap : gap);
  const p0 = pivot - share * title;
  const c0 = center - title;
  // Moved over even with no title, the pivot can't stay put: the title
  // takes what's left between the sides.
  if (!fixed && (width / 2 - p0 < lo || width / 2 - p0 + c0 > hi)) return hi - lo - c0;
  const room = [];
  if (share > 0) room.push((width / 2 - p0 - lo) / share);
  if (share < 1) room.push((hi - width / 2 + p0 - c0) / (1 - share));
  return fixed ? Math.max(0, Math.min(...room)) : Math.min(...room);
}

// The room the title has in `zone`, from each zone's width without it
// ({ left, center, right }): centered, the bar's width less twice the wider
// side, a gap each side and the center's other items (titleRoom), so it
// stays centered; at a side, from its zone's other items to the center
// zone, or to the other side.
export function titleSpace(width, { left = 0, center = 0, right = 0 }, zone, gap = 24, pivot = center / 2) {
  if (zone === "center") return titleRoom(width, left, right, gap) - (center > 0 ? center + ITEM_GAP : 0);
  if (zone === "left") {
    const end = center > 0 ? centerAt(width, left, right, center, gap, pivot) : width - right;
    return end - gap - (left > 0 ? left + ITEM_GAP : 0);
  }
  if (zone === "right") {
    const start = center > 0 ? centerAt(width, left, right, center, gap, pivot) + center : left;
    return width - (right > 0 ? right + ITEM_GAP : 0) - gap - start;
  }
  return Infinity;
}

// Whether the title would get narrower than MIN_TITLE with every clock
// showing.
export function crowded(width, left, right, gap = 24) {
  return titleRoom(width, left, right, gap) < MIN_TITLE;
}

// Over a notch (SPEC.md §8) the bar keeps this much of its middle clear, a
// little more than the widest MacBook notch *(unverified per model)*.
export const NOTCH_ROOM = 220;

// Which workspace chips show left of a notch, as indexes in order: those
// that fit before `limit` (the x no chip may pass), with room for a "+n"
// chip `more` wide when not all do. The chips start at `start`, each
// `widths[i]` wide with `gap` after it. Chip `keep` (the current one, or
// -1) always shows, in place of the last ones that would.
export function notchChips(start, widths, gap, limit, more, keep = -1) {
  const end = (ids) => ids.reduce((x, i) => x + widths[i] + gap, start);
  const all = widths.map((_, i) => i);
  if (end(all) - gap <= limit) return all;
  const shown = [];
  for (const i of all) {
    if (end([...shown, i]) + more > limit) break;
    shown.push(i);
  }
  if (keep >= 0 && !shown.includes(keep)) {
    while (shown.length > 0 && end([...shown, keep]) + more > limit) shown.pop();
    shown.push(keep);
  }
  return shown;
}

// Each item's click target, as how far it reaches past its own box on each
// side: to the bar's top and bottom, and halfway across the gap to each
// neighbor, so a click between two items goes to the nearer one rather than
// nowhere. A group's outer end (`start` on the left, `end` on the right)
// reaches the bar's edge; its inner end stops at the item, leaving the room
// between the groups to the title. Boxes are { left, right, top, bottom },
// left to right.
export function hitInsets(bar, items, { start = false, end = false } = {}) {
  const half = (a, b) => Math.max(0, (b - a) / 2);
  return items.map((r, i) => {
    const prev = items[i - 1];
    const next = items[i + 1];
    return {
      top: Math.max(0, r.top - bar.top),
      bottom: Math.max(0, bar.bottom - r.bottom),
      left: prev ? half(prev.right, r.left) : start ? Math.max(0, r.left - bar.left) : 0,
      right: next ? half(r.right, next.left) : end ? Math.max(0, bar.right - r.right) : 0,
    };
  });
}

// The title's target: the free bar between the two groups, from the left
// group's last item (`leftEnd`, its right edge) to the right group's first
// (`rightStart`), to the bar's top and bottom.
export function titleInsets(bar, title, leftEnd, rightStart) {
  return {
    top: Math.max(0, title.top - bar.top),
    bottom: Math.max(0, bar.bottom - title.bottom),
    left: Math.max(0, title.left - leftEnd),
    right: Math.max(0, rightStart - title.right),
  };
}

// What a click at an element reaches, innermost first: a chip's window
// icon, then the logo, a chip, the title, the clocks or a status item.
const TARGET = "nav > button .app.win, #apple, #logo, nav > button, #title, #clocks, #icons > button.icon";

// A trackpad sends many small scrolls; one step is this much of them.
const STEP = 50;


let uuid = null;
let scrolled = 0;

function el(tag, className, text) {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}

// A long name is cut at 16 characters with an ellipsis (SPEC.md §8, a guess
// to confirm); the chip's tip has it whole.
const NAME_MAX = 16;
function shortName(name) {
  const chars = Array.from(String(name));
  return chars.length > NAME_MAX ? chars.slice(0, NAME_MAX).join("") + "…" : chars.join("");
}

// Each chip is its name, then the app icon of each window there wanting
// attention (tide sends at most five, their ids in `wins`, and how many
// more as `more`), which a click focuses (SPEC.md §8). An app with no icon
// shows as a blank square of the same size, so the count still reads.
function renderWorkspaces(nav, workspaces, appIcons = {}) {
  nav.replaceChildren();
  // Every workspace tide sends has a chip: the empty ones go once
  // they're left, and "in" stays (SPEC.md §6.1).
  for (const w of workspaces) {
    const b = el("button");
    b.type = "button";
    const short = shortName(w.n);
    // Only a cut name has a tip: a whole one would say it again.
    if (short !== String(w.n)) b.setAttribute("data-tip", String(w.n));
    b.append(el("span", "n", short));
    const wins = w.wins || [];
    (w.apps || []).forEach((app, i) => {
      const url = appIcons[app];
      let icon;
      if (url) {
        icon = el("img", "app");
        icon.src = url;
        icon.alt = "";
      } else {
        icon = el("span", "app none");
      }
      if (wins[i] !== undefined) {
        icon.className += " win";
        icon.addEventListener("click", (e) => {
          // The window, not the chip's workspace.
          e.stopPropagation();
          send({ focus: wins[i] });
        });
      }
      b.append(icon);
    });
    if (w.more > 0) b.append(el("span", "more", `+${w.more}`));
    // A field tide left out is false: toggle(name, undefined) would flip it.
    for (const k of ["current", "occupied", "urgent"]) b.classList.toggle(k, !!w[k]);
    b.addEventListener("click", () => send({ show: w.n }));
    nav.append(b);
  }
}

// The status icons: 16 px line drawings in the text color, drawn here, so
// they follow the bar's light and dark colors. Each item's state is also in
// its data-state, for the styles and the tests.
const svg = (body, width = 16) =>
  `<svg viewBox="0 0 ${width} 16" width="${width}" height="16" fill="none" stroke="currentColor" ` +
  `stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

const SLASH = `<path d="M2.5 2.5l11 11"/>`;
const PATHS = {
  awake: `<path d="M3 6h7.5v3.5a3 3 0 0 1-3 3h-1.5a3 3 0 0 1-3-3z"/><path d="M10.5 7h1a1.75 1.75 0 0 1 0 3.5h-1"/><path d="M5.5 2.5v1.5M8 2.5v1.5"/>`,
  mic: `<rect x="6" y="2" width="4" height="7.5" rx="2"/><path d="M3.5 8a4.5 4.5 0 0 0 9 0"/><path d="M8 12.5v2"/>`,
  speaker: `<path d="M2.5 6h2.5l3.5-3v10l-3.5-3h-2.5z"/>`,
  waves: [`<path d="M10.5 6.5a2 2 0 0 1 0 3"/>`, `<path d="M12 5a4 4 0 0 1 0 6"/>`, `<path d="M13.5 3.5a6.4 6.4 0 0 1 0 9"/>`],
  speakerOff: `<path d="M11 6.5l3 3M14 6.5l-3 3"/>`,
  bluetooth: `<path d="M4.5 5l7 6-3.5 3V2l3.5 3-7 6"/>`,
  headphones: `<path d="M2.5 11V8.5a5.5 5.5 0 0 1 11 0V11"/><rect x="2" y="9.5" width="3" height="4.5" rx="1"/><rect x="11" y="9.5" width="3" height="4.5" rx="1"/>`,
  camera: `<rect x="1.5" y="4.5" width="9" height="7" rx="1.5"/><path d="M10.5 7.2l4-2.2v6l-4-2.2"/>`,
  arcs: [`<path d="M6 10.6a2.8 2.8 0 0 1 4 0"/>`, `<path d="M4 8.5a5.7 5.7 0 0 1 8 0"/>`, `<path d="M2 6.4a8.5 8.5 0 0 1 12 0"/>`],
  dot: `<path d="M8 12.8v.01"/>`,
  wired: `<path d="M5.5 2v3M10.5 2v3"/><path d="M3.5 5h9v2.5a4.5 4.5 0 0 1-9 0z"/><path d="M8 12v2.5"/>`,
  bolt: `<path d="M5.5 2.5l-3 6h3l-1 5 4-7h-3z"/>`,
  // A power symbol, as tide's system-shutdown-symbolic.
  power: `<path d="M8 2v5.5"/><path d="M4.6 4.3a5 5 0 1 0 6.8 0"/>`,
  // A processor, as tide's cpu-symbolic: a chip with pins on each side.
  // Three dots in a row, for other apps' icons, as a menu's More.
  tray: `<path d="M3.5 8v.01M8 8v.01M12.5 8v.01" stroke-width="2.25"/>`,
  cpu: `<rect x="4" y="4" width="8" height="8" rx="1.5"/><rect x="6.5" y="6.5" width="3" height="3" rx="0.5"/>` +
    `<path d="M6 1.5v2M10 1.5v2M6 12.5v2M10 12.5v2M1.5 6h2M1.5 10h2M12.5 6h2M12.5 10h2"/>`,
};

const VOLUME = { mute: 0, low: 1, mid: 2, high: 3 };

// Wi-Fi's dot and arcs, `lit` of three at full strength and the rest faint.
const arcs = (lit) =>
  PATHS.dot + PATHS.arcs.map((a, i) => (i < lit ? a : a.replace("<path ", '<path opacity="0.3" '))).join("");

// A status item: a button sending `msg` when clicked, drawn with `art`.
function icon(name, label, msg, art, state) {
  const b = el("button", `icon ${name}`);
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.setAttribute("data-tip", label);
  b.setAttribute("data-state", state);
  b.innerHTML = art;
  if (msg) b.addEventListener("click", () => send(msg));
  return b;
}

// A VPN's lock, as tide's (tide §7.4): bottom right, on a disc of the
// bar's color so it reads over the icon.
const LOCK =
  `<circle cx="12.5" cy="12.5" r="3.9" fill="var(--bar)" stroke="none"/>` +
  `<rect x="10.4" y="12" width="4.2" height="3" rx="0.6" fill="currentColor" stroke="none"/>` +
  `<path d="M11.3 12v-0.9a1.2 1.2 0 0 1 2.4 0V12" stroke-width="1.1"/>`;

// Wi-Fi with its bars, a wire, or neither, with the lock while a VPN is up.
function network(icons) {
  const kind = icons.network?.kind ?? (icons.wifi?.on ? "wifi" : "none");
  const vpn = !!icons.network?.vpn;
  const w = icons.wifi;
  // The lock goes last, over the icon; the tip says so after the rest.
  const drawn = (art, label, msg, state) => {
    const b = icon(kind === "wired" ? "wired" : "wifi", vpn ? `${label}, VPN on` : label, msg, svg(art + (vpn ? LOCK : "")), state);
    if (vpn) b.setAttribute("data-vpn", "on");
    return b;
  };
  if (kind === "wifi" && w) {
    return drawn(arcs(w.bars), w.name || "Wi-Fi", { open: "wifi" }, `bars-${w.bars}`);
  }
  if (kind === "wired") {
    return drawn(PATHS.wired, "Wired network", { open: "network" }, "wired");
  }
  const off = w && !w.on;
  return drawn(arcs(0) + SLASH, off ? "Wi-Fi off" : "No network", { open: w ? "wifi" : "network" }, off ? "off" : "none");
}

// The battery: an outline with a bar as full as it is, and a bolt beside it
// while charging.
function battery(p) {
  const fill = Math.max(0, Math.min(100, Math.round(p.percent))) * 0.08;
  const body =
    `<rect x="1.5" y="4.5" width="11" height="7" rx="1.5"/><path d="M14.5 7v2"/>` +
    `<rect x="3" y="6" width="${fill.toFixed(2)}" height="4" rx="0.5" fill="currentColor" stroke="none"/>`;
  const state = p.charging ? "charging" : p.percent <= 20 ? "low" : "normal";
  const b = icon("battery", p.tip || `Battery ${p.text}`, { open: "battery" }, (p.charging ? svg(PATHS.bolt, 10) : "") + svg(body), state);
  b.append(el("span", "text", p.text));
  return b;
}

// Each status icon's drawing, by its id in the Bar page's list (bar.lua's
// ICONS): its elements, none when it has nothing to show.
const DRAW = {
  source(icons) {
    if (!icons.source) return [];
    const b = icon("source", icons.source.name, { toggle: "source" }, "", "label");
    b.textContent = icons.source.label;
    return [b];
  },
  awake(icons) {
    if (icons.awake?.presenting) {
      // Presenter mode (SPEC.md §10): the cup with a word, and a click ends it.
      const b = icon("awake", "Presenting: Do Not Disturb and keep awake", { toggle: "presenter" }, svg(PATHS.awake), "presenting");
      b.append(el("span", "text", "Presenting"));
      return [b];
    }
    if (!icons.awake) return [];
    // Its tip says what it's doing, in the sign's words (presenter.lua's
    // awake_sign), as tide's hover does.
    const on = !!icons.awake.on;
    return [icon("awake", on ? "Keeping awake" : "Not keeping awake", { toggle: "awake" }, svg(PATHS.awake), on ? "on" : "off")];
  },
  camera(icons) {
    if (!icons.camera) return [];
    const c = el("span", "icon camera");
    c.setAttribute("data-tip", "Camera in use");
    c.setAttribute("data-state", "in-use");
    c.innerHTML = svg(PATHS.camera);
    return [c];
  },
  mic(icons) {
    if (!icons.mic) return [];
    const muted = !!icons.mic.muted;
    const art = svg(PATHS.mic + (muted ? SLASH : ""));
    return [icon("mic", muted ? "Microphone muted" : "Microphone", { toggle: "mic" }, art, muted ? "muted" : "on")];
  },
  // Bluetooth: one glyph, faint while off, as tide's; a click opens
  // Bluetooth settings.
  bluetooth(icons) {
    if (!icons.bluetooth) return [];
    const on = !!icons.bluetooth.on;
    return [icon("bluetooth", on ? "Bluetooth on" : "Bluetooth off", { open: "bluetooth" }, svg(PATHS.bluetooth), on ? "on" : "off")];
  },
  // Each connected Bluetooth audio device, named on hover; a click opens
  // Bluetooth settings.
  headphones(icons) {
    return (icons.headphones?.devices ?? []).map((d) => icon("headphones", d.name, { open: "bluetooth" }, svg(PATHS.headphones), "connected"));
  },
  volume(icons) {
    if (!icons.volume) return [];
    // Four levels with mute, then the level as a %. An output with no
    // volume control (fixed) draws the full speaker with no %, and can't
    // be scrolled.
    const v = icons.volume;
    const waves = v.level === "fixed" ? 3 : (VOLUME[v.level] ?? 0);
    const art = svg(PATHS.speaker + (waves === 0 ? PATHS.speakerOff : PATHS.waves.slice(0, waves).join("")));
    const b = icon("volume", v.tip || (v.muted ? "Sound muted" : "Sound"), null, art, v.level);
    // A click opens the volume popover under it, as tide's; tide places
    // it, so it sends where the speaker's right edge is.
    b.addEventListener("click", () => {
      const r = b.getBoundingClientRect();
      send({ sound: { right: Math.round(r.right) } });
    });
    if (v.text) b.append(el("span", "text", v.text));
    if (!v.fixed) {
      let wheeled = 0;
      b.addEventListener("wheel", (e) => {
        e.preventDefault();
        wheeled += e.deltaY;
        if (Math.abs(wheeled) < STEP) return;
        // Scrolling up, away from you, turns it up.
        send({ volume: wheeled < 0 ? 1 : -1 });
        wheeled = 0;
      });
    }
    return [b];
  },
  network: (icons) => [network(icons)],
  battery: (icons) => (icons.battery ? [battery(icons.battery)] : []),
  // The system monitor: CPU %, colored when hot, throttling or short of
  // memory; a click opens Activity Monitor.
  sysmon(icons) {
    if (!icons.sysmon) return [];
    const s = icons.sysmon;
    const b = icon("sysmon", s.tip || "CPU", { open: "sysmon" }, svg(PATHS.cpu), s.tone || "normal");
    b.append(el("span", "text", s.text));
    return [b];
  },
  // Other apps' icons, which macOS keeps in its menu bar: a click hides
  // the bars so the menu bar shows (bar.lua's Show Menu Bar).
  tray: () => [icon("tray", "Other apps' icons", { tray: true }, svg(PATHS.tray), "normal")],
  // The session menu, last unless moved, as tide's: tide shows macOS's own
  // menu under the icon, so it sends where the icon is.
  session() {
    const session = icon("session", "Lock, log out or power off", null, svg(PATHS.power), "normal");
    session.addEventListener("click", () => {
      const r = session.getBoundingClientRect();
      send({ session: { x: Math.round(r.left) } });
    });
    return [session];
  },
};

// The bar's order unless the Bar page chose another: every icon but the
// tray.
export const ICON_ORDER = ["source", "awake", "camera", "mic", "bluetooth", "headphones", "volume", "network", "battery", "sysmon", "session"];

// The order tide sent: the bar's own when it sent none, and none when it
// sent an empty list, which hs.json.encode writes as {}.
function iconOrder(sent) {
  if (sent === undefined || sent === null) return ICON_ORDER;
  return Array.isArray(sent) ? sent : [];
}

// The icons in `order`, the ids tide sends (bar.shown_icons); one it
// doesn't know is skipped, as is "clock" from a tide that still sends it.
function renderIcons(box, icons, order = ICON_ORDER) {
  box.replaceChildren();
  for (const id of order) {
    if (!Object.hasOwn(DRAW, id)) continue;
    box.append(...DRAW[id](icons));
  }
}

// Sets each item's reach (hitInsets) as --reach-* for its ::before, which
// bar.html draws as its click target. Hidden items take no room.
const SIDES = ["top", "bottom", "left", "right"];
const setReach = (e, h) => {
  for (const side of SIDES) e.style.setProperty(`--reach-${side}`, `${h ? h[side] : 0}px`);
};

// Returns the shown items' boxes.
function reach(bar, items, opts) {
  const shown = items.filter((e) => e.getBoundingClientRect().width > 0);
  for (const e of items) if (!shown.includes(e)) setReach(e, null);
  const boxes = shown.map((e) => e.getBoundingClientRect());
  hitInsets(bar, boxes, opts).forEach((h, i) => setReach(shown[i], h));
  return boxes;
}

// Every clock if the title keeps MIN_TITLE, else local time alone. Then the
// title is held to the room left, so a long one ends in an ellipsis rather
// than running over the chips or the clocks.
// The "+n" chip for workspaces hidden by the notch; a click opens the
// switcher's Workspaces tab, which lists them all.
const moreChip = el("button", "more-ws");
moreChip.type = "button";
moreChip.addEventListener("click", () => send({ workspaces: true }));

// Over a notch, hides the chips that would reach it (notchChips), behind
// moreChip.
function fitNotch() {
  const nav = document.getElementById("workspaces");
  if (moreChip.parentNode) moreChip.remove();
  const chips = [...nav.children];
  for (const c of chips) c.style.display = "";
  if (!notch || chips.length === 0) return;
  const bar = document.getElementById("bar").getBoundingClientRect();
  const width = document.getElementById("bar").clientWidth;
  const boxes = chips.map((c) => c.getBoundingClientRect());
  // Unmeasured, as before the page lays out: nothing to hide yet.
  if (!(width > 0) || boxes.some((b) => !(b.width > 0))) return;
  const gap = boxes.length > 1 ? Math.max(0, boxes[1].left - boxes[0].right) : 4;
  // Room for "+99", measured as tide's chips are sized.
  const more = 40;
  const keep = chips.findIndex((c) => c.classList.contains("current"));
  // The rest of the chips' zone stays clear of the notch too: what follows
  // them on the left, or what comes before them on the right, where they
  // end at the bar's right edge and give way from their start.
  const others = [...nav.parentNode.children].filter((e) => e !== nav && e.getBoundingClientRect().width > 0);
  const navBox = nav.getBoundingClientRect();
  let start;
  let limit;
  if (nav.parentNode.id === "center") {
    // Centered, the chips sit beside the notch, in its half: they may reach
    // back to the side zone, less the rest of their half.
    const items = centerItems();
    const i = items.findIndex((e) => e.id === "workspaces");
    const s = afterNotch(items.length, notch) < 0 ? items.length : afterNotch(items.length, notch);
    const half = i < s ? items.slice(0, s) : items.slice(s);
    const rest = half.filter((e) => e.id !== "workspaces").reduce((sum, e) => sum + (e.right - e.left) + ITEM_GAP, 0);
    const side = document.getElementById(i < s ? "left" : "right").offsetWidth || 0;
    start = 0;
    limit = width / 2 - NOTCH_ROOM / 2 - (side > 0 ? side + 24 : 24) - rest;
  } else if (nav.parentNode.id === "right") {
    const before = others.filter((e) => e.getBoundingClientRect().right <= navBox.left);
    const lead = before.length > 0 ? navBox.left - before[0].getBoundingClientRect().left : 0;
    start = 0;
    limit = boxes[boxes.length - 1].right - bar.left - (width / 2 + NOTCH_ROOM / 2) - lead;
  } else {
    const after = others.filter((e) => e.getBoundingClientRect().left >= navBox.right);
    const tail = after.length > 0 ? after[after.length - 1].getBoundingClientRect().right - navBox.right : 0;
    start = boxes[0].left - bar.left;
    limit = width / 2 - NOTCH_ROOM / 2 - tail;
  }
  const shown = new Set(notchChips(start, boxes.map((b) => b.width), gap, limit, more, keep));
  if (shown.size === chips.length) return;
  chips.forEach((c, i) => {
    if (!shown.has(i)) c.style.display = "none";
  });
  const hidden = chips.length - shown.size;
  moreChip.textContent = `+${hidden}`;
  moreChip.setAttribute("aria-label", `${hidden} more workspaces`);
  moreChip.setAttribute("data-tip", `${hidden} more: open the switcher's Workspaces`);
  nav.append(moreChip);
}

// Each zone's width without the title, { left, center, right }: the
// title's own width, and its gap from the zone's other items, taken off.
function zoneWidths() {
  const title = document.getElementById("title");
  const out = {};
  for (const z of ["left", "center", "right"]) {
    const zone = document.getElementById(z);
    let w = zone.offsetWidth || 0;
    if (title.parentNode === zone) w = Math.max(0, w - (title.offsetWidth || 0) - (zone.children.length > 1 ? ITEM_GAP : 0));
    out[z] = w;
  }
  return out;
}

// The clickable elements of an element of bar.html, in order: a group's
// own (the chips, the status icons), or itself.
function targets(e) {
  if (e.id === "workspaces" || e.id === "icons") return [...e.children];
  return e.id === "title" ? [] : [e];
}

// The center zone's items, in order, each with its elements' box from the
// zone's start: { id, els, left, right }.
function centerItems() {
  const center = document.getElementById("center");
  const at = center.getBoundingClientRect().left;
  const out = [];
  for (const e of layoutList(layout)) {
    if (e.zone !== "center") continue;
    const els = ELEMENTS[e.id].map((id) => document.getElementById(id)).filter((el) => el.parentNode === center);
    // A placed title counts even held to 0 px by the last fit, so its room
    // is worked out where it is, not as if it were alone.
    const boxes = els.map((el) => el.getBoundingClientRect()).filter((b) => b.width > 0 || (e.id === "title" && b.right > 0));
    if (boxes.length === 0) continue;
    out.push({
      id: e.id,
      els,
      left: Math.min(...boxes.map((b) => b.left)) - at,
      right: Math.max(...boxes.map((b) => b.right)) - at,
    });
  }
  return out;
}

// Over a notch, the center item after it keeps NOTCH_ROOM from the one
// before (afterNotch); every other one has its .item-start gap.
function spaceNotch() {
  // Every item's, not only the center's: one moved to a side keeps none.
  for (const ids of Object.values(ELEMENTS)) {
    for (const id of ids) document.getElementById(id).style.marginLeft = "";
  }
  const items = centerItems();
  const i = afterNotch(items.length, notch);
  if (i >= 0) items[i].els[0].style.marginLeft = `${NOTCH_ROOM}px`;
}

// The room the title has where it goes (titleSpace), the center zone's
// from its items as they are (centerTitleRoom).
function titleRoomNow(width, widths, zone) {
  if (zone !== "center") return titleSpace(width, widths, zone, 24, pivotOf(centerItems(), notch));
  const items = centerItems();
  const i = items.findIndex((e) => e.id === "title");
  // Not measured yet: the zone as if the title were its only item.
  if (i < 0) return titleSpace(width, widths, zone);
  const center = document.getElementById("center").offsetWidth || 0;
  return centerTitleRoom(width, widths.left, widths.right, {
    pivot: pivotOf(items, notch),
    center,
    title: items[i].right - items[i].left,
    share: titleShare(items.length, i, notch),
    fixed: notch,
  });
}

function fit() {
  spaceNotch();
  fitNotch();
  const clocks = document.getElementById("clocks");
  clocks.classList.toggle("compact", false);
  const width = document.getElementById("bar").clientWidth;
  // The title keeps MIN_TITLE where it goes, unless it's turned off.
  const zone = titleZone(layout);
  let widths = zoneWidths();
  const tight = zone !== null && titleRoomNow(width, widths, zone) < MIN_TITLE;
  clocks.classList.toggle("compact", tight);
  if (tight) widths = zoneWidths();
  const room = titleRoomNow(width, widths, zone);
  // Unmeasured, as before the page lays out, leaves the title as it is.
  if (Number.isFinite(room)) document.getElementById("title-text").style.maxWidth = `${Math.max(0, Math.floor(room))}px`;
  // The center zone's pivot on the bar's middle, or moved over to clear
  // the sides (centerAt); left to bar.html's centering where that's the same.
  const center = document.getElementById("center");
  const left = document.getElementById("left").offsetWidth || 0;
  const right = document.getElementById("right").offsetWidth || 0;
  const cw = center.offsetWidth || 0;
  const at = centerAt(width, left, right, cw, 24, pivotOf(centerItems(), notch), notch && centerItems().length > 0);
  const moved = width > 0 && Math.abs(at - (width - cw) / 2) >= 0.5;
  center.style.left = moved ? `${Math.round(at)}px` : "";
  center.style.transform = moved ? "none" : "";
  const bar = document.getElementById("bar").getBoundingClientRect();
  // Each zone's items, split at the title, are a group: the left zone's
  // first group reaches the bar's left edge (so the corner opens the Apple
  // menu, as on a Mac) and the right zone's last its right edge; the rest
  // stop at their items, leaving the room between them to the title.
  const title = document.getElementById("title");
  const runs = [];
  for (const z of ["left", "center", "right"]) {
    let run = { items: [] };
    runs.push(run);
    for (const e of document.getElementById(z).children) {
      if (e === title) {
        run = { items: [] };
        runs.push(run);
      } else {
        run.items.push(...targets(e));
      }
    }
  }
  for (const run of runs) reach(bar, run.items, { start: run === runs[0], end: run === runs[runs.length - 1] });
  // An empty title has no target: there's no window there to maximize.
  const box = title.getBoundingClientRect();
  if (title.parentNode?.id === "unplaced" || !(box.width > 0)) {
    setReach(title, null);
    return;
  }
  // The free bar beside the title: from the last item left of it to the
  // first right of it.
  let leftEnd = bar.left;
  let rightStart = bar.right;
  for (const run of runs) {
    for (const e of run.items) {
      const r = e.getBoundingClientRect();
      if (!(r.width > 0)) continue;
      if (r.right <= box.left) leftEnd = Math.max(leftEnd, r.right);
      if (r.left >= box.right) rightStart = Math.min(rightStart, r.left);
    }
  }
  setReach(title, titleInsets(bar, box, leftEnd, rightStart));
}

// Where the pointer is on this bar, from tide, or null off it; kept so a
// redraw marks the new target.
let pointerAt = null;
let hovered = null;

function markHover() {
  hovered?.classList.toggle("hover", false);
  hovered = null;
  const target = pointerAt && document.elementFromPoint(pointerAt.x, pointerAt.y)?.closest(TARGET);
  if (target && !(target.id === "title" && !document.getElementById("title-text").textContent)) {
    target.classList.toggle("hover", true);
    hovered = target;
  }
  // The camera is no target, since a click there does nothing, but has a tip.
  showTip(hovered ?? (pointerAt && document.elementFromPoint(pointerAt.x, pointerAt.y)?.closest("#icons > .icon")));
}

// While the title, or an item with a tip, is hovered, tide shows the
// uncut title, or the tip, below the bar, centered on it at `x`: the page
// can't draw past its own strip, and WebKit shows no `title` attribute's
// tooltip in a window that's never key (SPEC.md §8). Sent only when it
// changes, since the pointer moves often.
let tipSent = JSON.stringify({ text: "" });
function showTip(target) {
  const at = target?.id === "title" ? document.getElementById("title-text") : target;
  const text = target?.id === "title" ? at.textContent : (target?.getAttribute("data-tip") ?? "");
  const box = at?.getBoundingClientRect();
  const tip = text ? { text, x: Math.round((box.left + box.right) / 2) } : { text: "" };
  const json = JSON.stringify(tip);
  if (json === tipSent) return;
  tipSent = json;
  send({ tip });
}

let settings = DEFAULT_SETTINGS;
let goodSent = null;

function tick() {
  renderClocks(document.getElementById("clocks"), new Date(), false, settings);
  fit();
}

// Whether this bar is over a notch (SPEC.md §8), from tide.
let notch = false;
// The Bar page's Light background and Dark background, as tide sent them
// (barColors: { lightBarColor, darkBarColor }, tide for Linux's names):
// launcher.css's --bar reads them as --bar-light and --bar-dark, and is the
// bar's own without them.
export function colorBar(colors, root = document.documentElement) {
  for (const [mode, key] of [["light", "lightBarColor"], ["dark", "darkBarColor"]]) {
    if (colors?.[key]) root.style.setProperty(`--bar-${mode}`, colors[key]);
    else root.style.removeProperty(`--bar-${mode}`);
  }
}

// The Bar page's layout, as tide sent it (barLayout): the default unless
// it sent one.
let layout = undefined;

// Puts each of bar.html's elements in its zone, in order (arrangement()),
// moving only what isn't there already. The first element of each item
// after the first in its zone is .item-start, which spaces it from the one
// before.
function arrange(where) {
  for (const z of ["left", "center", "right", "unplaced"]) {
    const zone = document.getElementById(z);
    const want = where[z].map((id) => document.getElementById(id));
    const have = [...zone.children];
    if (want.length !== have.length || want.some((e, i) => e !== have[i])) {
      for (const e of want) {
        e.remove();
        zone.append(e);
      }
    }
  }
  const firsts = new Set(Object.values(ELEMENTS).map((ids) => ids[0]));
  for (const ids of Object.values(ELEMENTS)) {
    for (const id of ids) document.getElementById(id).classList.toggle("item-start", firsts.has(id));
  }
}

window.tide = {
  update(state) {
    uuid = state.uuid;
    notch = !!state.notch;
    renderWorkspaces(document.getElementById("workspaces"), state.workspaces, state.app_icons || {});
    document.getElementById("title-text").textContent = state.title;
    const order = iconOrder(state.iconOrder);
    renderIcons(document.getElementById("icons"), state.icons, order);
    // An item with nothing to show takes no room: the title with no window
    // focused here, the status icons with every one off.
    layout = state.barLayout ?? undefined;
    colorBar(state.barColors);
    arrange(arrangement(layout, { notch, has: { title: !!state.title, icons: order.length > 0 } }));
    const loaded = nextSettings(state, settings);
    settings = loaded.settings;
    if (loaded.errors.length > 0) send({ clockErrors: loaded.errors });
    const good = JSON.stringify(settings.tideClocks);
    if (good !== goodSent) {
      goodSent = good;
      send({ goodClocks: settings.tideClocks });
    }
    tick();
    markHover();
  },
  // tide says where the pointer is, in this page's coordinates, or null
  // once it's left the bar.
  pointer(x, y) {
    pointerAt = x === null || x === undefined ? null : { x, y };
    markHover();
  },
};

document.getElementById("workspaces").addEventListener("wheel", (e) => {
  e.preventDefault();
  scrolled += e.deltaY;
  if (Math.abs(scrolled) < STEP) return;
  send({ step: scrolled > 0 ? 1 : -1 });
  scrolled = 0;
});

// Double-clicking the title, or the free bar around it, maximizes the
// focused window, as on a Mac's title bar; tide acts only if that window is
// on this bar's display. A double click on an item is that item's.
document.getElementById("bar").addEventListener("dblclick", (e) => {
  if (["bar", "title", "title-text"].includes(e.target.id)) send({ maximize: true });
});

// tide's logo opens the switcher on Launch, or closes it, as Super+Space
// does (SPEC.md §8).
document.getElementById("logo").addEventListener("click", () => send({ switcher: true }));
// A right-click on an item opens its settings page, and anywhere else on
// the bar the Bar page, in place of WebKit's menu.
document.getElementById("bar").addEventListener("contextmenu", (e) => {
  const id = settingsPage(e.target);
  if (id === null) return;
  e.preventDefault();
  send({ settings: id });
});
// The Apple menu, which tide opens for real (bar_hs.lua).
// It opens under the logo, wherever the layout put it.
const apple = document.getElementById("apple");
apple.addEventListener("click", () => send({ menubar: { x: Math.round(apple.getBoundingClientRect().left) } }));

// The clocks open the dashboard, with its clock panel.
document.getElementById("clocks").addEventListener("click", () => send({ dashboard: true }));

setInterval(tick, 30000);
