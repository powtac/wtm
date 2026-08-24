# ADR-004: Platform Baseline

- Status: Accepted
- Date: 2026-08-24

## Context

The first beta needs a narrow, testable platform matrix. Supporting older macOS versions
or Intel introduces availability branches and distribution variants before product value
is proven.

## Decision

Phase 1 supports Apple Silicon on macOS 15 or later. Newer macOS versions must remain in
the release test matrix as they become available.

## Consequences

- Intel and macOS 14 or earlier are unsupported in the first beta.
- Code may use macOS 15 APIs without compatibility shims.
- Expanding the platform matrix requires measured demand, CI coverage, and a reviewed ADR
  amendment or superseding decision.

## Requirements impact

Compatibility requirements must state CPU architecture, minimum OS, tested OS/Xcode
matrix, and unsupported configurations separately.

## Validation

Package and Xcode release builds target macOS arm64; release evidence records architecture
and minimum supported system.
