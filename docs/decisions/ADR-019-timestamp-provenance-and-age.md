# ADR-019: Timestamp Provenance and Age Semantics

- Status: Accepted
- Date: 2026-08-24

## Context

Most providers do not expose a reliable download date or last-used date. File creation and
modification timestamps can be copied, restored, or changed independently. A scan time says
nothing about model age.

## Decision

Represent provider download, file creation, file modification, and observation time as
separate timestamp kinds with confidence. Phase 1 model age uses the earliest available
non-observation timestamp among the installation artifacts and exposes the selected kind.
If none exists, age is unknown. `Old` compares this explicit age against the user threshold;
it never means unused or safe to delete.

## Consequences

- Phase 1 cannot claim `firstSeenAt` or historical last use without persistence.
- `observedThisScan` is useful diagnostics but excluded from age.
- Relative age uses localized whole units; details retain the absolute date and provenance.
- Sorting uses raw dates and keeps unknown values as their own deterministic group.

## Requirements impact

Requirements must name each timestamp, aggregation rule, confidence, timezone, display and
sorting semantics, unknown fallback, and the distinction between age and usage.

## Validation

Domain and presentation tests cover earliest-change selection, observation exclusion,
whole-unit formatting, sorting, thresholds, and unknown age.
