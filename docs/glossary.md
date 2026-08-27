# WTM glossary

This is the canonical public vocabulary for What The Model (WTM). UI labels use
title case as shown in the app. Code names are shown in backticks. Use these
terms in documentation, issues, screenshots, and support requests.

WTM is a local model inventory. It is not a general disk scanner, model
download service, inference host, or client configuration manager.

## App map

| UI part | Canonical name | Meaning |
| --- | --- | --- |
| Whole app | What The Model; WTM | The product. The public category is **Local LLM Inventory for macOS**. |
| Main window | Inventory window | The three-column window containing scopes, the model list, and model details. |
| Left column | Inventory sidebar | The list of inventory scopes. `Settings…` is a separate footer action, not an inventory scope. |
| Middle column | Inventory list; model table | The current scan result, shown as model rows. |
| Right column | Detail pane | Details and actions for the selected model or selection. “Inspector” is an informal synonym. |
| Top of the list | List controls | `Scan Now`/`Rescan`, search, and filters. |
| Below list controls | Scan status or scan summary | Live progress while scanning, or the last completed/cancelled scan result. |
| Above the table | Storage controls | Shared/unknown storage categories and the total for the active inventory scope. |
| Native preferences window | Settings | The five top-level panes: `General`, `Sources`, `Integrations`, `Security`, and `Advanced`. |

## Inventory sidebar scopes

| UI label | Definition |
| --- | --- |
| `All Models` | Every discovered model installation in the current inventory, subject to search and filters. |
| `Old` | Installations whose earliest available change evidence is older than the configurable `Old after` threshold. |
| `Age Unknown` | Installations with no usable earliest change timestamp. |
| `Incomplete` | Installations for which the scanner found partial or incomplete model evidence. |
| `Issues` | The latest scan's `InventoryIssue` records, such as source access, enumeration, or malformed metadata errors. It is separate from installations whose state is `Model Issue`. |

Search and the `Source Type`, `Format`, `State`, and `Source` filters narrow the
selected inventory scope. `Show All Models` clears that view back to `All
Models`; it does not run another scan.

## Inventory data

| Term | Definition |
| --- | --- |
| Scan | A read-only inspection of explicitly enabled and authorized source roots. |
| Inventory | The ephemeral, normalized result built from the latest scan. It is rebuilt from provider files and local APIs; model results are not persisted. |
| Source | One user-approved scan root, such as a Hugging Face cache or a manually selected folder. A source has a source type, optional provider role, path, volume identity, and access state. |
| Source root | The exact directory boundary WTM may inspect for a source. WTM must not silently widen it to the home directory or a parent cache. |
| Provider | A known storage convention and its read-only inventory adapter, for example Ollama, Hugging Face, or MLX. |
| Manual folder | A generic source scanned for recognizable model files without claiming provider ownership. It is a source type and adapter role, not a model provider. |
| Model identity | The logical model, independent of one local copy or file format; code type `ModelIdentity`. |
| Model variant | One representation of an identity, including format and optional quantization; code type `ModelVariant`. |
| Model installation | One detected identity/variant at one source and path; code type `ModelInstallation`. It means “found locally”, not “complete”, “compatible”, “loaded”, or “running”. |
| Artifact | A physical file or provider object belonging to an installation: weights, manifest, configuration, tokenizer, metadata, or an unknown item. |
| Model card | A confirmed external documentation link for the model. WTM does not guess an unknown model-card URL. |

## Storage and size

| Term | Definition |
| --- | --- |
| Logical size | The sum of file sizes as represented by the source. |
| Allocated Size | The physical disk allocation attributed to the installation. It remains available in model details; the list uses `Inventory Share`. |
| Exact Bytes | The exact allocated byte count shown in the detail pane. |
| `Inventory Share` | Show each row's exclusively attributable allocated bytes as a percentage of the active scanned inventory. |
| Shared | Physical storage referenced by more than one installation. It is counted separately to avoid double-counting. |
| Unknown | Physical storage whose ownership cannot be established safely. |
| Reclaimable | Storage that a reviewed cleanup plan may remove after dependency, identity, and in-use checks. It is an estimate until the action completes. |
| Active scanned inventory | The set of installations and storage currently included by the selected scope and latest scan. |

## States and evidence

### Installation states

| UI state | Definition |
| --- | --- |
| `Stored` | Model data is present on local storage and was inventoried. It does not claim runtime compatibility or successful inference. |
| `Incomplete` | Required or expected evidence is partial, missing, or still downloading. |
| `Model Issue` | The installation has a model-specific problem recorded by the adapter. |
| `Offline` | The installation is known from inventory but its source or volume is currently unavailable. |

