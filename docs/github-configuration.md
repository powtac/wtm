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

## Release environment

Create a protected Environment named `release` with required reviewer approval. Store only
these Environment secrets:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

`release.yml` accepts only a stable SemVer tag matching the Xcode project version. It uses
an ephemeral keychain and publishes a draft only after signing, notarization, DMG, SBOM,
checksum, secret-pattern, and start-smoke gates pass. Artifact attestation is enabled only
after the repository is public.

## Public launch

Before changing visibility, run a history, secret, personal-data, fixture-license,
trademark, and security audit. Then enable Discussions, Pages, public issue forms,
Dependabot, code scanning, secret scanning, push protection, and artifact attestations
where the GitHub plan supports them.

After visibility changes to public, set Pages source to **GitHub Actions**, approve the
`github-pages` Environment, run the Pages workflow, and verify all Settings extension links
against `https://powtac.github.io/wtm/extend.html`.

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
