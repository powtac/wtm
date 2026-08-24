# Phase 2 Acceptance

Phase 2 is Safe Actions. Its code and UI gates are accepted against Requirements 0.2.0.
The roadmap remains `In progress` until a fresh artifact from the final Phase 2 source
commit passes Developer ID signing, hardened runtime, notarization, stapling, and
Gatekeeper.

| Gate | Evidence |
|---|---|
| Reviewed plan | Immutable five-minute plan, one-time executor generation, complete native preview, irreversible confirmation, and preview/cancel UI test |
| Filesystem integrity | Lexical source containment, no-follow `lstat` identity, expiry, source-state, inode-replacement, symlink-swap, and 200 traversal-candidate tests |
| Shared storage | Hugging Face snapshot/reference graph, final-reference blob rule, fail-safe blob-last ordering, manual hardlink deduplication, and Ollama shared-blob accounting |
| Provider actions | Ollama loopback-only HTTP contract, `/api/ps` loaded-model block, official `DELETE /api/delete`, failure report, and fresh-plan recovery |
| Open files | macOS process-file inspection, blocking preview conflict, execution-time revalidation, and real open-fixture regression |
| Recovery and partial failure | Injected recoverable Trash fixture, provider retry, stop-after-failure semantics, and Hugging Face shared-blob retention |
| Read-only sources | External and local read-only volumes are rejected before a filesystem plan is offered |
| Post-action verification | App integration test proves preview, action, affected-source-only rescan, refreshed empty inventory, and audit update |
| Audit and privacy | Bounded JSON audit, redaction assertions, user-confirmed clearing, and no stored names, paths, provider payloads, credentials, or file contents |
| Capability boundary | `scripts/check-architecture` permits Trash only through `WTMActions`, local HTTP only in `ActionOllama`, and rejects raw delete, process, runtime, client, download, privileged-helper, and media capabilities |
| Product language | English-only app catalog and public documentation; German normative `REQUIREMENTS.md` |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
```

The 2026-08-24 local gate run passed 47 Swift-package tests, 18 app tests, the Release
build, all architecture/decision/fixture/language checks, and two native UI tests.
Destructive and recovery tests use injected mutation services and isolated temporary
directories only; they never target the user's model stores.

## Explicit limits

- Process-file inspection blocks positive matches but cannot claim visibility into macOS
  processes whose metadata the OS denies. The preview states this limitation.
- Reclaimable size is a deduplicated estimate. Free volume change is not an exact success
  signal; the provider state and targeted rescan are authoritative.
- Trash-backed operations are recoverable through Finder. Ollama provider deletion is
  irreversible and requires a separate confirmation.

## Distribution evidence

Pending a fresh Developer ID archive from the final Phase 2 source commit. Phase 2 is not
marked complete until that exact artifact lineage passes notarization, stapling, and
Gatekeeper validation.
