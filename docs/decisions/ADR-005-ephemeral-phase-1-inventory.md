# ADR-005: Ephemeral Phase 1 Inventory

- Status: Accepted
- Date: 2026-08-24

## Context

An inventory database would enable history and offline snapshots, but would also introduce
schema migrations, stale-state semantics, local privacy retention, and recovery behaviour
before those features have proven product value. Provider files are already the source of
truth for Phase 1.

## Decision

Phase 1 keeps model identities, installations, artifacts, issues, and storage calculations
in memory. Every app launch performs a new full scan of the enabled sources. WTM does not
write a SQLite database or another model inventory index.

WTM persists only operational preferences needed to repeat the user's intent: configured
sources, stable URL bookmarks, consent state, source order, scan-on-launch, and UI
settings. Provider files remain the sole source of truth.

## Consequences

- Scan results stream into the UI but disappear when the app exits.
- An offline source remains configured, but models from a previous session are not shown.
- Phase 1 cannot claim a durable `firstSeenAt`, historical changes, or an offline snapshot.
- Startup work increases, so provider-specific roots, cancellation, bounded concurrency,
  and early result delivery are release requirements.
- A future persistent inventory requires a new ADR, schema, migrations, privacy review,
  and explicit product value. It is not a hidden Phase 1 extension.

## Requirements impact

Phase 1 requirements must define full rescan behaviour, what operational settings persist,
what inventory data does not persist, offline-source semantics, and which historical claims
are impossible. A future requirement for history, `firstSeenAt`, trends, or offline model
rows must first supersede this decision.

## Validation

The former SQLite inventory target and schema were removed. Settings round-trip tests prove
that only source intent and UI preferences persist; architecture and acceptance records
state that inventory results remain in memory.
