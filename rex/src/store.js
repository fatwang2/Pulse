// Where Pulse for Rex keeps the watchlist: one JSON file, shared by every
// Pulse pane and by the `pulse-rex` commands that Rex's palette runs. A second
// file is only touched, to ask running panes for a refresh.
import { mkdirSync, readFileSync, renameSync, statSync, unwatchFile, watchFile, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export function storeDir(env = process.env) {
  if (env.PULSE_REX_HOME) return env.PULSE_REX_HOME;
  const config = env.XDG_CONFIG_HOME || join(env.HOME || homedir(), ".config");
  return join(config, "pulse-rex");
}

export function createStore(dir = storeDir()) {
  const file = join(dir, "watchlist.json");
  const refresh = join(dir, "refresh");
  const watched = [];
  return {
    file,
    /** The saved preferences, or undefined before the first edit (the starter list then applies). */
    load() {
      try { return JSON.parse(readFileSync(file, "utf8")); } catch { return undefined; }
    },
    save(preferences) {
      mkdirSync(dir, { recursive: true });
      // Written whole and renamed, so a pane never reads half a file.
      const temporary = `${file}.${process.pid}.tmp`;
      writeFileSync(temporary, JSON.stringify(preferences, null, 2) + "\n");
      renameSync(temporary, file);
    },
    requestRefresh() {
      mkdirSync(dir, { recursive: true });
      writeFileSync(refresh, String(Date.now()));
    },
    /** Calls `onEdit` when another process saves, `onRefresh` when one asks for a refresh. */
    watch(onEdit, onRefresh) {
      const poll = { interval: 700, persistent: false };
      const changed = (callback) => (current, previous) => {
        if (current.mtimeMs !== previous.mtimeMs) callback();
      };
      watchFile(file, poll, changed(onEdit));
      watchFile(refresh, poll, changed(onRefresh));
      watched.push(file, refresh);
    },
    close() {
      for (const path of watched.splice(0)) unwatchFile(path);
    },
    exists() {
      try { return statSync(file).isFile(); } catch { return false; }
    },
  };
}
