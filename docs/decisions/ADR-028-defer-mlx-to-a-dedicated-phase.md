# ADR-028: Defer MLX to a Dedicated Phase

- Status: Accepted
- Date: 2026-08-25

## Context

The original roadmap placed generic MLX storage and runtime support in Phase 4 beside the
OpenClaw and Unsloth integrations. Implementation proved that these are different trust
boundaries. OpenClaw and Unsloth use reviewed handoff plans around existing WTM runtime
evidence; MLX-LM is a Python package whose server entry point resolves Python modules and
can interpret either a local path or a Hub model identifier.

The current code contains a `.mlx` format value, but that is only a vocabulary element. It
does not recognize a documented MLX directory graph, establish completeness, bind an MLX
runtime, or prove inference. A suffix or directory name is not sufficient model evidence.

Launching an `mlx_lm.server` script or `python -m mlx_lm.server` through the existing
executable approval would bind only part of the executed code. Python import resolution,
the selected interpreter, package tree, working directory, environment, symlinks, and
package updates can all change the code that actually runs. A Hub identifier may also turn
a runtime test into an implicit network download. The upstream server is intended for
local development and does not itself establish WTM's product security boundary.

## Decision

- MLX storage and runtime support are removed from Phase 4. Phase 4 contains the passive
  menu bar, launch-at-login setting, and reviewed OpenClaw and Unsloth client handoffs.
- Phase 6 becomes `MLX Support`, delivered after the stable public-release gate. Phase 7
  becomes the separately optional model-download phase.
- Phase 6 is split internally into two ordered gates:
  1. a compiled, read-only MLX storage adapter with documented fixtures, explicit
     completeness evidence, configuration association, and conservative false-positive
     handling;
  2. an optional MLX runtime adapter only after its execution trust model is accepted.
- `.mlx`, a directory name, or Python-package presence alone never proves an MLX model or
  a runnable installation.
- A shipped MLX runtime must bind and revalidate the canonical interpreter, entry point,
  package/distribution identity, protected model resources, working directory, arguments,
  and allowlisted environment. Arbitrary `python` lookup, inherited module search paths,
  shell activation, and unreviewed virtual environments are rejected.
- Runtime tests accept only a confirmed canonical local model path. Repository identifiers
  or other inputs that can trigger fallback downloads are rejected. WTM neither installs
  nor updates Python packages and does not enable training, remote binds, public tunnels,
  or remote code.
- MLX runtime state follows ADR-025: numeric loopback, explicit preview, bounded redacted
  logs, separate health/inference evidence, and Stop limited to a WTM-owned process.
- Model acquisition remains Phase 7. It cannot be smuggled into Phase 6 through library
  convenience APIs.
- There is no committed Phase 8. Further ideas remain backlog/research until a separate
  scope decision, requirements, and release gate are accepted.

## Consequences

- Phase 4 implementation no longer depends on Python or MLX and can be closed after its
  existing integration and release evidence is complete.
- Phase 6 can ship storage-only support if the runtime trust model is not strong enough.
  Inventory value is not coupled to executing third-party Python code.
- Python interpreter, package, or protected-resource changes invalidate prior approval.
- Users do not receive a misleading `Runnable` claim from a recognized suffix or installed
  command name.
- Downloads move to Phase 7 and retain an independent license, authentication, integrity,
  disk-space, cancellation, and supply-chain review.

## Requirements impact

The integration matrix, phase mapping, roadmap, threat model, and phase gates move generic
MLX support from Phase 4 to Phase 6. `FR-MLX-*` defines its observable boundary. `FR-DWN-*`
moves to Phase 7. Phase 4 remains `Implemented` until manual integration evidence closes
its gate; Phase 5 remains the next release milestone.

## Validation

Phase 6 storage tests require licensed MLX fixtures, malformed and partial structures,
configuration association, physical-byte accounting, symlink/path-boundary rejection, and
false-positive cases. Runtime tests additionally cover interpreter and package replacement,
module-search injection, hostile working directories and environment values, local-path-only
planning, loopback binding, port conflict, timeout/cancellation, process ownership, bounded
redaction, and distinct health versus minimal-inference evidence. Architecture checks must
continue to reject package installation, shell activation, implicit download inputs,
training, remote endpoints, and dynamic runtime plugins.

## References

- [MLX-LM repository](https://github.com/ml-explore/mlx-lm)
- [MLX-LM server documentation](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md)
