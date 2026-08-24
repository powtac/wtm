# ADR-013: GitHub-Native Delivery

- Status: Accepted
- Date: 2026-08-24

## Context

WTM is intended to become a public open-source project and needs one visible workflow for
community input, code review, security, releases, documentation, and distribution.

## Decision

Use GitHub Issues, Discussions, Projects, Pull Requests, Actions, Releases, Security, and
Pages as the project operating model. Repository scripts are the local source of truth for
required CI checks; workflows call those scripts rather than duplicating build logic.

## Consequences

- Adapter proposals use structured issue forms and focused pull requests.
- Branch protection requires build/test and secret-scan checks when the plan supports it.
- Releases publish signed artifacts, checksums, notes, and later attestations.
- The website explains extension roles and links back to contribution workflows.

## Requirements impact

Repository requirements must separate features available while private from public-release
gates and must identify which checks are required, conditional, or unavailable on GitHub
Free/private repositories.

## Validation

Versioned community files, issue templates, workflows, scripts, and GitHub configuration
guidance exist in the repository.
