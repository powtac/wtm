# Phase 4 Acceptance

Phase 4 is Integrations. Its implementation is present against the Phase 4 scope in
`REQUIREMENTS.md` and [ADR-026](decisions/ADR-026-passive-menu-bar-and-reviewed-client-handoffs.md).
The phase is complete. Automated, manual UI, and notarized distribution evidence is recorded
below.

| Gate | Evidence |
|---|---|
| Client boundary | Separate compiled `ClientAdapter` targets and registry uniqueness checks |
| OpenClaw | Provider-qualified Ollama reference, fresh inference evidence requirement, typed arguments, and negative runtime-evidence test |
| Unsloth | Reviewed API-only plan with numeric loopback, `--no-cloudflare`, `--disable-tools`, and no training path |
| Handoff execution | `ClientHandoffBroker` revalidates the reviewed executable, starts only the approved process, tracks ownership, and observes exit status |
| Menu bar projection | `NSStatusItem` derives counts, storage, age, incomplete bytes, issues, running sessions, offline sources, scan state, and actions from the existing inventory model |
| Launch at login | Independent `SMAppService` setting with injected service test; enabling the menu bar does not imply login launch |
| Settings and links | Integrations and launch-at-login controls are exposed through native Settings; adapter guide links remain data/configuration-only |
| Capability boundary | Architecture checks reject shell, Terminal automation, remote endpoints, dynamic plugins, package installation, training, public tunnels, and downloads |
| Automated verification | `./scripts/test` passed 93 Swift package tests, app tests, the Release build, architecture/decision/fixture/language checks, and website checks on 2026-08-26 |
| UI smoke | `./scripts/test-ui` passed 4 UI tests with 0 failures on 2026-08-26; the test process disables only the menu-bar projection via `WTM_UI_TEST_MODE` |
| Launch smoke | `./script/build_and_run.sh --verify` built, launched, and confirmed the debug process on 2026-08-26 |
| Manual UI | Native accessibility inspection verified menu-bar enable/disable with restoration, independent disabled Launch at Login, navigation between inventory and Settings, Integrations provider/client presentation, and the non-executing Unsloth handoff preview on 2026-08-26 |
| Distribution | Public v0.3.7 DMG checksum, strict code signature, notarized Gatekeeper acceptance, app/DMG stapling, DMG copy-and-launch smoke, SBOM, metadata, and artifact attestation were reverified on 2026-08-26 |

## Resolved UI crash

The UI smoke run reproduced a `SIGSEGV` caused by recursive AppKit constraint layout in
`NSStatusBarWindow` while creating an `NSStatusItem`. The menu-bar controller now ignores
reentrant settings notifications while applying the enablement state, and skips status-item
creation plus its defaults observer only for the explicit UI-test environment. Normal
launches keep the menu bar active. The recovery-alert helper dismisses only a stale macOS
“Don’t Reopen” prompt from an earlier crashed local run.

## Verification commands

```sh
./scripts/test
./scripts/test-ui
./script/build_and_run.sh --verify
```

## Acceptance result

The Phase 4 capability boundary, manual interaction path, and distribution evidence are
accepted. The handoff preview was inspected but not started; executing an external client is
not required to prove that WTM presents the exact shell-free plan before launch.

## Explicit limits

- Client handoff never rewrites external client configuration and never claims ownership of
  provider-managed runtime processes.
- OpenClaw and Unsloth remain reviewed local integrations; they do not install packages,
  download models, orchestrate training, enable public tunnels, or execute shell strings.
- The Phase 5 GitHub update-check/About work is not part of this Phase 4 acceptance.
