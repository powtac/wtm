# Changelog

All notable changes follow Keep a Changelog. The project uses Semantic Versioning once the
first public release is tagged.

## Unreleased

### Added

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

### Fixed

- Hugging Face model-card links for reviewed shorthand cache directories now restore the
  repository owner; unknown ownerless cache names no longer produce broken confirmed URLs.
