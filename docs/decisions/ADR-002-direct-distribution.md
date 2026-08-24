# ADR-002: Direct macOS Distribution

- Status: Accepted
- Date: 2026-08-24

## Context

Automatic discovery of configured local model stores and later invocation of explicitly
configured local tools conflict with the functional limits of a Mac App Store sandboxed
build.

## Decision

Distribute WTM outside the Mac App Store through GitHub Releases and the project website.
The primary product profile is not a Mac App Store profile.

## Consequences

- The direct build can inspect approved provider roots and later invoke approved tools.
- WTM must establish user trust through signing, notarization, clear consent, and narrow
  application-level capability boundaries.
- A future Mac App Store build would be a separate, reduced product profile and requires a
  new ADR; it is not a build-setting toggle for the same capabilities.

## Requirements impact

Distribution requirements must specify channel, trust chain, update/release ownership, and
the functional differences of any future store profile.

## Validation

The Phase 1 app was exported and accepted by Gatekeeper as a notarized Developer ID app.
