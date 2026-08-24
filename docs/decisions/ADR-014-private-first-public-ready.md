# ADR-014: Private-First, Public-Ready

- Status: Accepted
- Date: 2026-08-24

## Context

The repository begins private on GitHub Free but is planned for public release. Retrofitting
licenses, fixture rights, secret hygiene, language, and community structure after history
is public is costly and sometimes irreversible.

## Decision

Treat every commit as publication-ready from the start. Use Apache-2.0, redistributable or
synthetic fixtures with licenses, no personal paths or credentials, English public content
except the normative German requirements, and public-ready community/security files.

## Consequences

- Private history is not a license to commit secrets or non-redistributable model data.
- CI cost and GitHub-plan limitations are documented rather than bypassed silently.
- Public activation still needs a dedicated history, trademark, security, and release audit.

## Requirements impact

Public-release requirements must include repository-history scanning, fixture provenance,
license notices, trademark review, security policy activation, and artifact verification.

## Validation

Fixture-license, language, secret-scan, build, and test checks are versioned; public release
remains a later phase gate.
