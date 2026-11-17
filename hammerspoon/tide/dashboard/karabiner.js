// Karabiner-Elements' rules, turned on and off by tide (SPEC.md §15): the
// rule files in Karabiner's assets folder, which conf links there, and
// karabiner.json, where Karabiner keeps the rules it runs. Pure functions,
// run in JavaScriptCore (karabiner.lua), since only JSON.parse and
// JSON.stringify keep every other part of karabiner.json as it was. Turning a
// rule on copies it from its file into the selected profile, as Karabiner's
// own Enable button does; Karabiner reloads the file when it changes.

// `order` is conf's rules, top first, as each description starts
// (karabiner.lua's ORDER): Karabiner uses the first rule that matches a
// key, so some must sit above others. A rule not in it goes at the top, as
// Karabiner puts each rule it enables.

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

function rank(order, description) {
  return (Array.isArray(order) ? order : []).findIndex((prefix) => String(description).startsWith(prefix));
}

// A rule's name as the section shows it: its description up to the note in
// brackets, if any.
export function label(description) {
  const cut = description.indexOf(" (");
  return cut > 0 ? description.slice(0, cut) : description;
}

// The modifier swap of tide's PC keyboard type (SPEC.md §7.1), as
// Karabiner's key codes: each key as a PC keyboard sends it, in the Ctrl,
// Win and Alt spots, to the key it acts as, Command, Option and Control.
// The generic names are for a rule's modifiers.
export const SWAP = {
  left_control: "left_command", left_command: "left_option", left_option: "left_control",
  right_control: "right_command", right_command: "right_option", right_option: "right_control",
  control: "command", command: "option", option: "control",
};
// An Apple keyboard's own swap to the same keys by spot: its control sits
// where Ctrl does, its option where Win does and its command where Alt does.
export const APPLE_SWAP = {
  left_control: "left_command", left_option: "left_option", left_command: "left_control",
  right_control: "right_command", right_option: "right_option", right_command: "right_control",
};
// The key Caps Lock sends as tide's Compose (capslock.lua).
export const COMPOSE = { caps_lock: "f18" };

const swapName = (v) => (typeof v === "string" && Object.hasOwn(SWAP, v) ? SWAP[v] : v);

// `rule` as it reads once Karabiner swaps the modifiers itself: a rule file
// names the keys a PC keyboard sends, as macOS's mapping wants, where
// Karabiner runs its rules after its own swap. Each key code and modifier
// in it is swapped, in what the rule takes and what it sends: what it sent
// was swapped by macOS after it. A copy; the rest is as it was.
export function swapRule(rule) {
  const walk = (v) => {
    if (Array.isArray(v)) return v.map(walk);
    if (!isObject(v)) return v;
    const out = {};
    for (const [k, x] of Object.entries(v)) {
      if (k === "key_code") out[k] = swapName(x);
      else if (k === "modifiers" && (typeof x === "string" || Array.isArray(x))) out[k] = Array.isArray(x) ? x.map(swapName) : swapName(x);
      else if (k === "modifiers" && isObject(x)) {
        out[k] = {};
        for (const [kind, list] of Object.entries(x)) out[k][kind] = Array.isArray(list) ? list.map(swapName) : swapName(list);
      } else out[k] = walk(x);
    }
    return out;
  };
  return walk(rule);
}

// The rules in `files`, a list of { name, text }: each { file, title,
// description, label, rule }, and what's wrong with any file, by name.
// With `swap`, each rule as swapRule gives it, as Karabiner should run it.
export function assetRules(files, swap) {
  const rules = [];
  const errors = [];
  for (const f of Array.isArray(files) ? files : []) {
    let parsed;
    try {
      parsed = JSON.parse(f.text);
    } catch (e) {
      errors.push(`${f.name} isn't JSON: ${e.message}`);
      continue;
    }
    if (!isObject(parsed) || !Array.isArray(parsed.rules)) {
      errors.push(`${f.name} has no list of rules`);
      continue;
    }
    for (const rule of parsed.rules) {
      if (!isObject(rule) || typeof rule.description !== "string" || rule.description === "") {
        errors.push(`${f.name} has a rule with no description`);
        continue;
      }
      // Two files with one rule's name would be one switch for two rules.
      if (rules.some((r) => r.description === rule.description)) {
        errors.push(`${f.name} repeats the rule "${label(rule.description)}"`);
        continue;
      }
      rules.push({ file: f.name, title: typeof parsed.title === "string" ? parsed.title : "", description: rule.description, label: label(rule.description), rule: swap ? swapRule(rule) : rule });
    }
  }
  return { rules, errors };
}

