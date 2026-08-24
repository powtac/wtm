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

Provider-aware deletion planning and verification. This capability starts in Phase 2 and
is not present in the Phase 1 target graph.

### Runtime adapter

Readiness, start, stop, and health verification. This capability starts in Phase 3 and
must use an executable plus an argument array, never a shell string.

### Client adapter

Handoff to a consuming application or endpoint. This capability starts in Phase 4.

## How to extend this list

Use Settings or a validated data manifest for paths, labels, safe HTTPS link templates,
and other data-only definitions. Data manifests cannot contain Swift binaries, dynamic
libraries, scripts, or executable command strings.

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
