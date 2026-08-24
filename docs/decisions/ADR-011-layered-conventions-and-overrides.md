# ADR-011: Layered Conventions and Overrides

- Status: Accepted
- Date: 2026-08-24

## Context

Model tools use conventional paths, environment variables, app locations, and ports, but
users and providers can relocate them. Swift has no suitable Rails-style runtime discovery
mechanism for this product.

## Decision

Resolve configurable values through four explicit layers: built-in defaults, discovery
conventions, persistent user overrides, and session overrides. Later layers override
earlier values without mutating the shipped defaults. Effective values retain provenance
and can be reset.

## Consequences

- Defaults are versioned data and tested, not UI conditionals.
- Discovery improves setup but never authorizes scanning, deletion, or execution.
- Settings can explain why a value is active.
- A provider format change can be isolated to its catalog or adapter.

## Requirements impact

Requirements for settings and discovery must specify precedence, provenance, reset,
migration, validation, and the boundary between convenience and authorization.

## Validation

The versioned default source catalog proposes narrow Ollama, Hugging Face, Unsloth, and
`.models` roots, all disabled until consent; settings round-trip tests cover overrides.
