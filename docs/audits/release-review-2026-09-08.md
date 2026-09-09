# Release review — 2026-09-08

> Scope update — 2026-09-09: VoiceOver and brand/trademark work were subsequently
> removed from release gates by the project owner; see [backlog.md](../../backlog.md)
> and [ADR-031](../decisions/ADR-031-deferred-manual-acceptance.md). The findings and
> gate classifications below record the scope at the time of this audit.


## Published version

[WTM v0.4.3](https://github.com/powtac/wtm/releases/tag/v0.4.3) was published on
2026-09-06. It is build 14 from `8060dfd5eac56ba164841cabf11e75ebd778a3e4`, which
matches the annotated tag target. The maintenance checkout starts at `5835fb3`.
Unreleased adapter changes are not included in this binary.

| Check | Evidence |
|---|---|
| Asset allowlist and checksums | Exactly four declared assets; all three payload hashes pass `scripts/audit-release-artifacts` on 2026-09-08 |
| DMG SHA-256 | `25654c764f1891a24e59e61cdb816cf7077f4beda7fcf1a7fecdbee8e779a1f4`, matching the public asset digest and Cask |
| Attestation | `gh attestation verify` succeeds for the DMG and repository `powtac/wtm` on 2026-09-08 |
| Exact-source CI | [Run 34044998060](https://github.com/powtac/wtm/actions/runs/34044998060) succeeds, including quality gates and UI smoke |
| CodeQL | [Run 34044997526](https://github.com/powtac/wtm/actions/runs/34044997526) succeeds for the same source commit |
| Release chain | [Run 34045354962](https://github.com/powtac/wtm/actions/runs/34045354962) succeeds; signing, application and DMG notarization, stapling, Gatekeeper, mount/copy/start and atomic publication are workflow evidence |
| Public Homebrew tap | `powtac/homebrew-wtm` contains version 0.4.3 and the matching immutable DMG URL/hash |
| Homebrew verification | Strict online audit, isolated install, strict/deep signature check, Gatekeeper, staple validation and uninstall pass on 2026-09-08 |

The v0.4.2 independent mount/launch and history review remain historical evidence in the
[2026-09-05 audit](release-review-2026-09-05.md). This review does not recast that manual
launch as a v0.4.3 test. Local outputs are ignored under `build/release-043-assets/`,
`build/release-artifact-audit.log` and `build/release-attestation-verification.log`.

## Maintenance checkout

`scripts/run-logged build/test-run.log ./scripts/test` passes: 123 Swift package tests,
application tests, Release build, formatting, architecture, ADR, fixture, language,
localization, website and release-script checks. The four new LM Studio contract tests
cover import layout, malformed contents, unknown/split candidates, partial files, shared
identity and a symlink outside consent.

`scripts/run-logged build/build-run.log ./script/build_and_run.sh --verify` builds and
launches the maintenance app successfully. Native UI inspection shows its inventory
window, sidebar, Settings, search and scan controls. This is a launch/UI observation,
not a VoiceOver output pass or a claim that LM Studio runtime support is shipped.

Homebrew evidence: `build/homebrew-release-audit.log` and
`build/homebrew-release-smoke.log`. The smoke test installs into a project-local directory
and removes that test installation; it does not replace `/Applications/WTM.app`.

## Deferred work

Screenshot work was cancelled by the user. Existing tooling is retained; no screenshot
set is accepted or uploaded as part of this work.

VoiceOver output verification and the final product-name/acronym/icon disposition are
listed as backlog in the current roadmap. They have not passed. REQUIREMENTS.md still
names them as release gates; that conflict needs an explicit disposition before Phase 5
can be marked complete. Build or notarization success does not resolve it.
