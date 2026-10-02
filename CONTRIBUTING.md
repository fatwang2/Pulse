# Contributing to Pulse

This checkout contains two independent open-source editions. Current commercial
Mac and website development takes place elsewhere; historical Mac build
instructions are linked from [the history guide](docs/history/README.md).

## Choose an edition

| Edition | Source | Requirements |
| --- | --- | --- |
| Claude Code | `plugins/claude-code` | Claude Code 2.1.287+, with Mods enabled |
| Omarchy | `omarchy` | Node.js 22+ for reducer tests; Omarchy 4 / Qt for runtime checks |

Read the edition's README and AGENTS.md before changing it. Keep changes scoped;
sharing a repository does not require identical features or shared dependencies.
Preserve MIT notices and inherited attribution.

## Local checks

From the repository root:

```sh
make test-claude
make test-omarchy
make validate
```

`make validate` runs both suites and checks diff whitespace. Claude tests use its
native Mods harness with mocked host APIs and make no model calls. Omarchy's
installer tests use a temporary XDG_CONFIG_HOME and stub shell commands; they
never install Pulse into your real configuration.

For full Omarchy validation on Linux:

```sh
make -C omarchy validate
```

That additionally needs qmllint and `omarchy plugin validate`. Test the actual
bar/panel in a suitable Omarchy session before claiming runtime acceptance.
For Claude type checking, follow its README's declaration-generation instructions.
The GitHub workflow runs reducer/source checks and the native Claude suite;
it does not sign or publish apps and does not prove desktop/runtime acceptance.

## Issues and changes

Identify **Claude Code**, **Omarchy**, **current commercial Mac**, or **historical
Mac** when reporting an issue. Include relevant application/host versions and
reproduction steps. Remove credentials and private financial information from
logs or screenshots. Use private email for security reports.

A pull request should describe the user-visible behavior, affected edition, and
checks performed. Avoid mixing Mac distribution changes with open-source edition changes.
Edition versions and changelogs remain separate; existing `v0.*` Mac tags must
not be reused for open-source edition releases. See [transition notes](docs/repository-transition.md).
