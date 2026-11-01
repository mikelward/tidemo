// The dashboard launcher's stand-in for tileco's launcher.js (SPEC.md §9.2):
// tileco's own, with two lists that are chromeOS's swapped for tide's. The
// Actions scope's rows are the switcher's Actions tab, and the settings
// sections are Tide Settings' (launcher.lua's SETTINGS_SECTIONS), from the
// feed. The rest is tileco's matching, ranking and footer, unchanged.

import {
  footerKeys as tilecoFooterKeys,
  footerText as tilecoFooterText,
  items as tilecoItems,
  limitFor as tilecoLimitFor,
  logoTapped as tilecoLogoTapped,
  nextScope as tilecoNextScope,
  opening as tilecoOpening,
  rank as tilecoRank,
  SCOPE_ORDER as TILECO_SCOPE_ORDER,
  SECTION_KEY as TILECO_SECTION_KEY,
  workspaceRows as tilecoWorkspaceRows,
} from "./launcher.js";
import { feed } from "./launcher-chrome.js";

export const footerKeys = tilecoFooterKeys;
export const footerText = tilecoFooterText;
export const items = tilecoItems;
export const limitFor = tilecoLimitFor;
export const logoTapped = tilecoLogoTapped;
export const nextScope = tilecoNextScope;
export const opening = tilecoOpening;
export const rank = tilecoRank;
export const SCOPE_ORDER = TILECO_SCOPE_ORDER;
export const SECTION_KEY = TILECO_SECTION_KEY;
export const workspaceRows = tilecoWorkspaceRows;

export function actions() {
  return feed.actions.map((a) => ({ ...a }));
}

export function settingsSections() {
  return feed.sections.map((s) => ({ ...s }));
}
