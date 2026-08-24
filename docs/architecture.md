# Architecture

WTM is a native Swift 6 macOS application with a thin SwiftUI composition root and one
local Swift package. The Phase 1 product graph is read-only by construction.

```text
WTM app
  -> WTMInventory
      -> WTMAdapterContracts
      -> WTMDomain
      -> WTMSecurity
  -> AdapterOllama
  -> AdapterHuggingFace
  -> AdapterManual
```

`WTMDomain` owns provider-neutral identities, variants, installations, artifacts,
timestamps, sources, and issues. `WTMAdapterContracts` defines the storage-provider
boundary and immutable registry. Concrete provider targets do not depend on each other.

The app target is the only composition root. It constructs the registry and injects it
into `InventoryCoordinator`. Views never enumerate the file system directly.

Operational source settings are stored as a versioned JSON document under Application
Support. Folder URLs use macOS bookmark data and external-volume UUID plus relative path.
The store never contains installations, artifacts, or historical scan results.

## Phase 1 security boundary

- No action, runtime, client, or process-launch target is linked.
- Adapters expose inventory results only.
- Scan roots require explicit user enablement.
- Directory traversal resolves symlinks and rejects destinations outside the configured root.
- Files are opened through read-only APIs; weight files are never hashed during a normal scan.
- Model inventory is ephemeral and rebuilt on every launch. Only source bookmarks, consent,
  source order, scan-on-launch, and UI preferences persist.
- Provider files remain the sole source of truth.
- The app is not sandboxed, but it does not request Full Disk Access or elevated privileges.

`scripts/check-architecture` enforces the most important negative dependencies and
forbidden capabilities in CI.
