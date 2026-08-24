# ADR-010: Non-Sandboxed Least-Privilege Access

- Status: Accepted
- Date: 2026-08-24

## Context

The direct-distribution profile needs automatic discovery of narrow provider roots and
later local tool execution. Disabling App Sandbox removes a kernel-enforced product
boundary; it does not grant Full Disk Access or bypass normal file permissions.

## Decision

Disable App Sandbox for the primary distribution profile. Enforce least privilege in the
product: scan only built-in candidates that the user enables or folders the user selects;
respect TCC, POSIX permissions, ACLs, and read-only volumes; never request root, a
privileged helper, or mandatory Full Disk Access.

## Consequences

- Read-only is an application architecture guarantee backed by target isolation and tests.
- Bookmarks preserve user intent and URL recovery but are not claimed as a sandbox security
  boundary in this profile.
- Broad directories and newly mounted volumes are never scanned implicitly.
- Permission denial is a normal recoverable state, not a reason to escalate privileges.

## Requirements impact

Access requirements must distinguish product consent, actual OS access, source scope,
recovery, revocation, and offline state. Documentation must not imply that unsandboxed means
unrestricted or that read-only is enforced by macOS.

## Validation

Build settings disable App Sandbox and enable Hardened Runtime. Permission, path-boundary,
read-only architecture, and volume lifecycle tests cover the compensating controls.
