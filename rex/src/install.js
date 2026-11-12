// Adds Pulse to Rex's command palette: a marked block at the end of Rex's
// init.lua that loads lua/pulse.lua from this package. Nothing else in the
// file is touched, and the block is checked with `rex config check` before it
// stays; a failed check puts the file back as it was.
import { spawnSync } from "node:child_process";
import { accessSync, constants, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const BEGIN = "-- >>> pulse >>>";
export const END = "-- <<< pulse <<<";

/** Rex's own rule: REX_CONFIG, else rex/init.lua in the account's config directory. */
export function configPath(env = process.env) {
  if (env.REX_CONFIG) return env.REX_CONFIG;
  const config = env.XDG_CONFIG_HOME || join(env.HOME || homedir(), ".config");
  return join(config, "rex", "init.lua");
}

const luaString = (value) => `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;

/** The managed block: which Lua file to load and which program the actions run. */
export function loaderBlock(luaPath, command) {
  return [
    BEGIN,
    "-- Managed by `pulse-rex install`; `pulse-rex uninstall` removes it.",
    `dofile(${luaString(luaPath)}).setup({ bin = { ${command.map(luaString).join(", ")} } })`,
    END,
    "",
  ].join("\n");
}

/** `content` with the managed block replaced, or added at the end; `null` removes it. */
export function withBlock(content, block) {
  const start = content.indexOf(BEGIN);
  const endAt = start === -1 ? -1 : content.indexOf(END, start);
  if (start !== -1 && endAt !== -1) {
    let after = content.slice(endAt + END.length);
    if (after.startsWith("\n")) after = after.slice(1);
    let before = content.slice(0, start);
    if (!block) before = before.replace(/\n\n$/, "\n");
    return before + (block ?? "") + after;
  }
  if (!block) return content;
  if (!content.trim()) return block;
  return `${content.replace(/\n*$/, "")}\n\n${block}`;
}

function rex(args) {
  const result = spawnSync("rex", args, { encoding: "utf8", timeout: 20_000 });
  if (result.error) return { ok: false, text: `could not run rex (${result.error.message}). Is Rex's CLI on your PATH?` };
  return { ok: result.status === 0, text: (result.stderr || result.stdout || "").trim() };
}

function read(path) {
  try { return readFileSync(path, "utf8"); } catch { return null; }
}

const real = (path) => { try { return realpathSync(path); } catch { return null; } };

/**
 * The node and the package to write into init.lua. Node reports its real
 * path, which names its version under a version manager (…/node-v22.23.4/…)
 * and breaks when node is upgraded. So prefer a `node` on PATH that is the
 * same program through a stable link (…/node/current/bin/node), and the
 * package under that node's prefix when it is the same package.
 */
export function stablePaths(env = process.env, execPath = process.execPath, root = packageRoot()) {
  const realNode = real(execPath) ?? execPath;
  let node = execPath;
  for (const dir of (env.PATH ?? "").split(delimiter).filter(Boolean)) {
    const candidate = join(dir, "node");
    try { accessSync(candidate, constants.X_OK); } catch { continue; }
    if (real(candidate) === realNode) { node = candidate; break; }
  }
  let pkg = root;
  const linked = join(dirname(dirname(node)), "lib", "node_modules", "rex-pulse-ticker");
  if (linked !== root && real(linked) === real(root)) pkg = linked;
  return { node, lua: join(pkg, "lua", "pulse.lua"), bin: join(pkg, "bin", "pulse-rex.js") };
}

function packageRoot() {
  return dirname(dirname(realpathSync(fileURLToPath(import.meta.url))));
}

function apply(next, previous, config) {
  mkdirSync(dirname(config), { recursive: true });
  writeFileSync(config, next);
  const check = rex(["config", "check", config]);
  if (!check.ok) {
    if (previous === null) writeFileSync(config, ""); else writeFileSync(config, previous);
    throw new Error(`rex config check failed, so ${config} was put back as it was:\n${check.text}`);
  }
  return rex(["config", "reload"]).ok;
}

export function install() {
  const config = configPath();
  const files = stablePaths();
  const previous = read(config);
  const next = withBlock(previous ?? "", loaderBlock(files.lua, [files.node, files.bin]));
  if (next === previous) {
    return `Pulse is already in ${config}. Press cmd+shift+p in Rex and type Pulse.`;
  }
  const reloaded = apply(next, previous, config);
  return [
    `Added Pulse to ${config}${reloaded ? "" : " (rex config reload didn't run; reload Rex's config yourself)"}.`,
    "In Rex, press cmd+shift+p and type Pulse:",
    "  Pulse: Open Watchlist    the watchlist beside the focused pane",
    "  Pulse: Add Ticker…       add AAPL, 0700.HK, ^GSPC or BTC/USDT",
    "  Pulse: Refresh Quotes    one round now",
    "  Pulse: Pause or Resume   stop or restart automatic refresh",
    "To bind a key, add to init.lua after the Pulse block:",
    '  rex.bind("cmd+shift+u", "pulse_open")',
  ].join("\n");
}

export function uninstall() {
  const config = configPath();
  const previous = read(config);
  if (previous === null || !previous.includes(BEGIN)) return `Pulse isn't in ${config}. Nothing to remove.`;
  apply(withBlock(previous, null), previous, config);
  return `Removed Pulse from ${config}. Your watchlist is kept; delete ~/.config/pulse-rex to remove it too.`;
}
