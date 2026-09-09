# Phase 5 Acceptance

Phase 5 is Stable Public Release. The public launch and release chain are operational. The
technical history/PII review is recorded in the 2026-09-05 audit. Phase 5 is Completed
under the scope revised by [ADR-031](decisions/ADR-031-deferred-manual-acceptance.md).

| Gate | Evidence |
|---|---|
| Update source | `UpdateChecker` uses only the official `powtac/wtm` GitHub Releases API and release URLs; stable SemVer, failure-state, offline, rate-limit, and seven-day cache tests pass |
| About and entry points | Native About, app menu, and `Settings > General` share the same update checker and official release/download links |
| Release pipeline | Exact-SHA CI reuse plus fail-closed Developer ID signing, notarization, stapling, Gatekeeper, DMG mount/copy/start, SBOM, checksum, secret audit, attestation, draft, and atomic publish gates are versioned |
| Public release | v0.5.0 is public; its DMG digest, artifact attestation, Homebrew install, signature, Gatekeeper and staple checks pass in the 2026-09-09 audit. Exact-source workflow evidence for v0.4.3 remains in the historical audit |
| Independent DMG verification | v0.4.2 checksums, strict/deep code signing, notarized Gatekeeper acceptance, app/DMG stapling, read-only mount and launch, metadata, and attestation were reverified on 2026-09-05; copy-and-launch also passes in the published release workflow |
| Public repository | `powtac/wtm` is public; Issues are enabled; Discussions and Projects are intentionally disabled |
| Pages | GitHub Actions deployment is configured and `https://powtac.github.io/wtm/` returned HTTP 200 on 2026-08-26 |
| Protected release | Environment `release`, required reviewer, and all six required Environment secrets are configured |
| Repository security | Secret scanning and push protection are enabled; Swift code-scanning default setup is enabled; Dependabot security updates are enabled; `.github/dependabot.yml` adds weekly Actions updates |
| Automated verification | Release-source CI including UI smoke passes on 2026-09-06; maintenance `./scripts/test` (123 package tests, app tests and Release build) and `./script/build_and_run.sh --verify` pass on 2026-09-08 |
| Accessibility | CI UI smoke and native accessibility-tree inspection pass; VoiceOver-specific acceptance is deferred to the backlog |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
./scripts/check-release
./script/build_and_run.sh --verify
```

## Deferred work

VoiceOver support/acceptance and final brand/trademark disposition are tracked in
[backlog.md](../backlog.md). The project owner removed both from requirements and release
gates on 2026-09-09. Neither check is claimed to have passed.

Security disposition was resolved by the 2026-08-30 remediation and fresh scan evidence in
`docs/audits/security-review-2026-08-26.md` (scan
`2bfc03ad-5bac-44b3-98b4-3d0da4756431`, zero reportable findings).

The public v0.4.3 distribution, exact-source CI and matching Homebrew tap are verified in
the [2026-09-08 audit](audits/release-review-2026-09-08.md). The v0.4.2 independent
mount/launch and earlier v0.4.0 evidence are historical.

The [2026-09-05 release audit](audits/release-review-2026-09-05.md) records the history
review. Earlier audit statements treating the deferred items as release blockers are
historical and superseded by ADR-031.
Screenshot work was cancelled by the user and is not a pending task.

The [2026-09-09 audit](audits/adapter-release-review-2026-09-09.md) records the 0.5.0
Homebrew update and unreleased first-wave adapter verification separately.
