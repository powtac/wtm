# Architecture

WTM is a native Swift 6 macOS application with a thin SwiftUI composition root and one
local Swift package. Phase 3 adds an isolated runtime graph to the inventory and safe-action
graphs. Client handoff and downloads remain absent.

```text
WTM app (composition and presentation only)
  -> WTMInventory -> WTMAdapterContracts, WTMDomain, WTMSecurity
  -> AdapterOllama, AdapterHuggingFace, AdapterManual
  -> WTMActions -> WTMAdapterContracts, WTMDomain, WTMSecurity
  -> ActionOllama, ActionHuggingFace, ActionManual
  -> WTMRuntime -> WTMAdapterContracts, WTMDomain
  -> RuntimeOllama, RuntimeLlamaCpp
  -> WTMPersistence
```

`WTMDomain` owns provider-neutral identities, variants, installations, artifacts,
timestamps, sources, action plans, runtime evidence, sessions, and tool definitions.
`WTMAdapterContracts` defines separate storage and runtime boundaries with immutable
registries. Concrete provider targets do not depend on each other.

The app target is the only composition root. It constructs discovery, action, and runtime
registries and injects them into `InventoryCoordinator`, `ActionExecutor`, and
`RuntimeBroker`. Views neither enumerate or mutate the file system nor create a `Process`.

Provider sources scan before generic manual sources. The inventory coordinator reconciles
overlapping artifact paths so provider-backed identity replaces a generic cache view while
distinct installation paths and volumes remain separate.

## Phase 3 runtime boundary

- `RuntimeAdapter` owns provider-specific compatibility, plan construction, local health
  contracts, and the minimal inference contract. It never owns an OS process handle.
- `RuntimeBroker` is the sole process-lifecycle authority. Only its reviewed launcher may
  use Foundation `Process`; the app, views, adapters, and persistence targets cannot.
- Ollama uses its numeric-loopback API for readiness and one-token inference. WTM does not
  claim ownership of the daemon or expose a provider Stop action.
- llama.cpp uses an absolute executable URL, a separate typed argument array, an explicit
  allowlisted environment, numeric loopback, and a WTM-owned `Process` handle.
- Static compatibility, runtime reachability, and successful model inference are separate,
  timestamped observations. A provider manifest or open port is never inference evidence.
- A test plan previews the executable, signature status, final arguments, endpoint, memory
  estimate, and stop semantics before execution. Readiness is checked first; an incompatible
  result exposes only an explicit secondary `Try Anyway` action.
- Executable approval is bound to canonical no-follow identity and the exact arguments,
  endpoint, working directory, environment, and adapter. Any change requires approval again.
- WTM stops only a process handle it created in the current app session. On app termination,
  it briefly delays termination to stop remaining WTM-owned processes; it never infers
  ownership from a port, process name, or model ID.
- Captured output is bounded, redacted, and in memory only. Runtime endpoints, state,
  sessions, and logs are not restored after relaunch.
- Tool manifests use a closed versioned schema. Imports receive a new identity, are fully
  previewed, remain disabled, replace the existing override for that runtime, and inherit no
  approval. Exports are disabled and omit validation evidence and home-directory paths.
- Shells, Terminal automation, inherited login environments, remote endpoints, dynamic
  libraries, scripts, and executable plugins remain forbidden.

The Phase 2 action boundary remains intact: actions use short-lived immutable plans,
no-follow identities, provider revalidation, centralized macOS Trash, explicit irreversible
confirmation, and bounded privacy-preserving audit entries.

## Persisted and ephemeral state

Versioned JSON under Application Support persists only operational source settings, user
preferences, tool definitions, and identity-bound tool approvals. Source URLs use macOS
bookmark data and external-volume UUID plus relative path. A stored runtime override
suppresses the discovered convention default for the same runtime, preventing duplicate
tool entries after relaunch.

Installations, artifacts, historical scan results, runtime sessions, endpoints, process
handles, inference output, and runtime logs are ephemeral. Provider files and live local
APIs remain the source of truth.

The app is directly distributed, is not sandboxed, requests neither Full Disk Access nor
elevated privileges, and preserves the explicit source-consent model.

`scripts/check-architecture` enforces the inventory/action/runtime splits, the single Trash
boundary, the single process-launch boundary, loopback-only HTTP ownership, and the remaining
forbidden capabilities in CI.

## Recorded invariants

The [ADR index](decisions/README.md) is the authoritative history for architecture choices.
Phase 1 invariants are recorded in
[ADR-016](decisions/ADR-016-consent-bound-sources-and-volume-identity.md) through
[ADR-022](decisions/ADR-022-no-unrelated-media-capabilities.md). Phase 2 transactions and
pane-scoped actions are governed by
[ADR-023](decisions/ADR-023-revalidated-deletion-transactions.md) and
[ADR-024](decisions/ADR-024-pane-scoped-inventory-actions.md). Phase 3 runtime ownership and
verification are governed by [ADR-025](decisions/ADR-025-owned-runtime-sessions.md).
Phase 4 menu projections and client trust boundaries are governed by
[ADR-026](decisions/ADR-026-passive-menu-bar-and-reviewed-client-handoffs.md).
Phase 5 release publication and private-to-public gates are governed by
[ADR-027](decisions/ADR-027-fail-closed-public-release-chain.md).

`REQUIREMENTS.md` defines observable behaviour. An accepted ADR explains the constraint;
neither document may silently contradict the other.
