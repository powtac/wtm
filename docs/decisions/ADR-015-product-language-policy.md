# ADR-015: Product Language Policy

- Status: Accepted
- Date: 2026-08-24

## Context

The product and public community target an international audience, while internal product
reasoning and stakeholder requirements are authored in German. Maintaining two normative
translations would create divergence.

## Decision

Use English for the app, website, README, technical documentation, ADRs, code, issues,
pull requests, releases, and community communication. Keep `REQUIREMENTS.md` as the single
normative German exception. Do not maintain a second normative translation.

## Consequences

- English translations of requirements may be convenience artifacts only.
- User-facing string literals must use the String Catalog.
- Provider metadata may retain official names but must not introduce product copy in
  another language.

## Requirements impact

Language requirements must identify the normative document, public surfaces, localization
readiness, and automated checks without implying that German product UI is shipped.

## Validation

`scripts/check-language` and UI smoke tests protect the English product surface.
