# MLX runtime gate

Status: In progress, started 2026-09-09 after Phase 5 closed under ADR-031.
The [Phase 6 storage gate](../phase-6-acceptance.md) is complete. This work addresses the
optional runtime gate in FR-MLX-004 through FR-MLX-008; no MLX execution is enabled yet.

## First milestone: offline preflight

`scripts/probe-mlx-environment.py` reports the explicitly selected interpreter's standard
site-packages metadata without importing third-party packages or executing startup hooks.
Run it with that interpreter's absolute path and `-I -S`:

```sh
/absolute/path/to/python3 -I -S scripts/probe-mlx-environment.py
```

The report distinguishes observed distribution-directory names, readable metadata and
packages not observed in the inspected roots. Symlinked, unreadable or oversized metadata
is unverified rather than evidence of absence. The result always says `runtimeEnabled: false`:
metadata discovery is not dependency resolution, integrity verification or launch approval.
The named package list is an initial discovery set, not the transitive dependency closure.
No model scan, package installation, runtime launch or network request occurs.

The local probe used Homebrew Python 3.14.7 on 2026-09-09. It observed an
`mlx-0.32.1.dist-info` candidate whose metadata was not verified; `mlx-lm`, Transformers,
Tokenizers and Hugging Face Hub were not observed in that interpreter's standard package
root. Other interpreters or environments were not inspected. Local evidence is in
`build/mlx-runtime-review/environment.json`; machine-specific paths are kept out of this note.

Four synthetic tests cover metadata-only discovery, absence of package/hook execution,
symlink rejection and oversized metadata. They pass and run through `scripts/test`:

```sh
./scripts/run-logged build/mlx-runtime-review/probe-tests.log   /absolute/path/to/python3 -I -S scripts/tests/test_mlx_environment_probe.py
```

## Upstream contract review

Reviewed source revision: `ee19be43625b9385f979de6133938f683aba6e8e`.

- The [server's ModelProvider](https://github.com/ml-explore/mlx-lm/blob/ee19be43625b9385f979de6133938f683aba6e8e/mlx_lm/server.py)
  accepts different model, adapter and draft-model paths. A future WTM request boundary must
  lock these to the approved installation instead of exposing unrestricted model selection.
- The [model loader](https://github.com/ml-explore/mlx-lm/blob/ee19be43625b9385f979de6133938f683aba6e8e/mlx_lm/utils.py)
  downloads when a requested local path does not exist. It also has a separately enabled
  custom model-code path. WTM must reject missing/nonlocal inputs and keep custom code off;
  a filename check alone is insufficient.
- Python's [isolated and no-site flags](https://docs.python.org/3/using/cmdline.html)
  help exclude ambient import configuration. They do not bind the package graph, native
  libraries, interpreter resources or mutable files after inspection.

The existing WTM launcher stages verified individual executables/resources. It does not yet
bind and stage a Python runtime's complete dependency graph. Its current identity approval
must not be interpreted as MLX execution approval.

## Remaining runtime milestones

| Gate | Required result | Status |
|---|---|---|
| Environment discovery | Offline diagnostic, explicit interpreter, negative fixtures | Completed for the inspected interpreter |
| Execution identity | Bind interpreter, stdlib, entry point, transitive Python/native dependencies and model resources; detect replacement and prevent post-check substitution | Open |
| Local-only loading | Approved canonical model directory, no missing-path Hub fallback, no custom model code, no alternate model/adapter/draft selection | Open |
| Broker and presentation | Reviewed plan, explicit environment, numeric loopback, owned process and Stop, bounded logs and cancellation | Open |
| Runtime acceptance | Mutation/import-injection tests, port/ownership/lifecycle tests and real one-token inference on an approved local model | Open |

Next implementation unit: define and test the immutable execution-resource manifest and
its revalidation/staging contract before registering a `RuntimeMLX` adapter. A package version
or RECORD file alone is not trusted execution identity. Missing local dependencies prevent
live inference in the inspected environment but do not prevent synthetic boundary tests.
