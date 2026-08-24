# Security Policy

## Supported versions

Security fixes are provided for the latest published release. The unreleased `main`
branch is supported on a best-effort basis.

## Reporting a vulnerability

Use GitHub private vulnerability reporting. Do not open a public issue and do not send
model files, credentials, or unredacted filesystem paths. Include the affected version,
impact, minimal reproduction, and suggested mitigation when known.

If private vulnerability reporting is unavailable while the repository is private,
contact the repository owner through an existing private channel. Public launch is
blocked until a monitored public security contact is documented.

Expect acknowledgement within seven days. No remediation deadline is guaranteed before
the first stable release.

## Security boundary

Phase 1 is read-only. Scanners must not start processes, execute shell content, mutate
provider stores, follow symlinks outside an approved root, or ingest secrets. See the
[threat model](docs/threat-model.md) for the normative engineering constraints.
