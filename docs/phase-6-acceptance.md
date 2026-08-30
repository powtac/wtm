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
| Real source | Opt-in test against `/Users/powtac/.cache/huggingface/hub` produced a non-empty MLX inventory on 2026-08-26 |
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

The Phase 6 storage-only implementation is complete. Roadmap status remains `Implemented`
until the remaining Phase 5 release gates are closed. MLX runtime is not an acceptance gap:
FR-MLX-008 requires storage-only whenever the Python interpreter and package graph cannot be
revalidated fail-closed.
