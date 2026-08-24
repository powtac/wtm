# ADR-003: Developer ID Release Trust Chain

- Status: Accepted
- Date: 2026-08-24

## Context

A directly distributed app needs an Apple-verifiable origin and repeatable release
evidence. A locally successful Xcode build is not a distributable release.

## Decision

Every public WTM app and DMG must be built in Release configuration, signed with Developer
ID Application, use Hardened Runtime, be notarized by Apple, have the ticket stapled, and
pass Gatekeeper assessment. Release automation must fail closed if any step or artifact
identity cannot be verified.

## Consequences

- Developer credentials remain outside the repository and logs.
- The app bundle that is tested, notarized, stapled, checksummed, and published must be the
  same artifact lineage.
- Ad-hoc signing is permitted only for local and CI UI tests, never public distribution.
- DMG automation and attestations remain a later release gate, not evidence supplied by a
  manually notarized app export.

## Requirements impact

Release requirements must distinguish build success, signing, notarization acceptance,
stapling, Gatekeeper validation, packaging, checksum, and publication.

## Validation

Phase 1 records an arm64 Developer ID archive, accepted notarization submission, successful
stapling, and Gatekeeper acceptance in `docs/phase-1-acceptance.md`.
