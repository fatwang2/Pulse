# Pulse public repository

This repository hosts Pulse for Omarchy, Pulse for Claude Code, Pulse for opencode, Pulse for Herdr and Pulse for Raycast. Current
commercial Mac and website source belongs in the private Pulse repository.

- Keep `omarchy`, `plugins/claude-code`, `opencode`, `herdr` and `raycast` independent; follow their
  scoped AGENTS.md instructions (Raycast's live in docs/raycast.md, since the
  Store ships everything in raycast/) and run checks appropriate to the changed edition.
- Do not restore current Mac source, website source, signing material, private
  SDKs, or app publishing workflows here.
- Preserve historical Git commits, version tags, MIT notices, free DMG/ZIP assets,
  and the existing Sparkle feed. Never target a public Mac tag at private source.
- The standalone Omarchy repository remains the managed install/update source
  during migration. Do not archive it or change its installation contract as
  a side effect of local work here. See docs/repository-transition.md.
- Do not overwrite local watchlists or touch a user's running Omarchy shell for
  validation. Installer tests use throwaway configuration directories and stubs.
- Keep Claude's generated declarations, node_modules, build products and credentials
  out of Git. Preserve unrelated dirty work and stage only named task paths.
- `make test` runs both open-source suites. Actual Omarchy runtime acceptance
  requires the Linux shell; JavaScript tests and installer stubs do not prove it.
