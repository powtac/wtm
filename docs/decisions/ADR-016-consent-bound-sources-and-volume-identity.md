# ADR-016: Consent-Bound Sources and Volume Identity

- Status: Accepted
- Date: 2026-08-24

## Context

An unsandboxed scanner can technically read more than the user intended. Paths also drift
when external volumes are unmounted and remounted. Treating a path string as authorization
or identity creates both privacy and correctness failures.

## Decision

Model every scan source as a durable user intent with its own enabled state, access state,
provider role, bookmark, and—where available—volume identifier plus relative path. Built-in
sources are narrow suggestions and remain disabled until explicit consent. Every scan runs
a readability, scope, and volume-identity preflight. An offline, stale, denied, or replaced
source is never silently mapped to another mount.

## Consequences

- `~`, `~/.cache`, `~/Library`, and whole new volumes are not automatic recursive roots.
- Denial, wrong selection, revocation, stale bookmarks, and remount are normal recoverable
  flows in Settings.
- Bookmark data restores URLs but does not equal current authorization or readability.
- Offline configuration persists while its ephemeral inventory does not.
- Source consent and identity remain defined here; operational scan ordering is defined by
  [ADR-029](ADR-029-specific-source-scan-priority.md).

## Requirements impact

Requirements must independently specify suggestion, consent, OS access, preflight,
revocation, source identity, remount, offline handling, path overlap, and scan ordering.

## Validation

Source settings round trips, permission-state tests, UI smoke tests, and the external-volume
lifecycle script cover the decision.
