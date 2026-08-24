# ADR-025: Owned Runtime Sessions and Evidence-Gated Verification

- Status: Accepted
- Date: 2026-08-24

## Context

Phase 3 introduces process launch and local inference. A static compatibility claim, a
reachable port, a healthy runtime, and a successful model response are different facts.
Custom executable definitions also create a code-execution boundary: a previously reviewed
path can be replaced, a port can be captured, logs can expose secrets, and a timeout can
otherwise terminate a process WTM does not own.

Provider-managed runtimes and WTM-owned processes need different lifecycle semantics.
Ollama exposes a loopback API but does not provide a request-owned process identity. A
`llama-server` process started by WTM has an exact `Process` handle and can therefore be
stopped safely.

## Decision

- `RuntimeBroker` is the only process-lifecycle authority. It owns an in-memory session
  registry and serializes state transitions.
- Runtime evidence remains separated into static compatibility, runtime reachability, and
  inference verification. Every volatile assertion includes adapter version, check time,
  expiry, and evidence.
- Provider APIs are preferred over CLI execution. Phase 3 permits only loopback HTTP
  endpoints. Redirects or endpoints resolving outside loopback are rejected.
- CLI tools use immutable, schema-versioned `ToolDefinition` data containing an absolute
  executable URL and typed argument tokens. Shell strings, script bodies, arbitrary
  placeholder interpolation, and inherited environment variables are unsupported.
- Before first execution, WTM displays the canonical executable, signing result, and final
  argument array. Approval is bound to a no-follow binary identity and is invalidated when
  that identity changes. Identity is revalidated immediately before launch.
- WTM stops only a process represented by a live handle created by its current broker
  session. A provider-managed runtime can be stopped only if its adapter exposes an instance
  identity that cannot affect another client. Ollama does not currently meet that condition.
- Health checks precede minimal inference checks. A minimal inference request is explicit
  and warns that it can load the full model into unified memory.
- Runtime logs are bounded, redacted, and ephemeral. Runtime instances and logs are not
  restored as live state after app restart.
- Tool definitions and execution approvals may persist in versioned JSON. Imported
  definitions receive a new identity, are fully previewed, remain disabled, replace the
  stored override for that runtime, and inherit no approval. Export disables the definition
  and removes validation evidence and home-directory paths.
- A stored runtime override suppresses convention discovery for the same runtime after
  relaunch. Discovery must not recreate a duplicate default beside an imported or
  user-created override.
- `llama-server` is bound explicitly to `127.0.0.1`. Port availability is checked before
  launch and the selected port is propagated as a typed argument and endpoint. A bind race
  fails safely and may retry with a newly selected port; WTM never attaches ownership to an
  unknown listener.

## Consequences

- Ollama readiness and inference verification are supported without claiming ownership of
  its daemon or loaded model. WTM does not offer a destructive Ollama stop action in Phase 3.
- Controlled start and stop are available for WTM-started `llama-server` processes.
- Static validation cannot prove that a model will load or produce useful output.
- WTM cannot support interactive tools, shell setup scripts, pipelines, command expansion,
  or tools that require a fully inherited login-shell environment.
- A process crash, RAM exhaustion, provider API change, or port race remains possible and is
  surfaced as bounded evidence rather than converted into a compatibility claim.
- Custom tool approvals and definitions may persist; runtime state and output do not.
- App termination waits only for bounded cleanup of live WTM-owned process handles. It does
  not terminate provider-managed or inferred processes.
- Readiness precedes the normal test action. A negative compatibility result can expose only
  an explicit secondary `Try Anyway` path; it is never presented as verified compatibility.

## Requirements impact

`FR-HLT-*` and `FR-RUN-*` must preserve the three verification levels, loopback-only
networking, typed arguments, executable identity confirmation, owner-scoped stop semantics,
explicit memory warning, timeout/cancellation behavior, and bounded redacted logs. Phase 3
must not introduce client handoff, downloads, Terminal automation, or dynamic code plugins.

## Validation

Automated tests cover malformed tool definitions, path and identity changes, argument
resolution, environment allowlists, port conflicts, illegal state transitions, timeout,
cancellation, stop ownership, loopback rejection, health-check ordering, minimal inference,
and log redaction. Architecture checks permit `Process` only in the reviewed runtime launcher
and continue to reject shells and process execution from the app or adapters.
