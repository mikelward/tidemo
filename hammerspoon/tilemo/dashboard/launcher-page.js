// What tide calls on the dashboard launcher (SPEC.md §9.2), after tileco's
// page has started: tilemo.open(feed, scope) fills it and turns to a scope,
// tilemo.update(feed) brings in what arrived since, as browser tabs, and
// tilemo.press(scope) is a switcher key while it's open, which closes it on
// its own scope and otherwise turns to that one.

import { update } from "./launcher-chrome.js";

const chips = () => Array.from(document.querySelectorAll(".scopes button"));
const shown = () => chips().find((b) => b.getAttribute("aria-selected") === "true")?.dataset.scope ?? null;

// As a click on its chip does, so the page clears the selection and keeps
// the keyboard in the search field.
function turnTo(scope) {
  chips().find((b) => b.dataset.scope === scope)?.click();
}

window.tilemo = {
  open(next, scope) {
    update(next);
    turnTo(scope);
  },
  update,
  press(scope) {
    if (shown() === scope) window.close();
    else turnTo(scope);
  },
  scope: shown,
};
