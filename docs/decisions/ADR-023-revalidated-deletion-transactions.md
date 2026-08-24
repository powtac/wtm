# ADR-023: Revalidated Deletion Transactions

- Status: Accepted
- Date: 2026-08-24

## Context

Phase 2 introduces the first destructive capability. Inventory observations can become stale,
paths can be replaced between preview and execution, symbolic links can change targets, and
provider caches can share physical data. A confirmation dialog alone does not make deletion
safe.

## Decision

All cleanup runs through `ActionExecutor` using a short-lived, immutable deletion plan. A
compiled `StorageActionAdapter` creates provider-specific operations from the current
ephemeral inventory. Every file target records its source boundary and no-follow filesystem
identity. Immediately before execution, the executor revalidates plan generation, expiry,
source consent, path containment, filesystem identity, shared-reference state, provider
state, and unresolved batch conflicts.

Manual files and provider cache files use the macOS Trash through one injected system
service. Raw permanent filesystem deletion is forbidden. Hugging Face plans operate on
revisions, refs, and blobs proven unreferenced by remaining snapshots; they never delete a
blob merely because one model references it. Ollama deletion uses its loopback API, is
classified as irreversible, is blocked while the model is reported loaded, and requires a
separate explicit confirmation.

Batch plans are built provider-wise and combined into a conflict graph before preview.
Execution is serialized. Partial failure stops subsequent operations and produces a
per-operation result. A bounded, local audit stores only time, action kind, adapter, counts,
and outcome; it stores no paths, model names, command payloads, credentials, or file
contents, and the user can clear it.

## Consequences

- A preview cannot be reused after its generation expires or inventory/source state changes.
- Trash-backed actions are recoverable through Finder; provider API deletion is not presented
  as recoverable.
- Expected reclaimable storage remains a conservative estimate, never proof of free-space
  change.
- Provider action targets are linked in Phase 2, while process, runtime, client, download,
  privileged-helper, and raw-delete capabilities remain absent.
- Tests use injected mutation services and isolated temporary directories; they never target
  real user model stores.

## Requirements impact

This decision implements `FR-DEL-001` through `FR-DEL-011`, `SEC-005`, `SEC-006`,
`NFR-REL-003`, `NFR-REL-005`, and the Phase 2 gates in section 18. It does not weaken source
consent or authorize access outside configured roots.

## Validation

Unit and contract tests cover reference graphs, shared targets, irreversible confirmation,
expiry, stale generations, path escape, symlink replacement, inode replacement, partial
failure, audit redaction, provider recovery, and targeted post-action rescans. Architecture
checks allow Trash only in `WTMActions`, provider mutation only through compiled action
adapters, and continue to reject raw deletion, shells, runtime, client, and download code.
