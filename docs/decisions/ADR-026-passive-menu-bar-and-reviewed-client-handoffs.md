# ADR-026: Passive Menu Bar and Reviewed Client Handoffs

- Status: Accepted
- Date: 2026-08-24

## Context

Phase 4 adds a menu bar surface and hands verified local models or endpoints to external
clients. Both features can accidentally create a second source of truth. Client handoff also
crosses a process, application, configuration, and secrets boundary.

OpenClaw is a model consumer, not a model store or runtime owner. Unsloth Studio combines
inference and training-oriented capabilities; starting it with broad defaults could enable
unrelated tools or public-tunnel behaviour.

## Decision

- The menu bar is a passive projection of the existing in-memory inventory view model. It
  never owns a scanner, persistence layer, runtime registry, or background refresh loop.
- The status item uses a monochrome template symbol without permanent text. Its popover
  exposes counts, physical storage, old and incomplete models, issues, running WTM sessions,
  offline sources, last scan evidence, and explicit Open/Scan actions.
- Users can remove the status item in General settings. Launch at login remains an explicit,
  separate setting and must use `SMAppService`; it is never implied by enabling the menu bar.
- A `ClientAdapter` is compiled and reviewed. It receives an installation plus previously
  verified endpoint evidence and creates a short-lived handoff plan. It cannot mutate the
  client's persistent default model or claim runtime ownership.
- Native app bundles are opened with `NSWorkspace`. CLI clients use the centralized,
  identity-bound process launcher with typed arguments and no shell or Terminal automation.
- OpenClaw handoff uses its provider-qualified model reference and fresh inference evidence
  from a previously validated Ollama loopback runtime. WTM executes one reviewed local
  inference command; it does not store OpenClaw credentials or rewrite its configuration.
- Unsloth is presented as a Studio integration. WTM may start its reviewed API-only Studio
  command on numeric loopback or open an already configured local Studio endpoint. The plan
  disables tools and Cloudflare; WTM does not orchestrate training or install Python packages.
- Data-only client definitions can narrow an existing compiled capability; they cannot add
  executable code, shell syntax, unreviewed endpoint schemes, or arbitrary environment keys.

## Consequences

- Menu state cannot diverge from the main window during a process lifetime.
- Closing every inventory window does not terminate WTM while the status item is enabled.
- Client adapters remain less flexible than Terminal commands by design. Unsupported client
  installations receive an actionable unavailable state rather than a best-effort launch.
- Provider/API drift still requires adapter maintenance and contract tests.

## Validation

Tests cover menu summary derivation, insertion preference, adapter registry uniqueness,
provider-qualified model references, loopback endpoint rejection, expiring plans, and the
absence of shell, Terminal automation, secrets, training, installation, or download paths.
