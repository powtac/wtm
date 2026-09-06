# Release review — 2026-09-05

## Scope and result

The published release is **v0.4.2**, build 13, source commit
`4f4bb90133b93659805bc4c08857dffb544cc6f8`. The local maintenance checkout starts at
`410370f` and includes documentation and screenshot-tooling changes. Evidence for the
published binary and the maintenance checkout is distinguished below.

Distribution verification passes. Phase 5 remains **Implemented**: complete VoiceOver
output verification and final brand/trademark disposition are not established by this audit.
No new stable release is authorized by a green build alone.

## Published artifact verification

All four assets were downloaded from the [v0.4.2 release](https://github.com/powtac/wtm/releases/tag/v0.4.2).

| Check | Result |
|---|---|
| Release metadata | Version 0.4.2, build 13, commit matches the annotated tag target |
| SHA-256 manifest | All three payload hashes match; exact four-file asset allowlist passes |
| DMG hash | `c79619ca1ed5199181fe7861b3ea9a681837fa9a7ecd738b63c51d63df757c3f` |
| Artifact attestation | `gh attestation verify` succeeds for `powtac/wtm` |
| DMG | Read-only mount and `stapler validate` succeed |
| Application | `codesign --verify --deep --strict`, Gatekeeper execution assessment, and app `stapler validate` succeed |
| Launch | The mounted release opens its inventory and displays version 0.4.2 |
| Exact-commit CI | [CI run 33329314595](https://github.com/powtac/wtm/actions/runs/33329314595): Build and test and Secret scan succeed for the release commit |
| Release workflow | [Run 33329947583](https://github.com/powtac/wtm/actions/runs/33329947583) succeeds |

Local evidence is under ignored `build/release-audit-2026-09-05/` and
`build/release-audit-attestation.json`. These paths are local outputs, not committed evidence.

## History, secrets, personal data, and licenses

The checkout is not shallow. All 123 locally reachable commits and 912 unique blob objects
were inspected for private-key headers, AWS/GitHub/Hugging Face token patterns, user paths,
and email-shaped strings. No key/token pattern matched. This targeted scan complements the
successful release-commit CI TruffleHog check; it is not a claim that arbitrary secrets or
all personal data can be recognized by regular expressions.

- User-path matches are historical acceptance paths and synthetic runtime-redaction fixtures.
  The current MLX acceptance example now uses `$HOME` instead of a personal account path.
- Email-shaped content matches are Retina asset filenames, not contact addresses.
- Commit authors include a maintainer contact address and GitHub's Dependabot noreply address.
  Existing public commit metadata is retained. No history rewrite was performed.
- Tracked credential file extensions were checked; only `.env.example` is tracked among
  environment files. Local credentials are excluded from the audit report and Git.
- Model fixtures have CC0 license records; `scripts/validate-fixtures` passes.
- Runtime Swift packages are local project targets. Screenshot capture uses native XCTest attachments; no third-party
  Swift helper is copied into the application or test target.
- The icon's recorded provenance is generated original artwork in `design/README.md`.
  That document still marks branding as provisional; generation provenance is not a
  trademark clearance.

Raw pattern matches remain local in ignored `build/history-review-private.json`.

## Accessibility disposition

The released app exposes labelled sidebar scopes, Settings, scan/cancel actions, filters,
model rows, and detail regions through the accessibility tree. `Command-,` opens native
Settings and exposes the source switches. Cancel Scan updates the accessible status to
`Scan cancelled`.

VoiceOver was started for an explicit session, but the available automation interface
could not retrieve its spoken output/caption panel: selecting the VoiceOver process timed
out. This attempt is **not a passed VoiceOver session**. The remaining pass must exercise
first-run consent, sidebar/collection/detail traversal, search/filter, scan announcements,
cleanup and runtime preview cancellation, Settings, and menu bar navigation, verifying
actual spoken labels, focus order, and absence of traps. Do not infer this from UI tests.

## Brand/trademark disposition

A preliminary web search for the exact product name was performed. No register clearance
or similarity assessment has been established. The [DPMA search guidance](https://www.dpma.de/english/trade_marks/trade_mark_search/)
explains that exact-element searches do not provide similarity searching and that EUIPO
and WIPO records also matter for a complete German protection search.

The final product-name/acronym/icon disposition remains open pending documented evidence.
No claim of trademark availability is made.

## Maintenance verification

`./scripts/test` passes on 2026-09-05: 114 Swift package tests, application tests, Release
build, formatting, architecture, ADR, fixture, language, localization, website, and release
script gates. Full local log: `build/verification-2026-09-05.log`.

Screenshot and Homebrew verification are recorded in their respective guides after their
end-to-end checks. These maintenance changes do not change the already-published binary.

### Screenshot verification attempts

The focused source-setup UI test passed on Xcode 26.6 (one test, zero failures) after
restarting a stale local `testmanagerd`. Its initial post-test collection hung while Xcode
read coverage profiles from the runner container; the screenshot lane now disables
coverage only for image capture.

The full capture run subsequently reached the settings test, but macOS UserNotificationCenter's
`Hinweis` dialog intercepted toolbar clicks. This is recorded as a failed capture attempt,
not a successful screenshot set. The settings test now stops at the first assertion failure.
The dialog requires manual dismissal before the final full capture and visual verification.
Local logs: `build/screenshots-focused-2026-09-05.log` and
`build/screenshots-final-2026-09-05.log`.