### Source access states

| UI state | Definition |
| --- | --- |
| `Not Set Up` | The source has not been authorized for scanning. |
| `Allowed` | The current source root and its consent-bound identity are valid. |
| `Limited` | Access is intentionally narrower than a normal full source approval. |
| `Denied` | The current user permissions do not allow reading the source. |
| `Offline` | The source volume or path is unavailable. |
| `Stale` | The saved approval no longer proves the current source identity; access must be granted again. |

### Runtime evidence

`Runtime Verification` is a detail-pane section, not an installation state. It
keeps separate observations for:

- `Integrity`: whether the model files are structurally complete or corrupt.
- `Compatibility`: whether a selected runtime can use the format, architecture,
  and available memory.
- `Validation`: whether a runtime was reached and, separately, whether a real
  minimal inference request succeeded.
- `Runtime State`: whether a concrete instance is stopped, starting, running,
  stopping, or failed.
- `Ownership`: whether WTM started the process or a provider manages it.

`Loaded` describes runtime memory, not storage presence. `Running` describes a
runtime instance, not a model's inventory state. `Usable` must not be used as a
synonym for either one.

## Detail pane sections

| UI label | Definition |
| --- | --- |
| Model facts | Provider, format, allocated size, exact bytes, path, age, and age basis. |
| `Artifacts` | The files/provider objects that make up the installation, including `Shared` and `Unknown` markers. |
| `Configurations` | Configuration files associated with the installation. |
| `Reveal in Finder` | Opens a selected local path; it does not change inventory or source access. |
| `Runtime Verification` | Static/runtime evidence and the explicit `Run Test` flow for a compatible runtime. |
| `Clients` | Reviewed handoff options for consuming applications such as OpenClaw or Unsloth Studio. |
| Cleanup review | An explicit preview of selected models, operations, retained dependencies, conflicts, and estimates before an action. |
| Runtime test preview | A modal review of executable, arguments, endpoint, memory estimate, and stop behavior before launch. |
| Client handoff preview | A modal review of the exact client executable and argument vector before launch. |

## Settings panes

| Pane | Contains |
| --- | --- |
| `General` | Scan on Launch, update checks, menu-bar projection, login item, and the `Old after` threshold. |
| `Sources` | Enabled source roots, manual/MLX folder selection, and mounted-volume information. |
| `Integrations` | `Runtime Tools`, `Storage Providers`, and reviewed `Clients`. |
| `Security` | Per-source access renewal/removal and the bounded action audit. |
| `Advanced` | Ephemeral inventory explanation, extension guidance, and reset-to-defaults. |

## Adapter roles

| Role | Definition |
| --- | --- |
| `StorageProviderAdapter` | Read-only discovery of provider identities, artifacts, configurations, completeness, and evidence. |
| `ManualFolderAdapter` | Conservative file-format recognition inside a user-approved generic folder. |
| `StorageActionAdapter` | Provider-aware cleanup planning. It does not own the central transaction or Trash boundary. |
| `RuntimeAdapter` | Runtime compatibility, immutable test-plan construction, health checks, and minimal inference contracts. |
| `Runtime Tool` | A configured executable definition used by a runtime adapter, including path, arguments, approval, and validation. |
| `ClientAdapter` | A reviewed, short-lived handoff to a consuming application or endpoint. |
| `Storage Provider` | The Settings role for registered storage discovery adapters. It is not a runtime or client. |

## Remaining inconsistencies

These are real implementation/documentation mismatches found while creating
this glossary. They are recorded here so users do not infer the wrong meaning.

| Location | Inconsistency | Canonical direction |
| --- | --- | --- |
| `Offline` | The same word is used for an installation state and a source access state. | Keep the labels but qualify them in help/docs as `Installation: Offline` versus `Source: Offline`. |
| Format values | `Ollama` is exposed as a `ModelFormat`, although Ollama is primarily a storage/provider convention rather than a file format. | Prefer `Representation` or `Storage representation` for that field, or explain why provider-backed Ollama variants use the value. |
| Runtime terminology | The detail pane says `Runtime Verification`, Settings says `Runtime Tools`, and the architecture says `RuntimeAdapter`. | Keep all three only when the role is explicit: verification = evidence, tool = executable definition, adapter = implementation. |
| Scan result counts | The log says `installations`, the UI says `found`, and the sidebar says `models`. | Use `model installations found` in logs and docs; reserve `model` for the logical identity. |

The glossary describes the current behavior and does not silently redefine it.
Behavioral changes should update this file, the website glossary, the relevant
requirements/ADR, and tests together.