// The selected profile's rules list in parsed karabiner.json `config`, made
// if it's missing, or an { error }.
function profileRules(config) {
  if (!isObject(config) || !Array.isArray(config.profiles) || config.profiles.length === 0) {
    return { error: "karabiner.json has no profiles" };
  }
  const profile = config.profiles.find((p) => isObject(p) && p.selected === true) ?? config.profiles[0];
  if (!isObject(profile)) {
    return { error: "karabiner.json's profile isn't an object" };
  }
  if (profile.complex_modifications === undefined) {
    profile.complex_modifications = {};
  }
  const cm = profile.complex_modifications;
  if (!isObject(cm)) {
    return { error: "karabiner.json's complex_modifications isn't an object" };
  }
  if (cm.rules === undefined) {
    cm.rules = [];
  }
  if (!Array.isArray(cm.rules)) {
    return { error: "karabiner.json's complex_modifications.rules isn't a list" };
  }
  return { list: cm.rules };
}

function parse(configText) {
  try {
    return { config: JSON.parse(configText) };
  } catch (e) {
    return { error: `karabiner.json isn't JSON: ${e.message}` };
  }
}

// A copy of `rule` as Karabiner keeps it once enabled. Karabiner may add
// keys of its own, such as "enabled", and writes each object's keys sorted,
// so a copy is the same rule when its manipulators match, key order aside;
// a list's order counts.
const copyOf = (rule) => JSON.parse(JSON.stringify(rule));
function canonical(v) {
  if (Array.isArray(v)) return v.map(canonical);
  if (!isObject(v)) return v;
  const out = {};
  for (const k of Object.keys(v).sort()) out[k] = canonical(v[k]);
  return out;
}
const same = (a, b) => JSON.stringify(canonical(a.manipulators ?? [])) === JSON.stringify(canonical(b.manipulators ?? []));

// Where the rule named `description` goes in `list`: above the first rule
// ranked below it in `order`, else below the last ranked above it, else at
// the top.
function slot(list, order, description) {
  const r = rank(order, description);
  if (r < 0) return 0;
  const below = list.findIndex((x) => isObject(x) && rank(order, x.description) > r);
  if (below >= 0) return below;
  for (let i = list.length - 1; i >= 0; i--) {
    const k = isObject(list[i]) ? rank(order, list[i].description) : -1;
    if (k >= 0 && k < r) return i + 1;
  }
  return 0;
}

function text(config) {
  return JSON.stringify(config, null, 4) + "\n";
}

// Each rule's state in karabiner.json: { description, on, stale }, stale
// when its copy there differs from its file, or an { error }. A copy
// Karabiner's window turned off ("enabled": false) is off.
export function ruleStates(configText, rules) {
  const p = parse(configText);
  if (p.error) return p;
  const r = profileRules(p.config);
  if (r.error) return r;
  return {
    states: rules.map((rule) => {
      const copy = r.list.find((x) => isObject(x) && x.description === rule.description);
      return {
        description: rule.description,
        on: copy !== undefined && copy.enabled !== false,
        stale: copy !== undefined && !same(copy, rule.rule),
      };
    }),
  };
}

