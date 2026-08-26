# Phase 5 Acceptance

Phase 5 is Stable Public Release. The public launch and release chain are operational. The
phase remains `Implemented`, not `Completed`, until the final security disposition and a
VoiceOver release-candidate pass are recorded.

| Gate | Evidence |
|---|---|
| Update source | `UpdateChecker` uses only the official `powtac/wtm` GitHub Releases API and release URLs; stable SemVer, failure-state, offline, rate-limit, and seven-day cache tests pass |
| About and entry points | Native About, app menu, and `Settings > General` share the same update checker and official release/download links |
| Release pipeline | Exact-SHA CI reuse plus fail-closed Developer ID signing, notarization, stapling, Gatekeeper, DMG mount/copy/start, SBOM, checksum, secret audit, attestation, draft, and atomic publish gates are versioned |
| Public release | v0.3.7 is public with DMG, SHA-256 manifest, SPDX SBOM, build metadata, and an artifact attestation tied to release run `32897247933` |
| Independent DMG verification | Checksums, strict/deep code signing, notarized Gatekeeper acceptance, app/DMG stapling, DMG copy-and-launch, metadata, and the attestation were reverified on 2026-08-26 |
| Public repository | `powtac/wtm` is public; Issues are enabled; Discussions and Projects are intentionally disabled |
| Pages | GitHub Actions deployment is configured and `https://powtac.github.io/wtm/` returned HTTP 200 on 2026-08-26 |
| Protected release | Environment `release`, required reviewer, and all five required Environment secrets are configured |
| Repository security | Secret scanning and push protection are enabled; Swift code-scanning default setup is enabled; Dependabot security updates are enabled; `.github/dependabot.yml` adds weekly Actions updates |
| Automated verification | `./scripts/test`, `./scripts/test-ui`, `./scripts/check-release`, and `./script/build_and_run.sh --verify` pass on 2026-08-26 |
| Accessibility | Four UI smoke tests and native accessibility-tree inspection pass; the explicit VoiceOver release-candidate pass remains open |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
./scripts/check-release
./script/build_and_run.sh --verify
```

## Remaining gates

1. Resolve or explicitly accept SEC-001 through SEC-005 from
   `docs/audits/security-review-2026-08-26.md`, add their regression evidence, and re-run the
   security review against the final release candidate.
2. Record a VoiceOver pass against that release candidate. Automated accessibility hierarchy
   coverage is evidence, but it is not represented as a VoiceOver session.
3. Record the final history/PII and trademark audit. Fixture licenses and automated secret
   scans already pass.

The public v0.3.7 distribution is real and independently verified. These remaining gates
block the `Completed` label and the next stable tag; they do not invalidate the published
artifact evidence.
