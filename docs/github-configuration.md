# GitHub Configuration

The repository starts private and is designed to become public without rewriting history.

## Initial private settings

- Default branch: `main`
- Pull requests required for shared development
- Required checks: `Build and test` and `Secret scan`
- Actions workflow permissions: read-only by default
- Paid Actions overages: disabled
- Private vulnerability reporting enabled when available
- Discussions, Pages, and public issue intake remain disabled until public launch

## Public launch

Before changing visibility, run a history, secret, personal-data, fixture-license,
trademark, and security audit. Then enable Discussions, Pages, public issue forms,
Dependabot, code scanning, secret scanning, push protection, and artifact attestations
where the GitHub plan supports them.

Repository settings that cannot be expressed as code must be recorded here with the date,
owner, and reason.

## Labels

Create and maintain at least these labels before public issue intake:

- Type: `bug`, `enhancement`, `documentation`, `provider`, `runtime`, `security`, `accessibility`
- Contribution: `good first issue`, `help wanted`
- Triage: `needs-triage`, `needs reproduction`
- Priority: `priority: critical`, `priority: high`, `priority: medium`, `priority: low`

Label creation, branch protection, Projects, Discussions, Pages, and repository visibility
are remote GitHub state. They are not implied by the presence of repository files.