// karabiner.json's text with the rule named `description` on or off, or an
// { error }. On, it's copied from its file into its place; off, every copy
// of it goes. The rest of the file stays as it was.
export function withRule(configText, rules, description, on, order) {
  const rule = rules.find((x) => x.description === description);
  if (!rule) return { error: `no rule "${label(String(description))}" in Karabiner's rule files` };
  const p = parse(configText);
  if (p.error) return p;
  const r = profileRules(p.config);
  if (r.error) return r;
  const list = r.list;
  for (let i = list.length - 1; i >= 0; i--) {
    if (isObject(list[i]) && list[i].description === description) list.splice(i, 1);
  }
  if (on) list.splice(slot(list, order, description), 0, copyOf(rule.rule));
  return { text: text(p.config) };
}

// karabiner.json's text with every copy of the rule named `description`
// taken out, whether or not a file has it: { text }, no text when there was
// none. Or an { error }.
export function withoutRule(configText, description) {
  const p = parse(configText);
  if (p.error) return p;
  const r = profileRules(p.config);
  if (r.error) return r;
  const n = r.list.length;
  for (let i = r.list.length - 1; i >= 0; i--) {
    if (isObject(r.list[i]) && r.list[i].description === description) r.list.splice(i, 1);
  }
  return r.list.length === n ? {} : { text: text(p.config) };
}

// karabiner.json brought up to date with the rule files: every copy that
// differs from its file replaced in place, and every rule not in `seen`
// that's off turned on, once, so a new rule from conf starts on and one you
// turn off stays off. { text, updated, enabled }: text is null when nothing
// changed, and the others name what did. Or an { error }.
// `superFile` is tide's Super rule's file, and `superPrefixes` what a tide
// rule's description starts with, old names included (karabiner.lua).
// `unread` is whether a rule file couldn't be read (assetRules' errors).
export function synced(configText, rules, seen, order, superFile, superPrefixes, unread) {
  const p = parse(configText);
  if (p.error) return p;
  const r = profileRules(p.config);
  if (r.error) return r;
  const list = r.list;
  const known = new Set(Array.isArray(seen) ? seen : []);
  const updated = [];
  const enabled = [];
  // tide's Super rule is one file, tide.json, which the installer or the
  // Keyboard page swaps for another key's (karabiner.lua's SUPER_CHOICES),
  // or the installer's --super none removes. An enabled tide rule with no
  // file is a key replaced or given up: left on, two keys would be Super,
  // Command+C included, or Super would stay off plain Option. It goes, and
  // the file's rule, if any, takes its place, on, though turned off before.
  const prefixes = Array.isArray(superPrefixes) ? superPrefixes : [];
  const isTide = (d) => prefixes.some((prefix) => String(d).startsWith(prefix));
  const superRule = rules.find((x) => x.file === superFile && isTide(x.description));
  const replaced = [];
  // Not while a file can't be read, such as one caught mid-write: its rule
  // would look gone, and once turned off, stay off.
  for (let i = unread ? -1 : list.length - 1; i >= 0; i--) {
    const d = isObject(list[i]) ? list[i].description : undefined;
    if (isTide(d) && !rules.some((x) => x.description === d)) {
      list.splice(i, 1);
      replaced.push(d);
    }
  }
  for (const rule of rules) {
    const i = list.findIndex((x) => isObject(x) && x.description === rule.description);
    if (i >= 0) {
      if (!same(list[i], rule.rule)) {
        list[i] = Object.assign({}, list[i], copyOf(rule.rule));
        updated.push(rule.description);
      }
    } else if (superRule && rule === superRule && replaced.length > 0) {
      list.splice(slot(list, order, rule.description), 0, copyOf(rule.rule));
    } else if (!known.has(rule.description)) {
      list.splice(slot(list, order, rule.description), 0, copyOf(rule.rule));
      enabled.push(rule.description);
    }
  }
  return {
    text: updated.length + enabled.length + replaced.length > 0 ? text(p.config) : null,
    updated, enabled, replaced: replaced.map(label), super: replaced.length > 0 && superRule ? superRule.label : undefined,
  };
}

