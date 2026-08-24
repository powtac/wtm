# ADR-001: Direct macOS Distribution

- Status: Accepted
- Date: 2026-08-24

## Decision

WTM is distributed outside the Mac App Store as a Developer ID-signed, hardened,
notarized, and stapled macOS application. App Sandbox is disabled.

## Consequences

WTM can discover configured provider roots and, in later phases, invoke explicitly
configured local tools. TCC, POSIX permissions, and user consent still apply. WTM must not
request Full Disk Access, root access, or a privileged helper. Read-only behavior in Phase
1 is enforced by architecture and tests rather than the App Sandbox kernel boundary.
