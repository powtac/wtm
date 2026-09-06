# Phase 5 Acceptance

Phase 5 is Stable Public Release. The public launch and release chain are operational. The
technical history/PII review is recorded in the 2026-09-05 audit.

| Gate | Evidence |
|---|---|
| Update source | `UpdateChecker` uses only the official `powtac/wtm` GitHub Releases API and release URLs; stable SemVer, failure-state, offline, rate-limit, and seven-day cache tests pass |
| About and entry points | Native About, app menu, and `Settings > General` share the same update checker and official release/download links |
| Release pipeline | Exact-SHA CI reuse plus fail-closed Developer ID signing, notarization, stapling, Gatekeeper, DMG mount/copy/start, SBOM, checksum, secret audit, attestation, draft, and atomic publish gates are versioned |
| Public release | v0.4.2 is public with DMG, SHA-256 manifest, SPDX SBOM, build metadata, and an artifact attestation tied to release run `33329947583` |
| Independent DMG verification | v0.4.2 checksums, strict/deep code signing, notarized Gatekeeper acceptance, app/DMG stapling, read-only mount and launch, metadata, and attestation were reverified on 2026-09-05; copy-and-launch also passes in the published release workflow |
| Public repository | `powtac/wtm` is public; Issues are enabled; Discussions and Projects are intentionally disabled |
| Pages | GitHub Actions deployment is configured and `https://powtac.github.io/wtm/` returned HTTP 200 on 2026-08-26 |
| Protected release | Environment `release`, required reviewer, and all six required Environment secrets are configured |
| Repository security | Secret scanning and push protection are enabled; Swift code-scanning default setup is enabled; Dependabot security updates are enabled; `.github/dependabot.yml` adds weekly Actions updates |
| Automated verification | `./scripts/test`, `./scripts/test-ui`, `./scripts/check-release`, and `./script/build_and_run.sh --verify` pass on 2026-08-26 |
| Accessibility | Four UI smoke tests and native accessibility-tree inspection pass |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
./scripts/check-release
./script/build_and_run.sh --verify
```

## Backlog / Future

1. VoiceOver release-candidate pass.
2. Final brand/trademark disposition for the product name, acronym, and icon.

Security disposition was resolved by the 2026-08-30 remediation and fresh scan evidence in
`docs/audits/security-review-2026-08-26.md` (scan
`2bfc03ad-5bac-44b3-98b4-3d0da4756431`, zero reportable findings).

The public v0.4.2 distribution is real and independently verified. The earlier v0.4.0
evidence is historical.

The [2026-09-05 release audit](audits/release-review-2026-09-05.md) records current
artifact verification and the disposition of remaining acceptance work.
