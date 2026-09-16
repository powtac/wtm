# Phase 6 Acceptance

Phase 6 is MLX Support. Its implemented scope is deliberately storage-only under
`REQUIREMENTS.md` FR-MLX-001 through FR-MLX-003 and FR-MLX-008 plus
[ADR-028](decisions/ADR-028-defer-mlx-to-a-dedicated-phase.md). No MLX runtime, Python
package installation, model download, training, remote bind, tunnel, or remote code path is
shipped.

| Gate | Evidence |
|---|---|
| Compiled boundary | `AdapterMLX` is a separate SwiftPM target implementing only `StorageProviderAdapter` and is registered by the app composition root |
| Structural identity | `config.json` must contain the MLX-LM quantization schema with bounded bit/group values and a recognized mode; generic Safetensors plus config remains unconfirmed |
| Completeness | Weights, indexed shards, partial suffixes, tokenizer artifacts, config, manifest, metadata, timestamps, and physical file identity are represented separately |
| Path safety | Read-only no-follow traversal, root containment, safe index filenames, bounded 2 MiB JSON reads, and strict Hugging Face cache-key parsing are applied |
| Read-only capability | MLX is absent from action/runtime adapters; cleanup preparation rejects selections containing an unsupported provider |
| Reconciliation | A structurally confirmed MLX installation supersedes only the generic overlapping view of the same physical artifact set |
| Explicit consent | Settings and first-run source setup expose `Add MLX Folder…`; no default broad MLX scan root is silently added |
| Fixtures | CC0 placeholder MLX fixtures and license records cover complete, false-positive, partial/missing-shard, and out-of-root-symlink cases |
| Real source | Opt-in test against `$HOME/.cache/huggingface/hub` produced a non-empty MLX inventory on 2026-08-26 |
| Automated verification | `./scripts/test` passed 114 package tests plus app/architecture/release/website gates; `./scripts/test-ui` passed 4 tests; the build-run entrypoint launched and verified WTM |
| Manual UI | `Settings > Sources` exposes `Add MLX Folder…`; Integrations lists MLX as `Built-in · Read-only` |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
WTM_REAL_MLX_SOURCE="$HOME/.cache/huggingface/hub" \
  swift test --package-path Packages/WTMKit --filter realMLXSourceIsInventoried
./script/build_and_run.sh --verify
```

## Acceptance result

Phase 5 is Completed under [ADR-031](decisions/ADR-031-deferred-manual-acceptance.md);
its former manual-gate dependency is closed. The Phase 6 storage gate is complete.

On 2026-09-09 the project owner requested starting the optional Phase 6 runtime gate.
Phase 6 is now In progress for that additional scope. The first milestone is an offline
interpreter/package preflight and review of the upstream loading and server contracts,
recorded in [MLX runtime gate](integrations/mlx-runtime.md).

MLX execution remains unavailable until FR-MLX-004 through FR-MLX-007 are verified.
FR-MLX-008 continues to require storage-only behavior whenever execution identity cannot be
fully revalidated; starting this work does not waive that boundary.
