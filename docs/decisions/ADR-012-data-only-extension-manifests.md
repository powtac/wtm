# ADR-012: Data-Only Extension Manifests

- Status: Accepted
- Date: 2026-08-24

## Context

Users need configurable sources, tools, clients, and link rules without turning Settings
or imported files into an arbitrary code execution mechanism.

## Decision

User extensions are versioned, schema-validated data. They may describe paths, labels,
HTTPS templates, executable references, typed arguments, and allowlisted environment keys
for capabilities implemented by WTM. They may not contain executable payloads, scripts,
shell strings, dynamic libraries, hidden network requests, parsers, or deletion semantics.
Imported manifests are fully previewed, provenance-labelled, and disabled by default.

## Consequences

- Data can configure an existing capability but cannot create a new capability.
- A digest detects change but does not establish publisher trust.
- Unknown future schema versions fail closed or remain inspectable without activation.
- Secrets and personal absolute paths are excluded from export by default.

## Requirements impact

Manifest requirements must define schema versioning, allowed fields, validation limits,
provenance, import/export redaction, activation, migration, and failure behaviour.

## Validation

Each manifest type requires schema and negative fixtures before shipping. Code-level
extensions continue through ADR-007.
