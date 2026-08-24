# ADR-021: Compile-Time Phase Capability Isolation

- Status: Accepted
- Date: 2026-08-24

## Context

Feature flags and hidden controls do not remove destructive or executable code from a
release. Phase 1 promises read-only inventory, while later phases introduce deletion,
process execution, client handoff, and downloads with larger threat boundaries.

## Decision

Treat each shipping phase as a capability boundary in the target graph. Phase 1 links no
action, runtime, client, process-launch, or download implementation. Later capability
targets require their own ADR/threat-model update and must not be linked before their phase
gates pass. UI types never access file systems, persistence, network APIs, or `Process`
directly; the app target is the composition root.

## Consequences

- Disabled UI is not accepted as security isolation.
- Architecture checks enforce negative dependencies and known forbidden APIs.
- Every phase is independently testable and releasable.
- Shared domain contracts may anticipate later states, but Phase 1 cannot reach later
  operations.

## Requirements impact

Every requirement must have one target phase. Mixed features take the highest required
phase. Phase gates must include both positive behaviour and negative capability evidence.

## Validation

`scripts/check-architecture` rejects later-phase types, process/shell calls, source mutation,
and concrete-adapter imports in core targets; it is part of the standard test command.
