# ADR-018: Evidence-First Reconciliation and Storage Accounting

- Status: Accepted
- Date: 2026-08-24

## Context

Provider caches contain manifests, revisions, hard links, shared blobs, incomplete files,
and broad manual roots. A single physical artifact may appear through several logical
models. Phase 1 exposed duplicate generic `local` rows and naive byte totals when identity
and storage were conflated.

## Decision

Keep model identity, variant, installation, and artifact as separate concepts. IDs are
opaque strings with adapter-defined namespaces; Phase 1 requires deterministic identity
within a scan generation, not cross-session UUID persistence. Prefer provider-backed
evidence over a manual classification only when canonical artifact paths prove overlap.
Never merge distinct paths, revisions, sources, or volumes merely because names match.

Count allocated storage once per best-effort physical identifier. Assign bytes to an
installation only when the reference is exclusive; otherwise place them once in `Shared`
or `Unknown`. Do not hash multi-gigabyte weights during normal scanning.

## Consequences

- Generic duplicates disappear without hiding distinct installations.
- Provider scan order helps early reconciliation but cannot define identity by itself.
- Per-row logical or allocated size and inventory-wide unique storage are different metrics.
- APFS allocation, clones, sparse files, provider GC, and missing physical IDs limit exactness.
- Percentages use the current connected active scope, include explicit shared/unknown
  categories, and are calculated before presentation rounding.

## Requirements impact

Requirements must define entity boundaries, ID scope, reconciliation proof, storage terms,
physical deduplication, unknown handling, percentage denominator, rounding, and limits on
claims about reclaimable disk space.

## Validation

Domain and coordinator tests cover duplicate IDs, provider/manual overlap, distinct paths,
physical-identifier deduplication, shared/unknown totals, and 100-percent scoped breakdowns.
