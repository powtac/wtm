# ADR-031: Deferred Manual Acceptance

- Status: Accepted
- Date: 2026-09-09
- Partially supersedes: ADR-014's trademark-review prerequisite.

## Context

VoiceOver completion/acceptance and final brand/trademark disposition were treated as
release gates. The project owner explicitly requested moving both to a backlog and removing
them from REQUIREMENTS.md on 2026-09-09.

## Decision

- Track both items in the root [backlog](../../backlog.md), outside the current requirements
  and release gates, without a committed delivery phase.
- Remove VoiceOver-specific requirements and acceptance criteria. Keep keyboard operation,
  general accessibility, Accessibility Inspector and the existing implementation unchanged.
- Remove the trademark-review publication prerequisite from GH-PUB-003 and supersede that
  prerequisite in ADR-014. Preserve history, secret, PII, license, fixture and security reviews.
- Existing asset-license and third-party logo restrictions remain applicable.
- Phase 5 can close against its revised scope; deferral is not evidence that either check
  passed. Previously recorded audit observations remain historical evidence.

## Consequences

Neither backlog item blocks publication or Phase 5 acceptance. The remaining release trust
chain and accessibility checks continue to apply. Reintroducing either item as a release gate
requires an explicit scope decision and corresponding requirements update.

## Requirements impact

Updates sections 11.4 and 15.2 and GH-PUB-003; removes the obsolete product-name gate
reference. Aligns roadmap, acceptance and design guidance with the revised scope.

## Validation

Check that REQUIREMENTS.md contains no VoiceOver-specific criterion or trademark-clearance
gate, current release guidance points to the backlog, and ADR traceability and local document
links remain valid. No runtime code changes or new application tests are needed.
