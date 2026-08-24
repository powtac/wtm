# Roadmap

Phases are delivered in order. A phase is complete only after its implementation,
automated tests, manual gates, and distribution evidence are complete.

| Phase | Status | Gate |
|---|---|---|
| 0 — Foundation | Completed | Architecture, fixtures, CI including UI smoke, GitHub structure, Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper smoke are verified |
| 1 — Read-only Beta | Completed | Requirements 0.2.0 code gates and fresh Developer ID distribution evidence are verified |
| 2 — Safe Actions | Completed | Revalidated plans, provider actions, Trash, audit, targeted verification, recovery tests, and fresh notarized distribution are verified |
| 3 — Runtimes | Completed | Evidence-gated runtime checks, owned process lifecycle, tool definitions, automated gates, and fresh notarized distribution are verified |
| 4 — Integrations | Partially implemented | Native menu bar, separate login item, and reviewed OpenClaw/Unsloth handoffs are implemented; the normative MLX storage/runtime adapter and manual release evidence remain open |
| 5 — Stable Public Release | Implemented | DMG and Pages automation implemented; protected-environment release evidence and public community activation pending |
| 6 — Optional Downloads | Not started | Separate architecture and security decision required |

The normative scope and acceptance criteria are in
[Requirements (German, normative)](../REQUIREMENTS.md). Translations are convenience
copies only and are not maintained by the project.

Phase 4 is intentionally not marked complete: recognizing an `.mlx` suffix is not an MLX
storage/runtime adapter. A safe implementation must bind the Python interpreter and package
identity, prevent module-path injection and remote fallback downloads, and verify a local-only
health/inference path before execution.
