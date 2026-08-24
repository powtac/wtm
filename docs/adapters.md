# Adapters

WTM separates storage discovery, destructive actions, runtimes, and client handoff. A
single external product may eventually implement several roles, but each capability has
its own protocol and release phase.

## Adapter types

### Storage provider adapter

Read-only inventory of provider manifests, physical artifacts, configuration files,
completeness, identity, and model-card evidence. Phase 1 ships Ollama and Hugging Face
storage adapters.

The Hugging Face adapter accepts an explicit repository-alias map for non-standard cache
directories that omit the owner. Built-in or reviewed data aliases may restore a confirmed
`owner/model` repository ID; an unknown short name never becomes a guessed model-card URL.
See [ADR-020](decisions/ADR-020-confirmed-external-model-links.md) for evidence, collision,
and fallback rules.

### Manual folder adapter

Conservative recognition of GGUF, Safetensors, and related configuration files in a
user-selected folder. It must not claim provider-specific semantics. If its scan root
overlaps a provider cache, WTM keeps the provider-backed installation for identical
artifact paths and suppresses only the generic duplicate.

### Storage action adapter

Provider-aware deletion planning, revalidation, and reviewed provider requests. Phase 2
ships separate action adapters for Ollama, Hugging Face, and manual folders. Adapters return
data-only operations; `ActionExecutor` owns plan lifetime, conflict detection, filesystem
identity checks, Trash dispatch, serialization, and audit.

Ollama uses its loopback delete API. Hugging Face builds a revision/reference graph and
offers a blob only after its final snapshot reference is selected. Manual cleanup excludes
shared, unknown-ownership, credential, identity, and secret-like files. See
[ADR-023](decisions/ADR-023-revalidated-deletion-transactions.md).

### Runtime adapter

Provider-specific readiness, immutable test plans, local health verification, and minimal
model inference. Phase 3 ships two compiled runtime adapters:

- Ollama uses `/api/tags`, `/api/ps`, and a bounded non-streaming `/api/generate` request on
  numeric loopback. It does not expose Stop because the daemon does not provide a
  WTM-exclusive process or loaded-model identity.
- llama.cpp accepts GGUF installations and produces a reviewed `llama-server` plan bound to
  `127.0.0.1`, an allocated port, and one exact model path. `RuntimeBroker`, not the adapter,
  starts and stops the owned process.

Runtime adapters never receive shell strings and never launch processes directly. They
return typed plans to the central broker. Compatibility, health, inference, and ownership
remain separate facts.

### Client adapter

Handoff to a consuming application or endpoint. This capability starts in Phase 4.

## How to extend this list

Use Settings or a validated data manifest for paths, labels, safe HTTPS link templates,
typed executable arguments, and other data-only definitions. Imported tool definitions are
fully previewed, disabled, assigned a new identity, and never inherit execution approval.
Export removes home-directory paths and validation evidence. Data manifests cannot contain
Swift binaries, dynamic libraries, scripts, deletion semantics, or shell command strings.

A new parser, provider API, deletion semantic, or process lifecycle requires a compiled
SwiftPM adapter:

1. Open an `Adapter proposal` issue.
2. State the role, provider versions, discovery roots, capabilities, and security risks.
3. Add synthetic or redistributable fixtures with explicit licenses.
4. Implement the smallest target that conforms to the relevant contract.
5. Add contract, malformed-input, path-boundary, and failure tests.
6. Update architecture, threat model, support matrix, and changelog.
7. Submit a focused pull request for review.

Compiled adapters become available only through a normal signed WTM release. WTM does
not load third-party runtime plugins. The capability boundary is defined by
[ADR-007](decisions/ADR-007-compiled-adapters-only.md),
[ADR-009](decisions/ADR-009-capability-separated-adapters.md), and
[ADR-012](decisions/ADR-012-data-only-extension-manifests.md).
