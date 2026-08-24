# ADR-017: Streaming Full-Rescan Generations

- Status: Accepted
- Date: 2026-08-24
- Implementation: Partial; explicit stale-generation rejection is not yet verified

## Context

Ephemeral inventory makes a full scan the consistency boundary. Large caches still need
early visible results, cancellation, stable UI state, and protection against stale events
from a previous scan.

## Decision

Use one actor-isolated coordinator for launch scans and manual rescans. Each invocation is
a new scan generation, scans enabled sources deterministically, emits bounded asynchronous
batches, reconciles every batch into the current generation, and ends with one explicit
finished or cancelled outcome. Only one active generation may publish into a view model;
late events from cancelled or replaced generations are ignored.

## Consequences

- Results appear before the complete scan finishes.
- Scan progress is determinate only when the real unit of work is known; otherwise it is
  indeterminate and reports current source plus counts.
- Source-level failures do not erase successful results from other sources.
- A full rescan replaces the prior generation instead of appending duplicates.
- FSEvents remains optional; if introduced, it coalesces changes and triggers controlled
  source rescans rather than becoming a second inventory path.

## Requirements impact

Scan requirements must cover generation identity, single-flight behaviour, ordering,
batch bounds, replacement semantics, cancellation, late-event rejection, partial source
failure, and honest progress.

## Validation

Existing coordinator and app tests cover deterministic order, bounded streaming batches,
cancellation, source failures, and incremental UI updates. They do not yet prove that a
late event or task cleanup from a cancelled scan cannot affect an immediately started scan.
FR-SCN-016 and its regression test are required before Phase 1 is re-accepted against
Requirements 0.2.0.