// The selected profile in parsed karabiner.json `config`, or an { error }.
function selectedProfile(config) {
  if (!isObject(config) || !Array.isArray(config.profiles) || config.profiles.length === 0) {
    return { error: "karabiner.json has no profiles" };
  }
  const profile = config.profiles.find((p) => isObject(p) && p.selected === true) ?? config.profiles[0];
  return isObject(profile) ? { profile } : { error: "karabiner.json's profile isn't an object" };
}

// A key swap in a simple_modifications list: its from key, and its one to
// key, or undefined for anything else.
const fromKey = (e) => (isObject(e) && isObject(e.from) && typeof e.from.key_code === "string" ? e.from.key_code : undefined);
const toKey = (e) => (isObject(e) && Array.isArray(e.to) && e.to.length === 1 && isObject(e.to[0]) ? e.to[0].key_code : undefined);
const entry = (from, to) => ({ from: { key_code: from }, to: [{ key_code: to }] });

// `list` brought to `want` ({ from: to }), where each of tide's entries is
// `owned` as prefix + from: tide's entries no longer wanted, or wanted to
// another key, go; a wanted key not swapped yet is added and tide's. One
// swapped by you is yours and left alone. Gives the keys tide owns now.
function bring(list, want, owned, prefix) {
  const now = [];
  for (let i = list.length - 1; i >= 0; i--) {
    const from = fromKey(list[i]);
    if (from === undefined || !owned.has(prefix + from)) continue;
    if (Object.hasOwn(want, from) && toKey(list[i]) === want[from]) now.push(prefix + from);
    else list.splice(i, 1);
  }
  for (const [from, to] of Object.entries(want)) {
    if (list.some((e) => fromKey(e) === from)) continue;
    list.push(entry(from, to));
    now.push(prefix + from);
  }
  return now;
}

// Karabiner reads a missing vendor or product ID as 0, and writes a
// MacBook's built-in keyboard, which has neither, without them.
const idOf = (v) => (v === undefined ? 0 : v);
const deviceKey = (id) => `device:${idOf(id.vendor_id)}:${idOf(id.product_id)}:`;
const sameDevice = (d, id) =>
  isObject(d) && isObject(d.identifiers) && idOf(d.identifiers.vendor_id) === id.vendor_id &&
  idOf(d.identifiers.product_id) === id.product_id && d.identifiers.is_keyboard === true && d.identifiers.is_pointing_device !== true;

