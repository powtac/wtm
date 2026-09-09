# ADR-030: Explicit Local Service Connections

- Status: Accepted
- Date: 2026-09-09

## Context

The first follow-on adapter wave needs provider-managed LocalAI tests and an Open WebUI
browser handoff. Neither an OpenAI-compatible response nor a user-entered model ID proves
provider identity or a mapping to scanned weights. A browser handoff is different from the
owned client processes introduced by ADR-026.

## Decision

- Store only explicitly entered service/installation endpoint and model-reference settings
  in versioned local JSON, bounded to 1 MiB. No credential fields, automatic connection,
  import/export or restored validation evidence are introduced.
- Endpoints require HTTP numeric loopback, explicit ports and root paths; query strings,
  fragments and URL credentials are rejected. Changes invalidate outstanding previews.
- LocalAI uses separate health, exact model-list and one-token inference contracts with
  bounded, credential-free, redirect-free HTTP. It claims no process or file identity and
  offers no launch, installation or Stop capability.
- Extend ADR-026 with a browser strategy. The compiled Open WebUI adapter requires fresh
  inference evidence and emits one model-selection parameter, with no prompt or tools.
  Plan expiry cannot exceed evidence expiry. The central broker validates the full URL
  and plan before the composition layer opens it through the OS browser service.
- Browser authentication remains in the browser. WTM does not authenticate or control the
  selected WebUI instance, its backend mapping, redirects after navigation or browser state.

## Consequences

Explicit connection settings survive relaunch; live endpoints observed from runtime tests,
process handles, inference results and logs remain ephemeral under ADR-025. This extends
configuration, not the inventory index. Provider-specific storage remains independent from
runtime/client authority. Authenticated LocalAI and unconfigured services fail closed.

## Requirements impact

Implements first-wave roles from FR-FUT-004 and FR-FUT-008 while preserving the separation
of provider, runtime and client and the explicit preview required by FR-HLT-007. No release
gate, download restriction or process-ownership invariant is waived.

## Validation

Synthetic tests cover path boundaries, explicit mapping, changed preview bindings, HTTP
contracts and response bounds, URL injection, evidence expiry, persistence and App settings
invalidation. Architecture checks include the new concrete targets. Live provider testing
and manual release gates remain separately recorded; contract tests do not substitute for them.
