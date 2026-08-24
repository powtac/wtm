# Phase 1 Acceptance

Phase 1 is the read-only beta. It is accepted against Requirements 0.2.0, which
consolidates Phase 1 learnings into ADRs and adds stronger scan-generation and
repository-alias invariants. Inventory data remains ephemeral; only source consent,
bookmarks, volume identity, and UI preferences persist.

| Gate | Evidence |
|---|---|
| Provider and manual discovery | Ollama, Hugging Face, GGUF, Safetensors, and Unsloth fixtures plus adapter contract tests |
| External volumes | Stable APFS volume UUID/remount integration in `scripts/test-volume-lifecycle` and targeted unmount/remount app test |
| Permission recovery | First-run UI smoke plus denied, grant-again, revoke, stale, offline, and unreadable source tests |
| Scan-only boundary | `scripts/check-architecture` rejects action/runtime linkage, process execution, media frameworks, and known write APIs |
| Ephemeral normalized graph | Domain tests, source-settings round trip, and [ADR-005](decisions/ADR-005-ephemeral-phase-1-inventory.md); no inventory result is persisted |
| Identity and storage accounting | [ADR-018](decisions/ADR-018-evidence-first-reconciliation-and-storage.md), physical-ID deduplication, exclusive/shared/unknown storage tests, provider/manual reconciliation, and snapshot-root metadata rejection tests |
| Partial downloads | Synthetic Hugging Face fixture and a controlled interrupted `hf download` validated with `scripts/test-real-cache --expect-partial` on 2026-08-24 |
| Age and state | [ADR-019](decisions/ADR-019-timestamp-provenance-and-age.md), timestamp provenance, whole-unit age, `Old`, `Age Unknown`, and `Incomplete` presentation tests |
| Config and secret handling | Configuration allowlist, harmless-dotfile, secret-pattern, and Finder-target tests |
| Model cards | [ADR-020](decisions/ADR-020-confirmed-external-model-links.md), confirmed HTTPS-only link validation, canonical `owner/model`, reviewed shorthand alias, and unknown-owner negative contract tests |
| Extensibility | Immutable adapter registry, role-separated targets, data-driven Settings, and `docs/adapters.md` |
| Scan streaming | [ADR-017](decisions/ADR-017-streaming-full-rescan-generations.md), one coordinator, deterministic order, bounded events, cancellation, generation gating, and cancelled/replacement race regression |
| Product language | `scripts/check-language`; English string catalog and public documentation, with German normative requirements only |
| UI and accessibility | Fresh first-run labeled-control smoke through the macOS accessibility tree on local and ad-hoc CI signing |
| Distribution | Developer ID app beta, hardened runtime, notarization, stapling, and Gatekeeper evidence recorded below |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
./scripts/test-volume-lifecycle
./scripts/test-real-cache "$HOME/.cache/huggingface/hub"
```

## Distribution evidence

- Source commit: `956290d`
- Archive: `WTM Phase 1 Revalidated 2026-08-24 175531.xcarchive`
- Export: `/path/to/local/home/Desktop/WTM-0.1.0-Phase1-Revalidated.app`
- Version: `0.1.0 (1)`; bundle identifier: `de.powtac.whatthemodel`
- Architecture: Apple Silicon (`arm64`)
- Signing: `Developer ID signed (signer omitted)` with hardened runtime
- Entitlements: empty; App Sandbox remains disabled by accepted architecture decision
- Apple notarization: accepted on 2026-08-24; submission `767FBFE3-6FFF-4590-877B-AC32CB4D311E`
- Stapler: ticket validation succeeded
- Gatekeeper: accepted, source `Notarized Developer ID`
- Code-directory hash: `6106d7dc19bad8d35089637f0d07ad02ad727c8e`

The distributable DMG and public release automation remain Phase 5 scope.

## Requirements 0.2.0 revalidation findings

1. **Closed:** scan-generation UUID gating and a cancelled/replacement race regression
   satisfy FR-SCN-016.
2. **Closed:** deterministic fail-closed alias validation and negative collision/target
   tests satisfy FR-LNK-007.
3. **Closed:** a Developer ID archive from source commit `956290d` passed Apple
   notarization, stapler validation, and Gatekeeper assessment.

All Phase 1 findings are closed. Phase 1 is complete and release-ready against Requirements
0.2.0.
