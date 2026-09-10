/**
 * What a published Pulse release must contain, in one place.
 *
 * `scripts/release-mac.sh` asks this before it spends an hour on notarization,
 * and `.github/workflows/release-macos.yml` asks it again as a gate, so the
 * definition of "complete" cannot drift between the two.
 *
 * Pulse's update feed is not a file inside the version's own Release: Sparkle
 * reads one appcast.xml that lives on the stable `appcast` tag. A version whose
 * assets uploaded but whose appcast entry did not is therefore invisible to
 * every installed copy — published by GitHub's reckoning, unreleased by
 * Sparkle's. Completeness here means both halves landed.
 *
 * Usage:
 *   node scripts/release-status.mjs status   # is the current version released?
 *   node scripts/release-status.mjs check    # exit 0 when a release may proceed
 */

import { execFileSync } from 'node:child_process'
import { appendFileSync, readFileSync } from 'node:fs'
import { argv } from 'node:process'
import { fileURLToPath } from 'node:url'

const REPO = process.env.GH_REPO ?? 'fatwang2/Pulse'
const APPCAST_TAG = 'appcast'
const APPCAST_URL = process.env.SPARKLE_FEED_URL
  ?? `https://github.com/${REPO}/releases/download/${APPCAST_TAG}/appcast.xml`

/** The macOS marketing version, read where the release itself reads it. */
export function currentVersion() {
  const text = readFileSync(new URL('../project.yml', import.meta.url), 'utf8')
  const target = text.split(/^ {2}PulseMac:\s*$/mu)
  if (target.length < 2) throw new Error('no PulseMac target in project.yml')
  const match = /MARKETING_VERSION:\s*"([^"]+)"/u.exec(target[1])
  if (match === null) throw new Error('PulseMac declares no MARKETING_VERSION')
  return match[1]
}

/**
 * One pattern per required asset of a version's own Release: the update archive
 * Sparkle downloads, and the disk image a first-time install needs.
 * @param {string} version
 */
export function releaseAssets(version) {
  return [
    new RegExp(`^Pulse-${version.replaceAll('.', '\\.')}\\.zip$`, 'u'),
    new RegExp(`^Pulse-${version.replaceAll('.', '\\.')}\\.dmg$`, 'u'),
  ]
}

/** @param {string} tag */
function fetchRelease(tag) {
  try {
    const json = execFileSync('gh', ['api', `repos/${REPO}/releases/tags/${tag}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    return JSON.parse(json)
  } catch {
    return undefined
  }
}

/**
 * The appcast as Sparkle sees it: fetched over the public download URL rather
 * than read from the repository, because that URL is what shipped apps poll.
 */
async function fetchAppcast() {
  const response = await fetch(APPCAST_URL, { redirect: 'follow' })
  if (!response.ok) return undefined
  return await response.text()
}

/**
 * True when the appcast advertises this version and points at that version's
 * own tag. Matching the tag matters: an appcast entry left over from a failed
 * upload can name the right version while its enclosure still points at assets
 * that were never replaced.
 * @param {string | undefined} appcast
 * @param {string} version
 */
export function appcastAdvertises(appcast, version) {
  if (appcast === undefined) return false
  const items = appcast.split('<item>').slice(1)
  return items.some(item =>
    new RegExp(`<sparkle:shortVersionString>\\s*${version.replaceAll('.', '\\.')}\\s*</sparkle:shortVersionString>`, 'u').test(item)
    && item.includes(`/releases/download/v${version}/`))
}

/**
 * True only for a version that is publicly installable *and* offered as an
 * update: a published, non-draft, non-pre-release GitHub Release carrying both
 * assets, plus an appcast entry for it. Anything less counts as unreleased, so
 * the pipeline repairs it on the existing tag instead of skipping it.
 * @param {{ draft?: boolean, prerelease?: boolean, assets?: { name?: string }[] } | undefined} release
 * @param {string | undefined} appcast
 * @param {string} version
 */
export function isComplete(release, appcast, version) {
  if (release === undefined || release.draft === true || release.prerelease === true) return false
  const names = (release.assets ?? []).map(asset => asset.name ?? '')
  if (releaseAssets(version).some(pattern => !names.some(name => pattern.test(name)))) return false
  return appcastAdvertises(appcast, version)
}

/**
 * Human-readable description of what is missing, for logs.
 * @param {{ draft?: boolean, prerelease?: boolean, assets?: { name?: string }[] } | undefined} release
 * @param {string | undefined} appcast
 * @param {string} version
 */
export function describeGap(release, appcast, version) {
  if (release === undefined) return 'no Release'
  if (release.draft === true) return 'draft Release'
  if (release.prerelease === true) return 'pre-release'
  const names = (release.assets ?? []).map(asset => asset.name ?? '')
  const missing = releaseAssets(version).filter(pattern => !names.some(name => pattern.test(name)))
  if (missing.length > 0) return `missing ${missing.map(pattern => pattern.source).join(', ')}`
  if (!appcastAdvertises(appcast, version)) return 'assets uploaded but the appcast does not offer them'
  return 'complete'
}

async function main() {
  const command = process.argv[2] ?? 'status'
  const version = currentVersion()
  const release = fetchRelease(`v${version}`)
  const appcast = await fetchAppcast()
  const complete = isComplete(release, appcast, version)

  if (command === 'status') {
    const output = process.env.GITHUB_OUTPUT
    const line = `released=${String(complete)}`
    if (output !== undefined) appendFileSync(output, `${line}\n`)
    console.log(line)
    console.log(`Pulse ${version}: ${describeGap(release, appcast, version)}`)
    return
  }

  if (command === 'check') {
    console.log(`Pulse ${version}: ${describeGap(release, appcast, version)}`)
    if (complete) {
      console.error(`error: Pulse ${version} is already fully released; bump MARKETING_VERSION in project.yml first`)
      process.exit(1)
    }
    return
  }

  console.error(`error: unknown command ${command} (expected "status" or "check")`)
  process.exit(2)
}

if (argv[1] !== undefined && fileURLToPath(import.meta.url) === argv[1]) await main()
