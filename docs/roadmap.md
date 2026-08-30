# Roadmap

Phases are delivered in order. A phase is complete only after its implementation,
automated tests, manual gates, and distribution evidence are complete.

| Phase | Status | Gate |
|---|---|---|
| 0 — Foundation | Completed | Architecture, fixtures, CI including UI smoke, GitHub structure, Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper smoke are verified |
| 1 — Read-only Beta | Completed | Requirements 0.2.0 code gates and fresh Developer ID distribution evidence are verified |
| 2 — Safe Actions | Completed | Revalidated plans, provider actions, Trash, audit, targeted verification, recovery tests, and fresh notarized distribution are verified |
| 3 — Runtimes | Completed | Evidence-gated runtime checks, owned process lifecycle, tool definitions, automated gates, and fresh notarized distribution are verified |
| 4 — Integrations | Completed | Native menu bar, independent login item, reviewed OpenClaw/Unsloth handoffs, manual UI evidence, and notarized distribution evidence are verified |
| 5 — Stable Public Release | Implemented | Public v0.4.0, Pages, protected release environment, notarized DMG, SBOM, checksum, attestation, and 2026-08-30 security disposition are verified; VoiceOver and final history/PII/trademark evidence remain open |
| 6 — MLX Support | Implemented | Compiled read-only MLX-LM storage inventory is verified; runtime remains deliberately blocked by the interpreter/package trust gate in ADR-028 |

The normative scope and acceptance criteria are in
[Requirements (German, normative)](../REQUIREMENTS.md). Translations are convenience
copies only and are not maintained by the project.

Phase 4 evidence is recorded in [Phase 4 Acceptance](phase-4-acceptance.md). Phase 5's
public launch and remaining acceptance gaps are recorded in
[Phase 5 Acceptance](phase-5-acceptance.md). Phase 5 also owns the WTM application update path: a weekly, privacy-preserving
check against the stable GitHub Release plus manual `Check for Updates…` and
`Download Latest Release` links in About, Settings, the app menu, website, and README.
Provider- and model acquisition are currently backlog and have no committed shipping phase.
ADR-028 moves MLX into Phase 6 because recognizing
an `.mlx` suffix is not an inventory adapter and Python execution introduces a separate
interpreter/package boundary. The storage-only implementation and its evidence are recorded
in [Phase 6 Acceptance](phase-6-acceptance.md). No later shipping phase is
committed; later ideas remain backlog until separately accepted.
