# Phase 5 Acceptance

Phase 5 is Stable Public Release. The local implementation covers the public release
chain and the privacy-preserving WTM update path. The phase remains open until the
protected GitHub Environment, public repository launch, notarized release, and Pages
deployment evidence below are recorded.

| Gate | Evidence |
|---|---|
| Update source | `UpdateChecker` uses only `https://api.github.com/repos/powtac/wtm/releases` and official GitHub release URLs |
| Stable selection | Strict SemVer comparison ignores prereleases, drafts, malformed tags, and untrusted release URLs |
| Cache | Automatic checks are limited to one per seven days; manual checks use the same checker and status |
| Failure states | `Up to Date`, `Update Available`, `No Release Available`, `Offline`, `Rate Limited`, and `Check Failed` are distinct and text-based |
| Privacy | Update requests contain only GitHub API headers; no inventory, model, path, hardware, account, or telemetry data is sent |
| About | Native About window shows product name, version, build, repository, license, update status, release notes, and download links |
| Entry points | App menu, About, and `Settings > General` call the same `UpdateChecker`; Settings keeps the stable five-pane structure |
| Automated verification | SemVer, stable/prerelease, equal version, empty releases, invalid metadata, offline, rate-limit, and seven-day cache tests are included |
| Release pipeline | Exact-SHA CI reuse plus fail-closed Developer ID, notarization, stapling, Gatekeeper, DMG mount/copy/start, SBOM, checksum, secret audit, attestation, draft release, and atomic publish gates are versioned |
| Website | Versioned English Pages site, accessibility/link validation, extension guide, and official latest-release link are present |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
./scripts/check-release
./script/build_and_run.sh --verify
```

The public release workflow additionally requires repository visibility `public`, exact
tag `vMAJOR.MINOR.PATCH`, successful `Build and test` and `Secret scan` jobs from the `main`
CI push run for the exact commit, protected Environment `release`, five Environment secrets,
a successful Apple notarization, and manual public-launch checks. No release tag or public
repository mutation is performed by local tests.

## Open manual gates

1. Complete the history/secret/PII, fixture-license, trademark, and security audit.
2. Change `powtac/wtm` to public and enable Discussions, Pages, Dependabot, code scanning,
   secret scanning, push protection, and artifact attestations where supported.
3. Configure the protected `release` Environment and verify the first tagged release
   from a clean commit.
4. Record notarized DMG, Gatekeeper, Pages, update-link, Accessibility Inspector, and
   VoiceOver evidence.

Phase 6 must not be treated as started until these Phase 5 release gates are accepted.
