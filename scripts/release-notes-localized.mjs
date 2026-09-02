#!/usr/bin/env node
// Inline localized release notes for the Sparkle alert, from the website's changelog data.
//
// Usage: release-notes-localized.mjs VERSION APPCAST_XML
//
// Rewrites the VERSION item in APPCAST_XML so it carries one
// <description xml:lang="…"> per language (en, zh, ja, ko) built from
// website/src/data/releases.ts, and drops any <sparkle:releaseNotesLink>
// elements on that item. Sparkle picks the description matching the user's
// language and falls back to the first listed one, so "en" is written first.
//
// The notes are embedded rather than linked on purpose: GitHub serves release
// assets as application/octet-stream, and Sparkle hands that MIME type to the
// web view untouched, so a linked HTML page never renders in the alert.
//
// Exits 0 without touching the appcast when the version is absent from the
// website data; the English fragment generate_appcast embedded from the GitHub
// release notes then stays as the only description.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const [version, appcastPath] = process.argv.slice(2);
if (!version || !appcastPath) {
  console.error("usage: release-notes-localized.mjs VERSION APPCAST_XML");
  process.exit(2);
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(join(root, "website/src/data/releases.ts"), "utf8");
// A data-only module: drop the type declaration and the export keyword, then
// evaluate the array literal in an empty sandbox.
const script = source
  .replace(/export type Release = \{[\s\S]*?\n\};\n/, "")
  .replace(/export const releases\s*:\s*readonly Release\[\]\s*=/, "releases =");
const sandbox = {};
vm.runInNewContext(script, sandbox);
const release = (sandbox.releases ?? []).find((entry) => entry.version === version);
if (!release) {
  console.error(`warning: no entry for ${version} in website/src/data/releases.ts; the appcast keeps English release notes only`);
  process.exit(0);
}

// English first: it is the fallback when none of the languages match.
const languages = {
  en: { heading: "What's new", changelog: "View the full changelog", path: "" },
  zh: { heading: "新功能与改进", changelog: "查看完整更新日志", path: "zh/" },
  ja: { heading: "新機能と改善", changelog: "更新履歴をすべて見る", path: "ja/" },
  ko: { heading: "새 기능과 개선", changelog: "전체 업데이트 내역 보기", path: "ko/" },
};
const escape = (text) =>
  text.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const cdata = (html) => `<![CDATA[${html.replaceAll("]]>", "]]]]><![CDATA[>")}]]>`;

const descriptions = [];
for (const [lang, copy] of Object.entries(languages)) {
  const items = release.highlights?.[lang] ?? [];
  if (items.length === 0) continue;
  const fragment =
    `<h3>Pulse ${escape(version)} · ${copy.heading}</h3>` +
    `<ul>${items.map((item) => `<li>${escape(item)}</li>`).join("")}</ul>` +
    `<p><a href="https://www.pulseticker.app/${copy.path}changelog">${copy.changelog}</a></p>`;
  descriptions.push(`            <description xml:lang="${lang}">${cdata(fragment)}</description>`);
}
if (descriptions.length === 0) {
  console.error(`warning: ${version} has no highlights in website/src/data/releases.ts; appcast left unchanged`);
  process.exit(0);
}

const appcast = readFileSync(appcastPath, "utf8");
let found = false;
const rewritten = appcast.replace(/<item>[\s\S]*?<\/item>/g, (item) => {
  if (!item.includes(`<sparkle:shortVersionString>${version}</sparkle:shortVersionString>`)) return item;
  found = true;
  const stripped = item
    .replace(/\n[ \t]*<sparkle:releaseNotesLink[^>]*>[\s\S]*?<\/sparkle:releaseNotesLink>/g, "")
    .replace(/\n[ \t]*<description[^>]*>[\s\S]*?<\/description>/g, "");
  return stripped.replace(/\n([ \t]*)<enclosure /, `\n${descriptions.join("\n")}\n$1<enclosure `);
});
if (!found) {
  console.error(`error: no <item> for ${version} in ${appcastPath}`);
  process.exit(1);
}
writeFileSync(appcastPath, rewritten);
console.log(`inlined ${descriptions.length} localized descriptions for ${version} into ${appcastPath}`);
