# Contributing to Pulse

This repository holds seven independent open-source editions of Pulse and the
documentation for Pulse MCP. Current commercial Mac and website development
takes place elsewhere; historical Mac build instructions are linked from
[the history guide](docs/history/README.md).

## Choose an edition

| Edition | Source | Requirements | Local checks |
| --- | --- | --- | --- |
| Claude Code | `plugins/claude-code` | Claude Code 2.1.287+, with Mods enabled | `make test-claude` |
| opencode | `opencode` | Node.js 22+; opencode 1.15+ or 2.x for runtime checks | `make test-opencode`, then `npm run build` in `opencode/` |
| Herdr | `herdr` | Node.js 22+; Herdr for runtime checks | `make test-herdr` |
| Rex | `rex` | Node.js 22+; Rex for runtime checks | `make test-rex` |
| Metrix.Bar | `metrix` | Node.js 22+; Metrix.Bar with its local API for runtime checks | `make test-metrix` |
| Omarchy | `omarchy` | Node.js 22+ for reducer tests; Omarchy 4 / Qt for runtime checks | `make test-omarchy` |
| Raycast | `raycast` | Node.js 22+; Raycast for runtime checks | `make test-raycast` |
| Pulse MCP | `mcp` | Documentation only: the server is part of Pulse for Mac | — |

Read the edition's README and AGENTS.md before changing it (Raycast's rules
are in [docs/raycast.md](docs/raycast.md), because the Store ships everything
in `raycast/`). Keep changes scoped: sharing a repository does not require
identical features or shared dependencies. Preserve MIT notices and inherited
attribution.

Some rules hold across the editions; each AGENTS.md states them precisely:

- Each edition lists the only hosts it contacts. Keep its README, docs and
  code in step on hosts, storage and behavior.
- Respect Yahoo Finance cooldowns. Never show cached data as fresh or an
  unknown delay as real time.
- Promote Pulse for Mac only, with links tagged with the edition's own
  `utm_source`.
- Never commit credentials, local API tokens, generated declarations,
  `node_modules` or build output.

## Local checks

From the repository root:

```sh
make test       # every edition's checks
make validate   # make test, then git diff --check
```

Or run one edition's target from the table. `make test-claude` needs the
Claude Code CLI and `make test-raycast` installs Raycast's npm dependencies;
the Node-only targets need no install.

What the checks cover:

- **Claude Code** tests use its native Mods harness with mocked host APIs and
  make no model calls. For type checking, follow its README's
  declaration-generation instructions.
- **opencode**, **Herdr** and **Rex** test their shared quote and watchlist code
  with `node --test`; the opencode and Rex copies must match Herdr's, and tests
  check it. Rex also tests that every line it draws fits its pane.
- **Metrix.Bar** tests check that `metrix/index.json` matches `pulse.bar` (its
  SHA-256 and version), the declared hosts, and the Worker's symbol, search and
  formatting rules. Rebuild the index after every change to `pulse.bar`; see
  the [Metrix.Bar guide](metrix/README.md).
- **Omarchy**'s installer tests use a temporary `XDG_CONFIG_HOME` and stub shell
  commands; they never install Pulse into your real configuration. For full
  validation on Linux, run `make -C omarchy validate`, which also needs
  qmllint and `omarchy plugin validate`.
- **Raycast** runs its search, catalog and quote tests, lint, build and type
  check.

## Runtime acceptance

Unit tests do not prove an edition works in its host. Before claiming a
change works, try it there:

| Edition | How |
| --- | --- |
| Claude Code | Load the plugin in Claude Code, and in Claude Desktop's Code tab if the change touches the panel |
| opencode | Install the packed package in a real opencode v1 and v2, not only from a checkout |
| Herdr | `herdr-app check` on the mod, then run it in Herdr; each `preview.png` is a real screenshot |
| Rex | `rex config check` on an `init.lua` that loads `rex/lua/pulse.lua`, then `rex do <that file> --action pulse_open` and a look at the pane and its layer |
| Metrix.Bar | `POST /v0/validate` and `POST /v0/check` with fixtures and steps, then the installed dashboard |
| Omarchy | The bar and panel in an Omarchy 4 session |
| Raycast | `npm run dev` in `raycast/`, then the command in Raycast |

The GitHub workflow runs every edition's local checks on pull requests and on
`main`. It does not sign or publish anything and does not prove runtime
acceptance.

## Releases

Each edition is released on its own; versions and changelogs stay separate.
Existing `v0.*` tags belong to the historical Mac app and must not be reused
for open-source releases. Release steps are in each edition's AGENTS.md; for
example, opencode and Rex publish to npm from `opencode-v*` and `rex-v*` tags, Raycast is
submitted to the Store only from the owner's Mac, and Metrix.Bar users receive
whatever `metrix/index.json` on `main` describes. See also the
[transition notes](docs/repository-transition.md).

## Issues and changes

Name the edition when you report an issue: **Claude Code**, **opencode**,
**Herdr**, **Rex**, **Metrix.Bar**, **Omarchy**, **Raycast**, **Pulse MCP**, **current
commercial Mac** or **historical Mac**. Include the relevant application and
host versions and the steps to reproduce. Remove credentials and private
financial information from logs and screenshots. Report security issues
privately to [sys@pulseticker.app](mailto:sys@pulseticker.app).

A pull request should describe the user-visible behavior, the affected edition,
and the checks performed, including runtime checks. Keep one edition per pull
request where you can, and never mix Mac distribution changes with open-source
edition changes.
