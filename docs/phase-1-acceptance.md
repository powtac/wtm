# Phase 1 Acceptance

Phase 1 is the read-only beta. This record maps the normative acceptance criteria in
`REQUIREMENTS.md` to executable evidence. Inventory data remains ephemeral; only source
consent, bookmarks, volume identity, and UI preferences persist.

| Gate | Evidence |
|---|---|
| Provider and manual discovery | Ollama, Hugging Face, GGUF, Safetensors, and Unsloth fixtures plus adapter contract tests |
| External volumes | Stable APFS volume UUID/remount integration in `scripts/test-volume-lifecycle` and targeted unmount/remount app test |
| Permission recovery | First-run UI smoke plus denied, grant-again, revoke, stale, offline, and unreadable source tests |
| Scan-only boundary | `scripts/check-architecture` rejects action/runtime linkage, process execution, media frameworks, and known write APIs |
| Ephemeral normalized graph | Domain tests, source-settings round trip, and ADR-005; no inventory result is persisted |
| Identity and storage accounting | Physical-ID deduplication, exclusive/shared/unknown storage tests, provider/manual reconciliation, and snapshot-root metadata rejection tests |
| Partial downloads | Synthetic Hugging Face fixture and a controlled interrupted `hf download` validated with `scripts/test-real-cache --expect-partial` on 2026-08-24 |
| Age and state | Timestamp provenance, whole-unit age, `Old`, `Age Unknown`, and `Incomplete` presentation tests |
| Config and secret handling | Configuration allowlist, harmless-dotfile, secret-pattern, and Finder-target tests |
| Model cards | Confirmed HTTPS-only link validation and Hugging Face card contract tests |
| Extensibility | Immutable adapter registry, role-separated targets, data-driven Settings, and `docs/adapters.md` |
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

- Archive: `WTM Phase 1 Final 2026-08-24 1715.xcarchive`
- Export: `/path/to/local/home/Desktop/WTM-0.1.0-Phase1.app`
- Version: `0.1.0 (1)`; bundle identifier: `de.powtac.whatthemodel`
- Architecture: Apple Silicon (`arm64`)
- Signing: `Developer ID signed (signer omitted)` with hardened runtime
- Apple notarization: accepted on 2026-08-24; submission `EEFB9151-B655-4BA5-BFFC-5D1FA05AE154`
- Stapler: ticket validation succeeded
- Gatekeeper: accepted, source `Notarized Developer ID`

The distributable DMG and public release automation remain Phase 5 scope.
