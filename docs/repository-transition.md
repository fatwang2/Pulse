# Public repository transition

## Scope

The public Pulse repository is the home for the maintained open-source Omarchy
and Claude Code editions, plus documentation and historical Mac downloads.
Current commercial Mac and website source remain private. The current checkout
no longer includes the historical app, Swift packages, website, Xcode project
configuration, Mac build/signing scripts, or Mac publishing workflows.
Their original contents remain reachable through existing commits and tags.

Root LICENSE and the edition licenses/notices are preserved. Historical release
notes remain available in Git history and GitHub Releases; the current checkout
keeps only a short historical Mac guide. Version tags, releases, binary assets,
and the Sparkle feed are unchanged by this local transition. Mac README screenshots
and the Omarchy preview are retained for product presentation.

## Omarchy provenance

Imported from [fatwang2/omarchy-pulse](https://github.com/fatwang2/omarchy-pulse)
at commit [`c57e21b1b3df5f3c76ff760e8b5436a3ccd194e0`](https://github.com/fatwang2/omarchy-pulse/tree/c57e21b1b3df5f3c76ff760e8b5436a3ccd194e0).
The edition lives in the top-level `omarchy/` directory. Runtime files, installer
behavior, LICENSE, NOTICE and preview image are preserved.
The README is adapted for the combined repository, AGENTS.md points to the frozen
Mac reference, and source checks no longer require GNU grep's `-P` flag.
The original repository retains its complete commit/contributor history; this
snapshot records its exact origin rather than claiming that history was merged.

The imported remote-tracking ref is retained locally for provenance inspection.
Publishing this checkout alone does not publish that ref or retire the old repo.

## Installation and update transition

The current managed installation command remains:

```sh
omarchy plugin add https://github.com/fatwang2/omarchy-pulse.git --enable
```

The old repository has not been changed or archived. It remains the managed
install/update source during transition; edits here do not yet update those users.
For local Linux development, the existing installer accepts the Omarchy edition directory:

```sh
./omarchy/install.sh --no-restart
```

It validates the directory and creates a development symlink. It is not a managed
Git update migration, and its existing behavior seeds an example watchlist only
when absent. Do not run it merely to validate this repository on someone's machine.

Before retiring the standalone source, choose and test a distribution path:
Omarchy-supported subdirectory installs if available, or an automatically exported
standalone distribution repository. Test both a fresh install and an update of an
existing installation, preserving plugin ID `pulse.omarchy` and user watchlists.
Maintain one editable implementation; avoid hand-maintained source copies.
Then announce the migration and update the old repository's README. Until that
work is done, the original managed install command stays documented and usable.

## Version and release boundaries

- Existing `v0.*` tags remain historical Mac releases and must not be repurposed.
- Omarchy and Claude keep their own manifest versions and validation requirements.
- New open-source release tags should identify the edition (for example
  `omarchy-v0.1.2` and `claude-v0.2.1`); this document creates no tags or releases.
- Commercial Mac release tags continue to reference preserved public source,
  never private commercial commits. Signing, notarization, release assets and
  Sparkle feed publication remain in the private distribution workflow.
- Open-source CI is read-only, requires no app signing secrets, and publishes nothing.

## Local validation, October 3, 2026

- Claude Code 2.1.287: the plugin is named `pulse-cc`. Strict manifest/marketplace
  validation and all 15 native tests passed.
- Omarchy: all 105 JavaScript tests, source rules and sandboxed installer checks passed.
- Claude strict TypeScript checks, workflow/issue-form YAML parsing, maintained
  documentation links and diff whitespace checks passed.
- Existing version tags, MIT notices and the four original Mac screenshots
  are preserved. Historical release-note files are accessible from preserved
  commits and Releases rather than duplicated here.
- Omarchy runtime files, installer, LICENSE and NOTICE match the pinned upstream
  snapshot. Only README, AGENTS.md and source-check portability were adapted.

GitHub CI runs the native Claude tests and Omarchy reducer/source/installer
checks for relevant pull requests and pushes to `main`. Full Omarchy QML validation
and real Linux shell acceptance remain separate from these checks.
The standalone Omarchy repository and existing Sparkle feed are unchanged by
this repository transition.
