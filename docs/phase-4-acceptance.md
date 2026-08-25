# Phase 4 Acceptance

Phase 4 is Integrations. Its implementation is present against the Phase 4 scope in
`REQUIREMENTS.md` and [ADR-026](decisions/ADR-026-passive-menu-bar-and-reviewed-client-handoffs.md).
The phase remains open until the manual UI and release evidence below is recorded.

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
| Automated verification | `./scripts/test` passed 88 Swift package tests, app tests, the Release build, architecture/decision/fixture/language checks, and website checks on 2026-08-25 |
| UI smoke | `./scripts/test-ui` passed 3 UI tests with 0 failures on 2026-08-25; the test process disables only the menu-bar projection via `WTM_UI_TEST_MODE` |
| Launch smoke | `./script/build_and_run.sh --verify` successfully launched the debug app and the process was then terminated cleanly |

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

## Open gates

1. A manual native UI pass remains required for status-item enable/disable, menu contents,
   navigation back to the inventory, launch-at-login independence, and client handoff preview.
2. Fresh Phase 4 integration/release evidence against the notarized distribution remains to
   be recorded. Phase 5 owns the final public DMG/Release/Pages gates.

## Explicit limits

- Client handoff never rewrites external client configuration and never claims ownership of
  provider-managed runtime processes.
- OpenClaw and Unsloth remain reviewed local integrations; they do not install packages,
  download models, orchestrate training, enable public tunnels, or execute shell strings.
- The Phase 5 GitHub update-check/About work is not part of this Phase 4 acceptance.
