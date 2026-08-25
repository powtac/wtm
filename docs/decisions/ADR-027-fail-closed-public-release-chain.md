# ADR-027: Fail-Closed Public Release Chain

- Status: Accepted
- Date: 2026-08-24

## Context

Phase 5 turns a locally notarized application into a repeatable public release. Signing,
notarization, DMG presentation, GitHub publication, and Pages have different failure modes.
A workflow that uploads before every gate finishes can expose an incomplete or untrusted
`latest` release. The repository also remains private on GitHub Free until the public launch.

## Decision

- A stable release starts only after repository visibility is public, from an exact
  `vMAJOR.MINOR.PATCH` tag in `powtac/wtm` and a protected GitHub Environment named
  `release`. The tag must match `MARKETING_VERSION`.
- Developer ID and App Store Connect credentials exist only as Environment secrets. The
  certificate is imported into an ephemeral runner keychain and the keychain is deleted in
  an unconditional cleanup step.
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
  release preflight verifies required command-line tools before any signing step and installs
  missing `ripgrep` noninteractively with Homebrew auto-update disabled; an unavailable
  dependency fails the run before credentials are imported.
- A release tag is pushed only after local gates, public visibility, the protected `release`
  Environment, and all required secrets are verified. A failed pre-release tag run may be
  rerun while no GitHub Release is published; after publication, the tag and release bytes
  are immutable and must never be force-moved.

## Consequences

- A failed build can leave logs or a workflow artifact, but cannot publish a non-draft
  release or update `latest`.
- GitHub Environment setup and five Apple secrets are required after public launch and
  before a release tag can succeed. Private repositories, forks, and other repositories
  cannot enter the release job. GitHub Free does not expose protected Environment secrets
  to this repository while it is private.
- The pipeline consumes macOS Actions minutes and performs two notarization submissions.
- Public Pages, attestations, Discussions, and security features still require a deliberate
  repository-visibility launch step; committed workflows do not imply remote activation.

## Requirements impact

This decision implements the architecture for `GH-REL-001` through `GH-REL-009`,
`GH-WEB-001` through `GH-WEB-008`, and the private-to-public controls in `GH-PUB-003`
through `GH-PUB-005`. Phase 5 remains `Implemented`, not `Completed`, until a real tagged
release passes the protected environment and the public-launch audit is recorded.

## Validation

CI parses the workflows, compiles the AppleScript, renders the DMG artwork, validates the
SPDX JSON, runs website link/accessibility checks, and executes the normal code gates.
A release run additionally provides the authoritative Developer ID, notarization, stapling,
Gatekeeper, DMG mount/copy/start, secret-pattern, checksum, SBOM, and publication evidence.
The 2026-08-25 first release attempt demonstrated that `macos-15` did not provide `rg` by
default: the run stopped in the verification step before signing. The release workflow now
performs the explicit preflight required above; this operational fix is separate from and
does not constitute notarization evidence.
