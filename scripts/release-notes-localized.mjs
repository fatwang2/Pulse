#!/usr/bin/env node
// Localized release notes for the Sparkle alert, from the website's changelog data.
//
// Usage: release-notes-localized.mjs VERSION OUT_DIR
//
// Writes OUT_DIR/Pulse-VERSION.<lang>.html for en, zh, ja, and ko when
// website/src/data/releases.ts has an entry for VERSION. generate_appcast turns
// each into a <sparkle:releaseNotesLink xml:lang="…"> — localized notes are
// always linked, never embedded — so the files must be uploaded next to the
// update archive; release-mac.sh does that.
//
// English is in the set on purpose: when none of the linked languages match
// the user's, Sparkle falls back to the first one listed, which is alphabetical
// by language code — so "en" has to be there, or an English (or German) Mac
// would be shown the Chinese page. The English fragment built from the GitHub
// release notes stays embedded as the default for appcast readers that use no
// link at all. Exits 0 without writing anything when the version is absent, so
// a release can go out before the website is updated.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const [version, outDir] = process.argv.slice(2);
if (!version || !outDir) {
  console.error("usage: release-notes-localized.mjs VERSION OUT_DIR");
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
  console.error(`warning: no entry for ${version} in website/src/data/releases.ts; localized release notes skipped`);
  process.exit(0);
}

const languages = {
  en: { heading: "What's new", changelog: "View the full changelog" },
  zh: { heading: "新功能与改进", changelog: "查看完整更新日志" },
  ja: { heading: "新機能と改善", changelog: "更新履歴をすべて見る" },
  ko: { heading: "새 기능과 개선", changelog: "전체 업데이트 내역 보기" },
};
const escape = (text) =>
  text.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

for (const [lang, copy] of Object.entries(languages)) {
  const items = release.highlights?.[lang] ?? [];
  if (items.length === 0) continue;
  const page = `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="color-scheme" content="light dark">
<style>
  body { font: 13px/1.5 -apple-system, system-ui, sans-serif; margin: 12px 14px; color: CanvasText; background: Canvas; }
  h3 { font-size: 13px; margin: 0 0 6px; }
  ul { padding-left: 18px; margin: 0 0 10px; }
  li { margin-bottom: 6px; }
  a { color: LinkText; }
</style>
</head>
<body>
<h3>Pulse ${escape(version)} · ${copy.heading}</h3>
<ul>${items.map((item) => `<li>${escape(item)}</li>`).join("")}</ul>
<p><a href="https://www.pulseticker.app/${lang === "en" ? "" : `${lang}/`}changelog">${copy.changelog}</a></p>
</body>
</html>
`;
  const file = join(outDir, `Pulse-${version}.${lang}.html`);
  writeFileSync(file, page);
  console.log(`wrote ${file}`);
}
