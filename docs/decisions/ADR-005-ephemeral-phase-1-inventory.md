# ADR-005: Ephemeral Phase 1 Inventory

- Status: Accepted
- Date: 2026-08-24

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