// karabiner.json's text with tide's key swaps (SPEC.md §7.1) brought to
// `want`: { swap, compose, apple }, the PC keyboard type's modifier swap,
// Caps Lock as Compose, and the Apple keyboards seen, each a { vendor_id,
// product_id }. Karabiner runs these before any rule, for every keyboard,
// one that comes later included. The swap goes in the profile's
// simple_modifications, for every keyboard, and each Apple keyboard gets
// its own in its device entry, which Karabiner uses first. Only the
// selected profile changes, the one Karabiner runs. `owned` is the entries
// tide added before, by profile name, so it takes out only those, and
// another profile's own swaps never read as tide's. A list is an older
// tide's, the selected profile's. A profile renamed since keeps them: with
// none under its name, it takes those of a name no profile has now, which
// `renamed` then names, so they're dropped. { text, profile, owned,
// renamed }: the profile's name and the entries tide owns there now, and
// no text when nothing changed. Or an { error }.
export function withSwaps(configText, want, owned) {
  const p = parse(configText);
  if (p.error) return p;
  const s = selectedProfile(p.config);
  if (s.error) return s;
  const profile = s.profile;
  const name = typeof profile.name === "string" ? profile.name : "";
  const before = JSON.stringify(p.config);
  let mine = [];
  const renamed = [];
  if (Array.isArray(owned)) mine = owned;
  else if (isObject(owned) && Array.isArray(owned[name])) mine = owned[name];
  else if (isObject(owned)) {
    const names = new Set(p.config.profiles.filter(isObject).map((x) => x.name));
    // A name gone may be a profile deleted, not this one renamed: only
    // entries this profile has exactly as tide sets them are taken, so
    // your own swap of the same key stays yours.
    const sets = (key) => {
      const m = /^profile:(.+)$/.exec(key);
      if (m) {
        const to = Object.hasOwn(SWAP, m[1]) && !m[1].match(/^(control|command|option)$/) ? SWAP[m[1]] : COMPOSE[m[1]];
        return Array.isArray(profile.simple_modifications) && profile.simple_modifications.some((e) => fromKey(e) === m[1] && toKey(e) === to);
      }
      const d = /^device:(\d+):(\d+):(.+)$/.exec(key);
      if (!d || !Object.hasOwn(APPLE_SWAP, d[3]) || !Array.isArray(profile.devices)) return false;
      const id = { vendor_id: Number(d[1]), product_id: Number(d[2]) };
      return profile.devices.some((x) => sameDevice(x, id) && Array.isArray(x.simple_modifications) &&
        x.simple_modifications.some((e) => fromKey(e) === d[3] && toKey(e) === APPLE_SWAP[d[3]]));
    };
    for (const [old, list] of Object.entries(owned)) {
      if (names.has(old) || !Array.isArray(list)) continue;
      mine = mine.concat(list.filter(sets));
      renamed.push(old);
    }
  }
  const had = new Set(mine);
  const w = isObject(want) ? want : {};
  if (profile.simple_modifications === undefined) profile.simple_modifications = [];
  if (!Array.isArray(profile.simple_modifications)) return { error: "karabiner.json's simple_modifications isn't a list" };
  const all = {};
  if (w.swap) {
    for (const k of ["left_control", "left_command", "left_option", "right_control", "right_command", "right_option"]) all[k] = SWAP[k];
  }
  if (w.compose) Object.assign(all, COMPOSE);
  const now = bring(profile.simple_modifications, all, had, "profile:");
  const apple = w.swap && Array.isArray(w.apple) ? w.apple.filter((id) => isObject(id) && Number.isInteger(id.vendor_id) && Number.isInteger(id.product_id)) : [];
  if (profile.devices === undefined) profile.devices = [];
  if (!Array.isArray(profile.devices)) return { error: "karabiner.json's devices isn't a list" };
  for (const id of apple) {
    if (!profile.devices.some((d) => sameDevice(d, id))) {
      profile.devices.push({ identifiers: { is_keyboard: true, product_id: id.product_id, vendor_id: id.vendor_id } });
    }
  }
  for (const d of profile.devices) {
    if (!isObject(d) || !isObject(d.identifiers)) continue;
    const id = d.identifiers;
    const wanted = apple.some((a) => sameDevice(d, a));
    const prefix = deviceKey(id);
    const mine = [...had].some((k) => k.startsWith(prefix));
    if (!wanted && !mine) continue;
    if (d.simple_modifications === undefined) d.simple_modifications = [];
    if (!Array.isArray(d.simple_modifications)) continue;
    now.push(...bring(d.simple_modifications, wanted ? APPLE_SWAP : {}, had, prefix));
  }
  const after = JSON.stringify(p.config);
  return { text: after === before ? undefined : text(p.config), profile: name, owned: now.sort(), renamed };
}

// The Apple keyboards in `karabiner_cli --list-connected-devices`'s list,
// parsed: each { vendor_id, product_id }, Karabiner's own keyboard left out.
// A MacBook's built-in keyboard, on the SPI bus, has no IDs: it's 0 and 0.
export function appleKeyboards(devices) {
  const out = [];
  for (const d of Array.isArray(devices) ? devices : []) {
    if (!isObject(d) || !isObject(d.device_identifiers)) continue;
    const id = d.device_identifiers;
    if (id.is_keyboard !== true || id.is_virtual_device === true) continue;
    if (d.is_apple !== true && d.is_built_in_keyboard !== true) continue;
    const vendor = idOf(id.vendor_id);
    const product = idOf(id.product_id);
    if (!Number.isInteger(vendor) || !Number.isInteger(product)) continue;
    if (out.some((k) => k.vendor_id === vendor && k.product_id === product)) continue;
    out.push({ vendor_id: vendor, product_id: product });
  }
  return out;
}
