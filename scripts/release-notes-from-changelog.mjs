#!/usr/bin/env node
// Draft .github/release-notes/<version>.md from the website changelog entry.
//
// releases.ts is the authored source for what a release says: its English
// highlights become the "What's new" bullets here, and the same entry later
// feeds the localized appcast descriptions (release-notes-localized.mjs) and
// the site's changelog page. Generating this file keeps GitHub, Sparkle, and
// the website in agreement instead of asking whoever ships the release to
// write the same text twice.
//
// Usage: release-notes-from-changelog.mjs VERSION [--force]
//
// Refuses to overwrite an existing notes file unless --force is passed, so a
// hand-edited paragraph survives a rerun.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const args = process.argv.slice(2);
const version = args.find((arg) => !arg.startsWith("--"));
const force = args.includes("--force");
if (!version) {
  console.error("usage: release-notes-from-changelog.mjs VERSION [--force]");
  process.exit(2);
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// Same data-only-module trick as release-notes-localized.mjs: drop the type
// declaration and the export keyword, then evaluate the array literal in an
// empty sandbox.
const source = readFileSync(join(root, "website/src/data/releases.ts"), "utf8");
const script = source
  .replace(/export type Release = \{[\s\S]*?\n\};\n/, "")
  .replace(/export const releases\s*:\s*readonly Release\[\]\s*=/, "releases =");
const sandbox = {};
vm.runInNewContext(script, sandbox);
const release = (sandbox.releases ?? []).find((entry) => entry.version === version);
if (!release) {
  console.error(`no ${version} entry in website/src/data/releases.ts — write it first`);
  process.exit(1);
}
const en = release.highlights?.en ?? [];
if (en.length === 0) {
  console.error(`the ${version} entry has no English highlights`);
  process.exit(1);
}

const setupNote =
  release.setupNoteEn ??
  "No setup is required after updating. Existing watchlists, positions, and trade history are untouched.";

const notes = [
  `Pulse ${version}`,
  "",
  "What's new:",
  ...en.map((line) => `- ${line}`),
  "",
  setupNote,
  "",
  `For first-time installation, download Pulse-${version}.dmg and drag Pulse to Applications. The zip asset is used by Sparkle automatic updates.`,
  "",
].join("\n");

const out = join(root, ".github/release-notes", `${version}.md`);
if (existsSync(out) && !force) {
  console.error(`${out} already exists — refusing to overwrite (pass --force)`);
  process.exit(1);
}
writeFileSync(out, notes);
console.log(`wrote ${out}`);
