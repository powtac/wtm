# Architecture Decision Records

ADRs record durable product and architecture decisions. They explain why a constraint
exists; `REQUIREMENTS.md` remains the normative source for observable product behaviour.

## Lifecycle

- `Proposed`: under review and not binding.
- `Accepted`: binding for implementation and requirements.
- `Superseded`: retained for history and linked to its replacement.
- `Rejected`: considered but not selected.

Accepted ADRs are immutable in intent. A materially different decision requires a new ADR
that supersedes the old one. Clarifications and additional evidence may amend an existing
record without rewriting its history.

Every ADR contains context, decision, consequences, requirements impact, and validation.
Implementation changes that alter an accepted invariant must update or supersede the ADR
before merge.

## Decision index

| ID | Decision | Origin |
|---|---|---|
| [ADR-001](ADR-001-native-macos-stack.md) | Native Swift 6 macOS stack | Baseline |
| [ADR-002](ADR-002-direct-distribution.md) | Direct distribution outside the Mac App Store | Baseline |
| [ADR-003](ADR-003-release-trust-chain.md) | Developer ID release trust chain | Baseline, validated in Phase 1 |
| [ADR-004](ADR-004-platform-baseline.md) | Apple Silicon and macOS 15+ beta baseline | Baseline |
| [ADR-005](ADR-005-ephemeral-phase-1-inventory.md) | Ephemeral Phase 1 inventory | Baseline, validated in Phase 1 |
| [ADR-006](ADR-006-field-authority-and-provenance.md) | Field-specific authority and provenance | Baseline |
| [ADR-007](ADR-007-compiled-adapters-only.md) | Compiled, reviewed code adapters only | Baseline |
| [ADR-008](ADR-008-safe-process-invocation.md) | Process invocation without a shell | Baseline |
| [ADR-009](ADR-009-capability-separated-adapters.md) | Capability-separated adapter roles | Baseline |
| [ADR-010](ADR-010-non-sandboxed-least-privilege.md) | Non-sandboxed least-privilege access model | Baseline |
| [ADR-011](ADR-011-layered-conventions-and-overrides.md) | Defaults, discovery conventions, and user overrides | Baseline |
| [ADR-012](ADR-012-data-only-extension-manifests.md) | Data-only user extensions | Baseline |
| [ADR-013](ADR-013-github-native-delivery.md) | GitHub-native delivery | Baseline |
| [ADR-014](ADR-014-private-first-public-ready.md) | Private-first, public-ready repository | Baseline |
| [ADR-015](ADR-015-product-language-policy.md) | English product with German normative requirements | Baseline |
| [ADR-016](ADR-016-consent-bound-sources-and-volume-identity.md) | Consent-bound sources and stable volume identity | Phase 1 learning |
| [ADR-017](ADR-017-streaming-full-rescan-generations.md) | Streaming full-rescan generations | Phase 1 learning |
| [ADR-018](ADR-018-evidence-first-reconciliation-and-storage.md) | Evidence-first reconciliation and storage accounting | Phase 1 learning |
| [ADR-019](ADR-019-timestamp-provenance-and-age.md) | Timestamp provenance and age semantics | Phase 1 learning |
| [ADR-020](ADR-020-confirmed-external-model-links.md) | Confirmed external model links | Phase 1 learning |
| [ADR-021](ADR-021-phase-capability-isolation.md) | Compile-time phase capability isolation | Phase 1 learning |
| [ADR-022](ADR-022-no-unrelated-media-capabilities.md) | No unrelated media capabilities | Phase 1 learning |
| [ADR-023](ADR-023-revalidated-deletion-transactions.md) | Revalidated deletion transactions | Phase 2 boundary |

## Requirements revision checklist

When rewriting the requirements, derive each statement from the relevant ADR and keep:

1. a stable requirement ID and target phase;
2. one observable behaviour or invariant per requirement;
3. explicit evidence, scope, confidence, and fallback semantics where applicable;
4. a verification method or release gate;
5. negative requirements for security boundaries;
6. no implementation detail unless it is itself an accepted architectural constraint.
