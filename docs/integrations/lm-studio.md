# LM Studio storage contract

Reviewed on 2026-09-08. This checkout adds a compiled read-only storage adapter;
it is not part of the already-published WTM 0.4.3 binary.

The official [import layout](https://lmstudio.ai/docs/app/advanced/import-model) is
`~/.lmstudio/models/<publisher>/<model>/<file>.gguf`. A relocated root must be
selected and approved explicitly. [Apple Silicon and macOS 14+](https://lmstudio.ai/docs/app/system-requirements)
are documented by LM Studio; WTM retains its own macOS 15 minimum.

| Capability | Contract |
|---|---|
| Inventory | Disabled source suggestion; consent-bound traversal and bounded GGUF v2/v3 header inspection |
| Identity | Relative import path distinguishes equal filenames in different directories; folder names never create a confirmed Hub link |
| Completeness | Stored means observed on disk, not verified inference or full tensor validation; tensorless GGUF remains incomplete |
| Shared artifacts | Retains physical file identity from the common metadata reader; in-scope links are supported, out-of-scope links are rejected |
| Partial / unknown | `.incomplete` remains Unknown/incomplete; unsupported layouts, Safetensors and split GGUF remain Unknown/issue |
| Provider metadata | No stable provider index is required by the documented GGUF import convention; model.yaml presets and remote catalogs are not installation evidence |
| Cleanup / runtime | No LM Studio deletion, API request, model loading, process start or Stop is added |

The supported boundary is the documented GGUF import convention as reviewed above, not
all files produced by every LM Studio release. Changed layouts and new formats need new
fixtures and review. Other temporary-file conventions are not classified as complete
models; only header-validated `.gguf` candidates can receive the GGUF format.

Contract tests generate tiny synthetic GGUF headers in disposable directories. They
exercise malformed contents, unknown layout, split files, partial artifacts, hard links,
and a symlink outside the approved source. They include no downloaded model weights.
The implementation reuses the shared bounded directory walker, GGUF reader and path-identity
checks. Unknown candidates retain the LM Studio provider ID, which has no action
adapter, so fallback cannot enable generic cleanup.

The [versioned integration catalog](catalog.json) records the remaining first-wave roles
and evidence gaps. Catalog URLs are reference data and are never queried during a scan.
