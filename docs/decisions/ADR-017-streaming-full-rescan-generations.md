# ADR-017: Streaming Full-Rescan Generations

- Status: Accepted
- Date: 2026-08-24
- Amended: 2026-08-27
- Implementation: Complete in Phase 1

## Context

Ephemeral inventory makes a full scan the consistency boundary. Large caches still need
early visible results, cancellation, stable UI state, and protection against stale events
from a previous scan. Source changes made in Settings must also converge on the same
consistency boundary instead of creating a second inventory path.

## Decision

Use one actor-isolated coordinator for launch scans, manual rescans, and rescans triggered
by a successfully persisted source-setting change. The scan trigger remains the caller's
event; operational source ordering follows
[ADR-029](ADR-029-specific-source-scan-priority.md). Each invocation is a new scan
generation, scans enabled sources deterministically, emits bounded asynchronous batches,
reconciles and publishes every available batch immediately into the current generation,
and ends with one explicit finished or cancelled outcome. Adapters should emit
incremental batches during long scans; coarser batches are acceptable when finer-grained
emission is not performant, with a target refresh interval of roughly 3–4 seconds. Only
one active generation may publish into a view model; late events from cancelled or
replaced generations are ignored. Disabling or revoking a source removes its ephemeral
results before the replacement generation starts.

## Consequences

- Results appear before the complete scan finishes.
- Specifically selected nested roots produce early results while their explicitly selected
  parent roots remain eligible for the same scan generation.
- Settings changes use the same full-rescan, cancellation, and generation-ordering rules
  as launch and manual scans.
- Scan progress is determinate only when the real unit of work is known; otherwise it is
  indeterminate and reports current source plus counts.
- Source-level failures do not erase successful results from other sources.
- A full rescan replaces the prior generation instead of appending duplicates.
- FSEvents remains optional; if introduced, it coalesces changes and triggers controlled
  source rescans rather than becoming a second inventory path.

## Requirements impact

Scan and source requirements must cover generation identity, single-flight behaviour,
ordering, batch bounds, immediate publication, replacement semantics, cancellation,
late-event rejection, source-setting rescans, partial source failure, and honest progress.

## Validation

Coordinator and app tests cover deterministic order, bounded streaming batches,
cancellation, source-setting-triggered rescans, source failures, incremental UI updates,
and the race where cleanup from a cancelled scan occurs after its replacement has started.
A generation UUID gates every event and terminal cleanup before it can mutate the active
view model.
