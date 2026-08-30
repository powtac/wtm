# ADR-027: Fail-Closed Public Release Chain

- Status: Accepted
- Date: 2026-08-24

## Context

Phase 5 turns a locally notarized application into a repeatable public release. Signing,
notarization, DMG presentation, GitHub publication, and Pages have different failure modes.
A workflow that uploads before every gate finishes can expose an incomplete or untrusted
`latest` release. The repository also remains private on GitHub Free until the public launch.
Finder automation adds a runtime-only boundary: AppleScript object specifiers are resolved
when executed, so successful compilation does not prove that a mounted path is exposed as
the assumed Finder object on a fresh hosted runner.

## Decision

- A stable release starts only after repository visibility is public, from an exact
  `vMAJOR.MINOR.PATCH` tag in `powtac/wtm` and a protected GitHub Environment named
  `release`. The tag must match `MARKETING_VERSION`.
- Before credentials are imported, the release must find a successful `push` run of the
  versioned `CI` workflow on `main` for the exact release commit. Its latest `Build and test`
  and `Secret scan` jobs must both be successful. Missing, skipped, pending, cancelled, or
  SHA-mismatched evidence fails closed; the release does not rerun the full CI suite.
- Developer ID and App Store Connect credentials exist only as Environment secrets. The
  certificate is imported into an ephemeral runner keychain; notarization uses an App Store
  Connect API key file rather than password arguments. The keychain and private key file are
  deleted in unconditional cleanup steps.
- The pipeline archives an Apple-Silicon Release build, notarizes and staples the app,
  creates a versioned native DMG, signs/notarizes/staples that DMG, and then repeats
  `codesign`, `stapler`, `spctl`, mount, copy, and process-start checks against the payload.
- Apple notarization is the malware gate. A separate artifact audit rejects credential file
  types and known high-confidence secret patterns before upload.
- The release contains the DMG, SHA-256 manifest, SPDX 2.3 SBOM, and machine-readable build
  metadata. Signed and notarized bytes are traceable, but byte-identical reproducibility is
  not claimed because timestamps and Apple tickets are external inputs.
- GitHub Release creation remains draft until every local gate, backup upload, and—when the
  repository is public—artifact attestation succeeds. Only the final step publishes it and
  changes `latest`.
- The English static website is versioned in `website/`. Its validation runs while private;
  Pages deployment is structurally disabled until repository visibility is public.
- Workflow actions are pinned to full commit hashes and each job receives only its explicit
  GitHub token permissions.
- Hosted macOS runner capabilities are not treated as part of the toolchain contract. The
  release verifies the selected Xcode and Swift toolchain before signing; release-specific
  scripts preflight both PATH-resolved tools and absolute macOS system-tool paths before
  signing credentials are imported.
- The exact hosted runner image from the workflow's `Set up job` log is diagnostic evidence.
  A generic runner label and a successful local run do not prove equivalent installed tools,
  GUI state, or Finder object resolution.
- DMG layout automation receives the actual `hdiutil` mount path and addresses it as a Finder
  folder. The display volume name is not used to discover a Finder `disk` object when an
  explicit temporary mountpoint is used.
- Files assigned to Finder window properties are resolved from their POSIX path before the
  Finder command. Nested `file of folder` object specifiers are not used for the background
  image because their runtime resolution differs across Finder versions.
- AppleScript compilation remains a syntax gate. The release run must execute the layout,
  confirm the app and Applications link, and require the resulting `.DS_Store` before the
  writable image is detached or converted.
- A release tag is pushed only after local gates, successful exact-SHA CI, public visibility,
  the protected `release` Environment, and all required secrets are verified. A failed
  pre-release tag run may be rerun while no GitHub Release is published; after publication,
  the tag and release bytes are immutable and must never be force-moved.

## Consequences

- A failed build can leave logs or a workflow artifact, but cannot publish a non-draft
  release or update `latest`.
- GitHub Environment setup and six Apple secrets are required after public launch and
  before a release tag can succeed. Private repositories, forks, and other repositories
  cannot enter the release job. GitHub Free does not expose protected Environment secrets
  to this repository while it is private.
- The pipeline consumes macOS Actions minutes and performs two notarization submissions.
- Reusing exact-SHA CI evidence removes a second full macOS test and UI-test pass from each
  release. A tag created before CI is green fails early and must be rerun after CI succeeds.
- A Finder-layout failure can occur after the app has already been notarized. Logs and release
  evidence must identify the failing phase instead of reporting the entire trust chain as a
  notarization failure.
- Public Pages, attestations, Discussions, and security features still require a deliberate
  repository-visibility launch step; committed workflows do not imply remote activation.

## Requirements impact

This decision implements the architecture for `GH-CI-013` through `GH-CI-014`,
`GH-REL-001` through `GH-REL-014`,
`GH-WEB-001` through `GH-WEB-008`, and the private-to-public controls in `GH-PUB-003`
through `GH-PUB-005`. Phase 5 remains `Implemented`, not `Completed`, until a real tagged
release passes the protected environment and the public-launch audit is recorded.

## Validation

CI parses the workflows, compiles the AppleScript, renders the DMG artwork, validates the
SPDX JSON, runs website link/accessibility checks, and executes the normal code gates.
A release run first verifies the successful CI workflow and required jobs for its exact SHA,
then provides the authoritative Developer ID, notarization, stapling, Gatekeeper, DMG
mount/copy/start, secret-pattern, checksum, SBOM, and publication evidence.
The 2026-08-25 first release attempt demonstrated that `macos-15` did not provide `rg` by
default: the duplicated full CI suite stopped in the verification step before signing. Exact-
SHA CI reuse removes that unnecessary release dependency; this operational change is separate
from and does not constitute notarization evidence. A later `v0.3.4` attempt successfully
notarized, stapled, and Gatekeeper-validated the app, then failed while resolving a custom
temporary mountpoint as Finder `disk "WTM 0.3.4"`. Waiting did not change the object model.
Passing the actual mount path as a Finder folder succeeded in a runtime fixture and preserves
the phase boundary: app notarization evidence remains valid, while DMG packaging remains
failed until its own gates pass. The subsequent `v0.3.5` attempt reached that folder but Finder rejected
the nested background-image object specifier with error `-10006`. Resolving the same image
to a concrete POSIX file alias before entering the Finder command succeeds against a real
writable APFS DMG and removes that runner-dependent object-specifier resolution.
The `v0.3.6` run confirmed that the background alias and `.DS_Store` layout step execute on
the hosted runner, then failed at the incorrectly hardcoded `/usr/bin/sync`; macOS exposes
that utility as `/bin/sync`. The release now validates all distribution executables before
credential import, so a path mismatch fails before archive and notarization work.
