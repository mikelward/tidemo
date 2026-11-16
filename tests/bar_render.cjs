// Lays out the bar's page (tests/bar_test.lua writes it to the file named on
// the command line) in Chromium, standing in for WebKit, and checks the
// layout's zones where only a real browser lays them out: a side wider
// than its half keeps its whole width, and the center zone moves over to
// clear it, so nothing overlaps; only the title gives way.
//
// Needs Playwright with Chromium, and skips with a note without it.

const assert = require("assert");
const path = require("path");

let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  console.log("SKIP the bar's zones in a browser: no Playwright");
  process.exit(0);
}

const workspaces = ["in", "design doc", "dotfiles", "planning", "standup", "recipes"].map((n, i) => ({ n, occupied: true, current: i === 1 }));
const icons = {
  source: { label: "DVO", name: "Dvorak" },
  awake: { on: true },
  mic: { muted: false },
  volume: { level: "mid", muted: false, text: "45%" },
  wifi: { on: true, bars: 3, name: "home" },
  network: { kind: "wifi" },
  battery: { percent: 84, charging: true, text: "84%" },
  sysmon: { text: "23%", tone: "normal" },
};
// Four clocks, so the right side is wide.
const clockFiles = [{ path: "clocks.json", text: JSON.stringify({ clocks: ["America/Los_Angeles", "America/New_York", "Asia/Tokyo"] }) }];

(async () => {
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({ viewport: { width: 1100, height: 36 }, timezoneId: "Europe/Dublin", locale: "en-US" });
    const tab = await context.newPage();
    const errors = [];
    tab.on("pageerror", (e) => errors.push(e.message));
    await tab.clock.setFixedTime(new Date("2026-10-26T09:30:00Z"));
    await tab.goto("file://" + path.resolve(process.argv[2]));
    // An element's box, and how far its content runs: the boxes of every
    // element in it (not their click targets, which reach past it).
    const box = (id) => tab.evaluate((i) => {
      const e = document.getElementById(i);
      const r = e.getBoundingClientRect();
      const inner = [...e.querySelectorAll("*")].map((c) => c.getBoundingClientRect()).filter((b) => b.width > 0);
      return {
        left: r.left,
        right: r.right,
        width: r.width,
        height: r.height,
        from: Math.min(r.left, ...inner.map((b) => b.left)),
        to: Math.max(r.right, ...inner.map((b) => b.right)),
        content: e.scrollWidth,
      };
    }, id);
    const update = (s) => tab.evaluate((st) => window.tide.update(st), s);

    // The workspaces centered, the title at the left, and a right side
    // wider than its half.
    await update({
      uuid: "A",
      workspaces,
      title: "A long document title that has to give way — Notes",
      icons,
      clockFiles,
      barLayout: [
        { id: "logo", zone: "left", shown: true },
        { id: "title", zone: "left", shown: true },
        { id: "workspaces", zone: "center", shown: true },
        { id: "icons", zone: "right", shown: true },
      ],
    });
    const left = await box("left");
    const center = await box("center");
    const right = await box("right");
    const title = await box("title-text");
    assert.ok(right.width > (1100 - center.width) / 2 - 24, `the right side is wider than its half (${right.width})`);
    assert.ok(right.from >= right.left - 0.5 && right.to <= right.right + 0.5,
      `the right side keeps its whole width (${right.from}..${right.to} in ${right.left}..${right.right})`);
    assert.ok((await box("clocks")).height <= 26, "its clocks on one line");
    assert.ok(Math.round(right.right) <= 1100, "and stays on the bar");
    assert.ok(center.to <= right.from, `the center clears the right side (${center.right} > ${right.left})`);
    assert.ok(center.from >= left.to, `and the left (${center.left} < ${left.right})`);
    assert.ok(center.width >= (await box("workspaces")).width, "every chip shows");
    assert.ok(title.content > title.width, "the title gives way, cut short");

    // The default layout: the title centered between the sides.
    await update({ uuid: "A", workspaces: workspaces.slice(0, 2), title: "Notes", icons: {}, clockFiles });
    const c = await box("center");
    assert.ok(Math.abs((c.left + c.right) / 2 - 550) < 1, `centered (${c.left}..${c.right})`);
    assert.deepStrictEqual(errors, []);
    await context.close();
  } finally {
    await browser.close();
  }
  console.log("bar zones: ok");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
