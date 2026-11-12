#!/usr/bin/env node
// pulse-rex: the Pulse watchlist for Rex, and the commands its palette actions run.
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { QuoteError } from "../src/quotes.js";
import { Watchlist } from "../src/watchlist.js";
import { createStore } from "../src/store.js";

const HELP = `pulse-rex — stock and crypto quotes beside your agents in Rex

Usage:
  pulse-rex install           add Pulse to Rex's command palette (edits Rex's init.lua)
  pulse-rex uninstall         take it out again
  pulse-rex                   run the watchlist in this terminal
  pulse-rex add SYMBOL...     add tickers: AAPL, 0700.HK, ^GSPC, BTC/USDT
  pulse-rex remove SYMBOL...  remove tickers
  pulse-rex pause | resume | toggle-pause
  pulse-rex refresh           ask open Pulse panes for a round now
  pulse-rex list              print the watchlist
  pulse-rex --version
`;

const self = [process.execPath, realpathSync(fileURLToPath(import.meta.url))];
const [command = "tui", ...args] = process.argv.slice(2);

function editor() {
  const store = createStore();
  const offline = () => Promise.reject(new Error("not used"));
  return { store, watch: new Watchlist({ load: store.load, save: store.save, fetch: offline, now: Date.now, sleep: offline, changed() {} }) };
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

async function main() {
  switch (command) {
    case "tui": {
      const { runPane } = await import("../src/tui.js");
      const option = (name) => { const at = args.indexOf(name); return at === -1 ? undefined : args[at + 1]; };
      const ratio = Number(option("--ratio"));
      const beside = option("--beside");
      return runPane(self, beside && ratio > 0 && ratio < 1 ? { beside, ratio } : null);
    }
    case "detail": {
      const { runDetail } = await import("../src/tui.js");
      const at = args.indexOf("--quote");
      return runDetail(at === -1 ? "" : args[at + 1]);
    }
    case "prompt": {
      const { runPrompt } = await import("../src/tui.js");
      return runPrompt();
    }
    case "add": case "remove": {
      if (!args.length) {
        if (command === "add" && process.stdin.isTTY) {
          const { runPrompt } = await import("../src/tui.js");
          return runPrompt();
        }
        fail(`Usage: pulse-rex ${command} SYMBOL...`);
      }
      const { watch } = editor();
      for (const symbol of args) {
        try { console.log(watch[command](command === "remove" ? symbol.trim().toUpperCase() : symbol)); } catch (error) {
          fail(error instanceof QuoteError ? error.message : String(error?.message ?? error));
        }
      }
      return;
    }
    case "pause": case "resume": case "toggle-pause": {
      const { watch } = editor();
      const paused = command === "toggle-pause" ? !watch.preferences.paused : command === "pause";
      console.log(watch.pause(paused));
      return;
    }
    case "refresh": {
      createStore().requestRefresh();
      console.log("Asked open Pulse panes to refresh.");
      return;
    }
    case "list": {
      const { watch } = editor();
      console.log(watch.preferences.symbols.join("\n") || "Your watchlist is empty.");
      if (watch.preferences.paused) console.log("(automatic refresh is paused)");
      return;
    }
    case "install": case "uninstall": {
      const installer = await import("../src/install.js");
      try { console.log(installer[command]()); } catch (error) { fail(String(error?.message ?? error)); }
      return;
    }
    case "--version": case "-v": case "version": {
      const { VERSION } = await import("../src/tui.js");
      console.log(VERSION);
      return;
    }
    case "--help": case "-h": case "help":
      process.stdout.write(HELP);
      return;
    default:
      process.stderr.write(HELP);
      process.exit(2);
  }
}

main().catch((error) => fail(String(error?.stack ?? error)));
