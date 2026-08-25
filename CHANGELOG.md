# Changelog

All notable changes follow Keep a Changelog. The project uses Semantic Versioning.

## [0.3.3] - 2026-08-25

### Fixed

- Fixed zsh release-script failure caused by using the read-only `status` shell variable
  while processing notarization reports.

## [0.3.2] - 2026-08-25

### Fixed

- Isolated the client-broker ownership test from hosted-runner process-exit timing by using
  a deterministic process launcher; real process execution remains covered separately.

## [0.3.1] - 2026-08-25

### Fixed

- Made the reviewed client-broker process test cancellation-safe and increased its exit
  observation deadline for hosted macOS runners.

## Unreleased

### Added

- A fixed `Settings…` footer below the collapsible inventory sidebar, backed by the native
  macOS Settings scene and covered by UI automation.
- Native macOS application scaffold for bundle `de.powtac.whatthemodel`.
- Read-only domain, adapter registry, and ephemeral scanner coordination.
- Initial Ollama, Hugging Face, and manual-folder inventory adapters.
- Synthetic adapter fixtures, contract tests, app test plan, and CI entry points.
- Temporary macOS application icon asset and editable master artwork.
- First-run source selection, persistent source bookmarks, and configurable launch scans.
- Bounded scan events with visible source progress, cancellation, and completion summaries.
- Separate global scan and contextual Finder actions plus counted artifact headings.
- Explicit exclusion and build gate for microphone, audio, Media Library, Apple Music,
  and speech-recognition access.
- Finder-like artifact ordering and native sortable inventory-table columns.
- Catalogued `~/.unsloth` discovery, deduplicated scan storage totals, whole-unit allocated
  sizes, sortable model age with explicit timestamp provenance, configurable old-model
  thresholds, and separate `Old`/`Age Unknown` filters.
- Provider-first reconciliation that removes generic `local` duplicates from overlapping
  manual and Hugging Face sources while preserving distinct installation paths, plus
  rejection of Finder metadata as a synthetic Hugging Face revision.
- Source permission recovery and revocation, external-volume identity/remount handling,
  incremental adapter batches, storage-share breakdowns, column customization, and
  English-only catalog validation.
- First-run labeled-control UI smoke tests for local and ad-hoc CI signing.
- Phase 1 acceptance evidence, including an arm64 Developer ID app verified by Apple
  notarization, stapling, and Gatekeeper.
- Content-derived initial table-column widths that ignore longer column headers while
  preserving native resizing and persisted column customization.
- Complete accepted ADR set and decision index, including Phase 1 learnings for consent,
  volume identity, scan generations, reconciliation, storage accounting, timestamps,
  confirmed external links, capability isolation, and excluded media permissions.
- Architecture-grounded Requirements 0.2.0 with ADR traceability, explicit opaque-ID
  scope, stale scan-generation rejection, and repository-alias governance.
- CI validation for unique ADR IDs, required decision-record sections, and Requirements
  traceability.
- Reviewed single- and multi-model cleanup UI with complete operation, dependency,
  conflict, reversibility, and conservative reclaim previews.
- Centralized macOS Trash actions for manual and Hugging Face storage, separately confirmed
  irreversible Ollama deletion through the loopback API, and targeted verification rescans.
- Bounded, paths-free local cleanup audit with explicit user clearing in Settings.
- Best-effort macOS open-file detection, Ollama loaded-model blocking, read-only-volume
  rejection, and native cleanup-preview UI coverage on isolated fixtures.
- Phase 2 acceptance evidence for version `0.2.0 (2)`, including Developer ID signing,
  hardened runtime, Apple notarization, stapling, Gatekeeper, and launch smoke.
- Separate runtime integrity, compatibility, validation, and lifecycle observations with
  adapter version, evidence time, expiry, and best-effort memory estimates.
- Ollama loopback readiness plus bounded one-token inference verification without claiming
  daemon or loaded-model ownership.
- Reviewed llama.cpp test plans with absolute executable identity, typed arguments,
  numeric-loopback port allocation, explicit environment, in-app redacted logs, and Stop
  limited to the exact WTM-owned process handle.
- Configurable runtime tool definitions, identity-bound approvals, complete launch preview,
  and versioned privacy-redacted import/export that always imports disabled and unapproved.
- Native runtime UI, readiness-gated `Run Test`, explicit secondary `Try Anyway`, owned
  process cleanup during app termination, and XCUITest coverage of the non-executing plan.
- Phase 3 acceptance evidence for version `0.3.0 (3)`, including 83 package tests, 19 app
  tests, three UI tests, Developer ID signing, hardened runtime, Apple notarization without
  issues, stapling, Gatekeeper, and controlled launch smoke.
- A native model-table context menu with newline-safe multi-selection copying for the model
  name, confirmed provider model reference, or standardized absolute model path.
- Phase 5 update checking against official GitHub Releases with strict stable SemVer
  selection, seven-day automatic caching, offline/rate-limit states, and no telemetry.
- Native About window with version/build metadata, repository and license links, release
  notes, and manual GitHub download actions.

### Changed

- Moved Scan, Cancel, and Filters into the inventory-list header while keeping Cleanup in
  the selected-model detail pane.
- Split true empty inventory from zero visible filter matches; the latter now explains the
  active view scope and restores it through `Show All Models` without rescanning.
- Revalidated Phase 1 against Requirements 0.2.0 with a current Developer ID archive,
  accepted Apple notarization, stapled ticket, and successful Gatekeeper assessment.
- Added the Phase 2 capability boundary: immutable deletion plans, no-follow identity
  revalidation, conflict detection, centralized Trash dispatch, and redacted local audit.
- Added compiled cleanup adapters for manual files, Hugging Face revision/reference graphs,
  and irreversible Ollama loopback API deletion with loaded-model blocking.
- Reclaim estimates now deduplicate hardlinks and shared Ollama blobs; Hugging Face shared
  blobs execute last so partial failures cannot remove them before selected references.
- Added the Phase 3 capability boundary: runtime adapters create typed plans while only
  `RuntimeBroker` may launch or stop a process; shells, Terminal automation, client handoff,
  remote endpoints, and downloads remain absent.

### Fixed

- Empty Issues content now occupies the same content region as populated lists, keeping
  inventory controls at a stable vertical position when switching sidebar sections.
- Hugging Face model-card links for reviewed shorthand cache directories now restore the
  repository owner; unknown ownerless cache names no longer produce broken confirmed URLs.
- Scan-generation UUID gating prevents cancelled scan tasks and late events from mutating or
  finishing an immediately started replacement scan.
- Hugging Face repository-alias catalogs reject normalized key collisions, unsafe local
  keys, and invalid canonical repository IDs before scanning.
- User-selected llama.cpp definition provenance is preserved, and a persisted runtime
  override now suppresses its discovered default after relaunch instead of creating a
  duplicate tool entry.
