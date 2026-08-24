# ADR-008: Safe Process Invocation

- Status: Accepted
- Date: 2026-08-24

## Context

Later phases need to start local runtimes and clients. Terminal automation and shell
strings add injection, quoting, permission, lifecycle, and ownership ambiguity.

## Decision

Launch CLI tools directly with Foundation `Process`, an absolute executable URL, and a
separate argument array. Never invoke a shell, `eval`, or Terminal by default. Show the
resolved executable and final arguments before the first custom execution; capture bounded,
redacted output inside WTM.

## Consequences

- Shell features, pipelines, expansion, and interactive prompts are unsupported.
- Tool placeholders require a typed, versioned schema.
- WTM may stop only processes it started or provider instances it can identify safely.
- Static validation is not runtime verification; health and inference checks remain
  separate, explicit operations.

## Requirements impact

Runtime requirements must cover executable identity, argv validation, environment
allowlists, signature changes, ports, timeouts, cancellation, logs, ownership, health, and
minimal inference verification.

## Validation

Phase 1 architecture checks reject `Process` and shell entry points. Phase 3 must add
negative argument, lifecycle, health-check, and ownership tests before linking runtime code.
