# Architecture

WTM is a native Swift 6 macOS application with a thin SwiftUI composition root and one
local Swift package. Phase 2 adds a capability-isolated cleanup graph to the read-only
inventory graph.

```text
WTM app
  -> WTMInventory
      -> WTMAdapterContracts
      -> WTMDomain
      -> WTMSecurity
  -> AdapterOllama
  -> AdapterHuggingFace
  -> AdapterManual
  -> WTMActions
      -> WTMAdapterContracts
      -> WTMDomain
      -> WTMSecurity
  -> ActionOllama
  -> ActionHuggingFace
  -> ActionManual
  -> WTMPersistence
```

`WTMDomain` owns provider-neutral identities, variants, installations, artifacts,
timestamps, sources, and issues. `WTMAdapterContracts` defines the storage-provider
boundary and immutable registry. Concrete provider targets do not depend on each other.
Provider sources are scanned before generic manual sources. The coordinator reconciles
overlapping artifact paths so provider-backed identity replaces a generic cache view,
while distinct installation paths and volumes remain separate.

The app target is the only composition root. It constructs separate discovery and action
registries and injects them into `InventoryCoordinator` and `ActionExecutor`. Views never
enumerate or mutate the file system directly.

Operational source settings are stored as a versioned JSON document under Application
Support. Folder URLs use macOS bookmark data and external-volume UUID plus relative path.
The store never contains installations, artifacts, or historical scan results.

## Phase 2 security boundary

- Read-only adapters still expose inventory results only; destructive semantics live in
  separately registered compiled action adapters.
- Every action uses a short-lived immutable plan and no-follow filesystem identities.
- `ActionExecutor` revalidates plan generation, expiry, source state, target identity,
  provider state, and batch conflicts immediately before mutation.
- Manual and Hugging Face filesystem actions use the macOS Trash through one injected
  service. Raw permanent filesystem deletion is absent.
- Ollama deletion uses only its loopback API and requires irreversible confirmation.
- Runtime, client, process-launch, download, and privileged-helper targets remain absent.
- Scan roots require explicit user enablement.
- Directory traversal resolves symlinks and rejects destinations outside the configured root.
- Files are opened through read-only APIs; weight files are never hashed during a normal scan.
- Model inventory is ephemeral and rebuilt on every launch. Only source bookmarks, consent,
  source order, scan-on-launch, and UI preferences persist.
- Provider files remain the sole source of truth.
- The app is not sandboxed, but it does not request Full Disk Access or elevated privileges.

`scripts/check-architecture` enforces the inventory/action split, the single Trash boundary,
and the remaining forbidden capabilities in CI.

## Recorded invariants

The [ADR index](decisions/README.md) is the authoritative history for architecture choices.
Phase 1 implementation specifically validated:

- consent-bound roots and external-volume identity ([ADR-016](decisions/ADR-016-consent-bound-sources-and-volume-identity.md));
- isolated streaming scan generations ([ADR-017](decisions/ADR-017-streaming-full-rescan-generations.md));
- provider-first reconciliation and physical storage accounting ([ADR-018](decisions/ADR-018-evidence-first-reconciliation-and-storage.md));
- timestamp provenance and age semantics ([ADR-019](decisions/ADR-019-timestamp-provenance-and-age.md));
- confirmed external model links ([ADR-020](decisions/ADR-020-confirmed-external-model-links.md)); and
- compile-time phase boundaries ([ADR-021](decisions/ADR-021-phase-capability-isolation.md)).

Phase 2 cleanup transactions are governed by
[ADR-023](decisions/ADR-023-revalidated-deletion-transactions.md).

`REQUIREMENTS.md` defines observable behaviour. An accepted ADR explains the constraint;
neither document may silently contradict the other.
