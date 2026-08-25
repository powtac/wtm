# Roadmap

Phases are delivered in order. A phase is complete only after its implementation,
automated tests, manual gates, and distribution evidence are complete.

| Phase | Status | Gate |
|---|---|---|
| 0 — Foundation | Completed | Architecture, fixtures, CI including UI smoke, GitHub structure, Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper smoke are verified |
| 1 — Read-only Beta | Completed | Requirements 0.2.0 code gates and fresh Developer ID distribution evidence are verified |
| 2 — Safe Actions | Completed | Revalidated plans, provider actions, Trash, audit, targeted verification, recovery tests, and fresh notarized distribution are verified |
| 3 — Runtimes | Completed | Evidence-gated runtime checks, owned process lifecycle, tool definitions, automated gates, and fresh notarized distribution are verified |
| 4 — Integrations | Implemented | Native menu bar, separate login item, and reviewed OpenClaw/Unsloth handoffs are implemented; manual integration/release evidence remains open |
| 5 — Stable Public Release | Implemented | DMG and Pages automation implemented; protected-environment release evidence, public community activation, About/download links, and weekly update-check UX remain open |
| 6 — MLX Support | Not started | Read-only compiled storage adapter first; runtime requires the separate interpreter/package trust gate in ADR-028 |

The normative scope and acceptance criteria are in
[Requirements (German, normative)](../REQUIREMENTS.md). Translations are convenience
copies only and are not maintained by the project.

Phase 4 is implementation-complete but does not become `Completed` until its manual evidence
is recorded in [Phase 4 Acceptance](phase-4-acceptance.md). Phase 5 implementation and
automated gates are recorded in [Phase 5 Acceptance](phase-5-acceptance.md), while its
protected public-launch evidence remains open. Phase 5 also owns the WTM application update path: a weekly, privacy-preserving
check against the stable GitHub Release plus manual `Check for Updates…` and
`Download Latest Release` links in About, Settings, the app menu, website, and README.
Provider- and model acquisition are currently backlog and have no committed shipping phase.
ADR-028 moves MLX into Phase 6 because recognizing
an `.mlx` suffix is not an inventory adapter and Python execution introduces a separate
interpreter/package boundary. Phase 6 may ship storage-only. No later shipping phase is
committed; later ideas remain backlog until separately accepted.
