# ADR-007: Compiled Adapters Only

- Status: Accepted
- Date: 2026-08-24

## Context

Provider parsers and runtime integrations process untrusted local data and may eventually
perform destructive or executable actions. Loading third-party bundles would expand the
code-signing and supply-chain boundary.

## Decision

Code adapters are SwiftPM targets compiled, reviewed, tested, signed, and shipped with a
normal WTM release. WTM does not load third-party Swift bundles, dynamic libraries, or
runtime code plugins.

## Consequences

- Community code integrations arrive through pull requests and release review.
- Library Validation and Hardened Runtime are not weakened for plugins.
- End users can extend declarative data, but cannot install arbitrary in-process code.
- Adapter releases follow the WTM release cadence.

## Requirements impact

Extension requirements must clearly separate declarative user configuration from new
parsing, deletion, process, or network semantics that require reviewed code.

## Validation

The package graph contains one target per concrete adapter and the immutable registry is
constructed only by the app composition root.
