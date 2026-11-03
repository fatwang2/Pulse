# Pulse

**Glanceable market data, wherever you work.**

[Website](https://www.pulseticker.app/) · [Mac App Store](https://apps.apple.com/app/id6812160110) · [Feedback](https://github.com/fatwang2/Pulse/issues)

Pulse is available for Mac, Claude Code, opencode, Herdr, and Omarchy. The Mac app is closed source;
this repository maintains the MIT-licensed Claude Code plugin, opencode plugin, Herdr mod and Omarchy edition.

| Edition | Source | Get started |
| --- | --- | --- |
| **Pulse for Mac** | Closed source | [Website and downloads](https://www.pulseticker.app/) · [Mac App Store](https://apps.apple.com/app/id6812160110) |
| **Pulse MCP** | Built into Pulse for Mac (docs only) | [Tools and client setup](mcp/README.md) |
| **Pulse for Claude Code** | Open-source plugin, MIT | [Installation and commands](plugins/claude-code/README.md) |
| **Pulse for opencode** | Open-source plugin, MIT | [Installation and commands](opencode/README.md) |
| **Pulse for Herdr** | Open-source mod and layout, MIT | [Installation and features](herdr/README.md) |
| **Pulse for Omarchy** | Open source, MIT | [Installation and features](omarchy/README.md) |

## Pulse for Mac

Market data in your macOS menu bar, with named watchlists, charts, and position
tracking. Visit [pulseticker.app](https://www.pulseticker.app/) for features,
downloads, and current purchase terms, or get Pulse from the
[Mac App Store](https://apps.apple.com/app/id6812160110).

Pulse for Mac is a paid app with a **30-day full-feature trial**, followed by
a **one-time purchase**. See [pricing and downloads](https://www.pulseticker.app/buy).

Pulse for Mac includes **Pulse MCP**, a local MCP server that gives Claude Code,
Claude Desktop, Cursor, Codex, VS Code and other MCP clients quotes, symbol
search, watchlists and positions over `127.0.0.1`. See the
[Pulse MCP guide](mcp/README.md) for its 15 tools and client configs.

![Pulse for Mac: a watchlist with live quotes and sparklines, opened from the menu bar](assets/readme/pulse-mac-01-en.png)

<p>
  <img src="assets/readme/pulse-mac-02-en.png" width="49%" alt="Symbol detail with a daily chart, buy and sell markers, and the position">
  <img src="assets/readme/pulse-mac-05-en.png" width="49%" alt="Holdings with day and total P&amp;L summed by currency">
  <img src="assets/readme/pulse-mac-03-en.png" width="49%" alt="Trade log with realized P&amp;L for each sell">
  <img src="assets/readme/pulse-mac-04-en.png" width="49%" alt="Local MCP server settings for AI agents">
</p>

The current Mac application and website are developed in a private repository.
Their current source is not included here. The historical Mac edition through
**0.15.8** retains its original MIT license in Git history and version tags;
free installers remain available. See [historical Mac source and downloads](docs/history/README.md).

## Pulse for Claude Code

A Claude Code plugin that shows stock and crypto quotes with signed percentage
changes above the prompt, with a `/pulse` panel for adding and removing tickers,
refreshing prices, and pausing updates. Stocks and indices come from Yahoo
Finance and crypto pairs from Binance's public Spot data. Requires Claude Code
**2.1.287 or later**, with Mods enabled.

![Pulse for Claude Code showing stock and crypto prices above the prompt](assets/readme/pulse-claude-code.png)

The prices and the `/pulse` panel also work in Claude Desktop's **Code** tab:

![Claude Desktop with Pulse CC prices above the prompt and the panel beside the chat](assets/readme/pulse-cc-desktop.png)

Install from GitHub:

```sh
claude plugin marketplace add fatwang2/Pulse
claude plugin install pulse-cc@pulse
```

Restart Claude Code or run `/reload-plugins`, then add a stock with
`/pulse add AAPL` or a crypto pair with `/pulse add BTC/USDT`, and open `/pulse`
to manage your watchlist.
See the [Claude Code guide](plugins/claude-code/README.md) for commands,
provider limits, privacy, and local development.

## Pulse for opencode

An [opencode](https://opencode.ai) plugin: a stock and crypto watchlist in the
session sidebar, with today's line on every row and a detail view with the
day's open, high, low and previous close, plus a one-line quote band along the
bottom of the window.

<img src="opencode/preview.png" alt="Pulse in the opencode sidebar" width="720">

In opencode v2, run `opencode plugin add opencode-pulse-ticker`. In opencode v1
(1.15+), add it to `~/.config/opencode/tui.json` and restart opencode:

```json
{ "plugin": ["opencode-pulse-ticker"] }
```

See the [opencode guide](opencode/README.md) for commands and privacy.

## Pulse for Herdr

A [Herdr](https://herdr.dev) mod: a stock and crypto watchlist docked beside
your agents, with today's line on every row and a detail view with the day's
chart, open, high, low and previous close. Comes as a mod and as a
"Herdr + Pulse" layout.

<img src="herdr/pulse-layout/preview.png" alt="Pulse for Herdr beside a terminal in Herdr" width="720">

Ask the agent running in Herdr:

```text
Read ~/.config/herdr-app/AGENTS.md, then add this layout: https://github.com/fatwang2/Pulse/tree/main/herdr/pulse-layout
```

See the [Herdr guide](herdr/README.md) for the mod on its own, usage and privacy.

## Pulse for Omarchy

An independent Pulse edition for Omarchy, with market data in the bar, named
watchlists, symbol search, quote details, charts, and theme-aware presentation.
Requires Omarchy 4 and its Quickshell shell.

<img src="omarchy/preview.png" alt="Pulse for Omarchy panel" width="360">

The existing managed installation continues to use the standalone repository
while its installation and update path is migrated:

```sh
omarchy plugin add https://github.com/fatwang2/omarchy-pulse.git --enable
```

The implementation is maintained in [`omarchy/`](omarchy/README.md).
See the [Omarchy guide](omarchy/README.md) for features and local development,
and [repository transition notes](docs/repository-transition.md) for migration details.

## Contributing and feedback

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Each open-source edition has its
own implementation and tests; development does not require building the Mac app.
Use [GitHub Issues](https://github.com/fatwang2/Pulse/issues) and identify the edition.
Mac support is also available at [hello@pulseticker.app](mailto:hello@pulseticker.app).
Report security issues privately to [sys@pulseticker.app](mailto:sys@pulseticker.app).

## License

The Omarchy edition and Claude Code plugin retain their [MIT license](LICENSE)
and any component notices. That license does not apply to the current commercial
Mac binaries or provide rights to third-party market data. Historical Mac source
retains its original license.
