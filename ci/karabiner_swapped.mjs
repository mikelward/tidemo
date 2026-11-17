// Writes each Karabiner rule file in a folder as tide copies it into
// karabiner.json once Karabiner swaps the modifiers (karabiner.js's
// swapRule), for ci/karabiner-lint.sh to check.
//
//   node karabiner_swapped.mjs KARABINER_MJS FROM_DIR TO_DIR

import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [source, from, to] = process.argv.slice(2);
const { swapRule } = await import(pathToFileURL(source).href);
for (const name of readdirSync(from).filter((n) => n.endsWith(".json"))) {
  const file = JSON.parse(readFileSync(join(from, name), "utf8"));
  file.rules = file.rules.map(swapRule);
  writeFileSync(join(to, name), JSON.stringify(file, null, 4) + "\n");
}
