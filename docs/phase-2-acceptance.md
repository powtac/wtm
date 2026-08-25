# Phase 2 Acceptance

Phase 2 is Safe Actions. Its code, UI, and distribution gates are accepted against
Requirements 0.2.0.

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

- Build source commit: `93a298c`
- Archive: `WTM Phase 2 2026-08-24 191300.xcarchive`
- Export: local path intentionally omitted
- Version: `0.2.0 (2)`; bundle identifier: `de.powtac.whatthemodel`
- Architecture: Apple Silicon (`arm64`)
- Signing: Developer ID signed with signer identity omitted; hardened runtime
- Entitlements: empty; App Sandbox remains disabled by accepted architecture decision
- Apple notarization: accepted on 2026-08-24; submission
  `AAE0C8AD-32A3-4FF4-B2D9-1777E1807C61`
- Stapler: ticket validation succeeded
- Gatekeeper: accepted, source `Notarized Developer ID`
- Launch smoke: notarized export remained running until controlled termination
- Code-directory hash: `7dc43fdfa519aeb92b1c9518b0cf780afa89d598`
- Executable SHA-256:
  `8f7735ba10ea02b7a6e5799a5fdf69199194ecd702dd1eabe4b4e41940ea1de6`

The distributable DMG and public release automation remain Phase 5 scope. All Phase 2
findings are closed; Phase 2 is complete.
