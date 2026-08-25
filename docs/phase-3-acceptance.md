# Phase 3 Acceptance

Phase 3 is Runtimes. Its code, UI, and distribution gates are accepted against
Requirements 0.2.0.

| Gate | Evidence |
|---|---|
| Evidence model | Integrity, static compatibility, runtime reachability, and real inference remain separate observations with adapter version, timestamp, expiry, and source evidence |
| Process authority | Only `RuntimeBroker` can launch or stop a process; shells, Terminal automation, inherited login environments, remote endpoints, downloads, and client handoff remain absent |
| Executable trust | Absolute executable URL, no-follow binary identity, signing result, architecture check, typed arguments, explicit environment, full launch preview, identity-bound approval, and immediate pre-launch revalidation |
| Ollama runtime | Numeric-loopback `/api/tags`, `/api/ps`, and bounded one-token `/api/generate`; WTM neither owns nor stops the Ollama daemon or provider-managed model instance |
| llama.cpp runtime | Reviewed `llama-server` plan, explicit `127.0.0.1` binding, allocated port, health-before-inference ordering, and Stop limited to the exact live `Process` handle created by WTM |
| Lifecycle safety | Serialized session transitions, timeout, cancellation, bounded termination cleanup, port-conflict handling, and no inference of ownership from a listener or PID |
| Logs and privacy | Bounded, redacted, ephemeral output; runtime state and logs are not restored as live state after relaunch |
| Tool definitions | Versioned closed schema, convention templates, one stored override per runtime, privacy-redacted export, and imported definitions assigned a new identity and forced disabled and unapproved |
| Product UX | Readiness precedes normal `Run Test`; negative static evidence exposes only the secondary `Try Anyway` path and never becomes a compatibility claim |
| Capability boundary | Architecture checks permit `Process` only in the reviewed launcher, local runtime HTTP only in runtime adapters, and reject shell, Terminal, client, download, privileged-helper, and media capabilities |

## Verification commands

```sh
./scripts/test
./scripts/test-ui
```

The 2026-08-24 local gate run passed 83 Swift-package tests, 19 app tests, the Release
build, all architecture/decision/fixture/language/format checks, and three native UI tests.
The UI suite verifies the non-executing launch preview and does not start a user runtime.

## Explicit limits

- Static compatibility and a memory estimate do not prove that a model can load, fit in
  unified memory, or produce useful output.
- A real inference check can load the complete model and consume substantial memory. The
  preview and confirmation communicate this before execution.
- `Try Anyway` bypasses only negative static compatibility evidence. It never bypasses
  executable validation, identity approval, loopback restrictions, or lifecycle safety.
- WTM does not own the Ollama daemon or provider-managed model process and therefore offers
  no Ollama Stop action in this phase.
- Tool-definition import configures only compiled runtime adapter roles. It is not a dynamic
  plugin, script, arbitrary command, client handoff, or download mechanism.

## Distribution evidence

- Build source commit: `d1780c8`
- Archive: `WTM Phase 3 2026-08-24 220600.xcarchive`
- Export: local path intentionally omitted
- Version: `0.3.0 (3)`; bundle identifier: `de.powtac.whatthemodel`
- Architecture: Apple Silicon (`arm64`)
- Signing: Developer ID signed with signer identity omitted; hardened runtime
- Entitlements: empty; App Sandbox remains disabled by accepted architecture decision
- Apple notarization: accepted on 2026-08-24 with no issues; submission
  `54EEA91E-D05D-4C9E-A499-0434235A8EA4`
- Stapler: ticket validation succeeded
- Gatekeeper: accepted, source `Notarized Developer ID`
- Launch smoke: notarized export remained running until controlled termination
- Code-directory hash: `1f37b67c0b5999089c30f3eac5f9e9a817ad9c70`
- Executable SHA-256:
  `5a95eb973afb6744e5669d0f4cb9120757228175376908abf5a77527180e3948`

The notarized archive and exported application match the same code-directory hash. All
Phase 3 findings are closed; Phase 3 is complete.
