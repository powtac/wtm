# Adapter and distribution verification — 2026-09-09

## Checkout implementation

Base: `3e3a73278d21e7803d1801307ab455c6caa31f30` (published v0.5.0).
The current working tree adds four compiled roles: GPT4All read-only GGUF storage,
Jan flat `model.yml`/GGUF storage, LocalAI provider-managed runtime tests, and Open WebUI
browser handoff. They are not included in the published 0.5.0 binary. The working copy
carries marketing version 0.5.1; no new WTM release was published by this verification.

- `./scripts/test` passes: 136 package tests, 37 App tests, Release build and all included
  format, architecture, ADR, fixture, language, localization, website and release-script checks.
- `./script/build_and_run.sh --verify` passes after the final Swift changes.
- Commands ran through `./scripts/run-logged`; logs are `build/test-run.log` and
  `build/build-run.log` (the canonical launcher also manages its own output).
- Synthetic contracts cover storage/path/partial-file handling, LocalAI request boundaries,
  response limits and stale mappings, WebUI URL injection and evidence expiry, and local
  connection persistence with App preview invalidation and Reset to Defaults cleanup.
- Live LocalAI inference, authenticated WebUI handoff and real GPT4All/Jan installations
  were not verified. These checks do not replace manual accessibility acceptance.

Capability scope and primary contract references are in the
[integration catalog](../integrations/catalog.json), linked adapter notes and
[ADR-030](../decisions/ADR-030-explicit-local-service-connections.md).

## Published Homebrew distribution

The public tap previously pointed to 0.4.3 although 0.5.0 was public. The source Cask and
`powtac/homebrew-wtm` were updated to the immutable 0.5.0 asset, tap commit `71eda32`.

- Downloaded DMG SHA-256 matches the release manifest:
  `1b7b5400fd11de5dfd06806ddfbb567afe6d90722b8282b3b39e9a0fdeb206c1`.
- `gh attestation verify` for `powtac/wtm` passes.
- `brew audit --strict --online --cask powtac/wtm/wtm` passes.
- Installation into `build/homebrew-release-smoke`, strict/deep `codesign` verification,
  Gatekeeper assessment and `stapler validate` pass. Uninstall removes the test app.
- `brew livecheck` reports current/latest 0.5.0 and `outdated: false`.
- Full log: `build/homebrew-release-verify.log`. The existing application in
  `/Applications` was not replaced by this Homebrew smoke test.

## Scope revision

After this verification, the project owner explicitly moved VoiceOver support/acceptance
and brand/trademark disposition to [backlog.md](../../backlog.md) and removed them from
requirements and release gates. [ADR-031](../decisions/ADR-031-deferred-manual-acceptance.md)
records the decision. Phase 5 is Completed under the revised scope; neither deferred check
is claimed to have passed. Screenshot work was explicitly cancelled by the user.
