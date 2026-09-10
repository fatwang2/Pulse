/**
 * Point the website's download mirror at the release just built.
 *
 * `website/src/download.ts` holds the version, file name, R2 key, source URL,
 * byte size and SHA-256 of the DMG the site serves. The Worker fetches that DMG
 * from GitHub and refuses to cache it unless the bytes match the size and
 * checksum recorded here — which is why these values are committed rather than
 * read from the release at runtime: a checksum fetched from the same place as
 * the file it is meant to vouch for proves nothing.
 *
 * Every field is derivable from the built artifact, so the release workflow
 * runs this instead of asking someone to transcribe a hash after the fact.
 *
 * Usage: update-download-mirror.mjs <path to the release DMG>
 * Exits 0 and reports "unchanged" when the file already says this, so the
 * caller can skip an empty commit.
 */

import { createHash } from 'node:crypto'
import { readFileSync, statSync, writeFileSync } from 'node:fs'
import { basename } from 'node:path'

const dmgPath = process.argv[2]
if (dmgPath === undefined) {
  console.error('usage: update-download-mirror.mjs <path to the release DMG>')
  process.exit(2)
}

const fileName = basename(dmgPath)
const match = /^Pulse-(\d+\.\d+\.\d+)\.dmg$/u.exec(fileName)
if (match === null) {
  console.error(`error: ${fileName} is not a Pulse release DMG (expected Pulse-<version>.dmg)`)
  process.exit(1)
}
const version = match[1]
const size = statSync(dmgPath).size
const sha256 = createHash('sha256').update(readFileSync(dmgPath)).digest('hex')
const repo = process.env.GH_REPO ?? 'fatwang2/Pulse'

/** Grouped the way the file already writes byte counts: 22_370_813. */
function groupDigits(value) {
  return String(value).replace(/\B(?=(\d{3})+(?!\d))/gu, '_')
}

const file = new URL('../website/src/download.ts', import.meta.url)
const source = readFileSync(file, 'utf8')

const declaration = /export const latestDownload = \{[\s\S]*?\} as const;/u
if (!declaration.test(source)) {
  console.error('error: could not find the latestDownload declaration in website/src/download.ts')
  process.exit(1)
}

const replacement = `export const latestDownload = {
  version: "${version}",
  fileName: "${fileName}",
  key: "releases/v${version}/${fileName}",
  sourceUrl:
    "https://github.com/${repo}/releases/download/v${version}/${fileName}",
  size: ${groupDigits(size)},
  sha256: "${sha256}",
} as const;`

const updated = source.replace(declaration, () => replacement)
if (updated === source) {
  console.log(`unchanged: the download mirror already serves ${version}`)
  process.exit(0)
}

writeFileSync(file, updated)
console.log(`download mirror now serves ${version} (${groupDigits(size)} bytes, sha256 ${sha256.slice(0, 12)}…)`)
