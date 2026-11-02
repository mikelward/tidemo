// What tide calls on the dashboard launcher (SPEC.md §9.2), after tileco's
// page has started: tilemo.open(feed, scope) fills it, clears the search
// and turns to a scope, tilemo.update(feed) brings in what arrived since, as
// browser tabs, tilemo.press(scope) is a switcher key while it's open, which
// closes it on its own scope and otherwise turns to that one, and
// tilemo.turn(scope) turns to a scope as Tab does, for CI's smoke test.

import { update } from "./launcher-chrome.js";

const chips = () => Array.from(document.querySelectorAll(".scopes button"));
const shown = () => chips().find((b) => b.getAttribute("aria-selected") === "true")?.dataset.scope ?? null;

// As a click on its chip does, so the page clears the selection and keeps
// the keyboard in the search field.
function turnTo(scope) {
  chips().find((b) => b.dataset.scope === scope)?.click();
}

// When the page last heard Esc, by the clock, for CI's smoke test.
document.addEventListener(
  "keydown",
  (e) => {
    if (e.key === "Escape") window.tilemo.esc = Date.now();
  },
  true,
);

window.tilemo = {
  // The page is kept between opens, hidden, so each starts with an empty
  // search as a new page would.
  open(next, scope) {
    // When the page heard it, when this had run, and when the page had
    // painted after it, by the clock, for CI's smoke test: a hidden page
    // can be slow to wake. update() starts an asynchronous refresh, which
    // the second frame comes after.
    const heard = Date.now();
    const query = document.getElementById("query");
    if (query) query.value = "";
    update(next);
    turnTo(scope);
    const opened = { heard, ran: Date.now(), visibility: document.visibilityState };
    window.tilemo.opened = opened;
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        opened.painted = Date.now();
      }),
    );
  },
  update,
  press(scope) {
    if (shown() === scope) window.close();
    else turnTo(scope);
  },
  turn: turnTo,
  scope: shown,
};
