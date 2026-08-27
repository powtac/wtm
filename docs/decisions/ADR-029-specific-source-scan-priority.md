# ADR-029: Specific Source Scan Priority

- Status: Accepted
- Date: 2026-08-27
- Implementation: Complete in Phase 1

## Context

WTM may scan both a specifically selected child folder and an explicitly selected parent
folder. The child is more likely to contain immediately useful model evidence, while the
parent remains part of the user's requested scope. The existing parent-covering filter
discarded the child or parent based on input order and therefore could delay useful results.

## Decision

Keep the scan trigger separate from operational ordering. Launch, manual, and successfully
persisted source-setting changes remain the events that start a full scan; `SourcePrioritizer`
does not inspect filesystem modification times and does not initiate scans.

`SourcePrioritizer` is the single deterministic ordering boundary in `WTMInventory`. It
removes only exact duplicate roots for the same provider, retains explicitly configured
nested roots, and sorts the operational queue by descending path depth. Provider priority
breaks equal-depth ties, followed by persisted source order. Thus `$HOME/.models` is scanned
before `$HOME`, while both remain eligible when both are enabled.

## Consequences

- Specific child folders can publish useful results earlier.
- An explicitly selected parent folder is still scanned and can discover additional results.
- Equal inputs produce the same order without relying on filesystem enumeration order.
- Overlapping results remain subject to normal installation reconciliation and physical-storage
  deduplication.
- Broad parent folders remain prohibited as automatic defaults; this decision applies only
  after explicit source configuration and consent.

## Requirements impact

Requirements must define the unchanged scan triggers, descending source path depth, tie-breakers,
retention of nested explicit sources, exact-duplicate handling, and the distinction between
operational ordering and scan initiation.

## Validation

Source-prioritizer tests cover nested-before-parent ordering, exact-root deduplication,
provider and persisted-order tie-breakers, and coordinator event order. Existing source
access, scope, reconciliation, and automatic source-setting rescan tests remain applicable.
