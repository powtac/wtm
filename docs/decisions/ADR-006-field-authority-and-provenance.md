# ADR-006: Field-Specific Authority and Provenance

- Status: Accepted
- Date: 2026-08-24

## Context

The file system, provider manifests, local provider APIs, executables, and runtime health
checks answer different questions. A global rule such as "API before CLI before file
system" produces false certainty.

## Decision

Choose authority per field. Every non-trivial observation carries its source, observation
time, and confidence. Conflicting evidence remains representable; absence of evidence is
`unknown`, not a negative fact.

## Consequences

- File presence and bytes come from the scoped file system.
- Provider identity, revisions, sharing, and partial state prefer provider structures or
  manifests.
- Runtime state requires a runtime API, controlled process observation, or health check.
- A model card, download date, usability state, or deletion safety must not be inferred
  from a filename alone.

## Requirements impact

Requirements for identity, time, links, readiness, and deletion must name evidence,
confidence, observation time, conflict handling, and the `unknown` fallback.

## Validation

Domain types model confidence and timestamp kinds; adapter and reconciliation tests cover
confirmed, derived, partial, malformed, and unknown evidence.
