# What The Model

[![CI](https://github.com/powtac/wtm/actions/workflows/ci.yml/badge.svg)](https://github.com/powtac/wtm/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/github/actions/workflow/status/powtac/wtm/ci.yml?branch=main&label=tests)](https://github.com/powtac/wtm/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/powtac/wtm?display_name=tag&sort=semver)](https://github.com/powtac/wtm/releases/latest)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)](https://support.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

What The Model is a native macOS inventory for locally stored LLMs. It explains which
models are present, where their files live, how much storage they occupy, whether a
download is incomplete, and which provider metadata belongs to each installation.

The current beta adds explicit runtime verification, a passive menu bar inventory, and
reviewed OpenClaw and Unsloth handoffs. WTM never opens a shell, automates Terminal, or
downloads models.

## Current scope

- Ollama manifest and blob inventory
- Hugging Face model-cache and incomplete-download inventory
- Conservative GGUF and Safetensors discovery in user-selected folders
- Explicit per-source consent before scanning
- Search, provider/state filtering, local file details, and Finder reveal
- A normalized in-memory inventory rebuilt from provider files on every launch
- Multi-model cleanup preview with retained dependencies, conflicts, and conservative
  reclaim estimates
- macOS Trash for manual and Hugging Face files; separately confirmed Ollama API deletion
- Open-file and loaded-model blocking, targeted post-action rescans, and a redacted local
  audit that the user can clear
- Separate integrity, compatibility, validation, and runtime evidence for each supported
  model/runtime pair
- Ollama loopback health and one-token inference verification without daemon ownership
- Reviewed llama.cpp launch plans, identity-bound executable approval, in-app redacted logs,
  and Stop limited to the exact WTM-owned process
- Configurable, schema-validated runtime tool definitions with disabled imports and
  privacy-redacted exports
- Passive menu bar status and an independent Launch at Login setting
- Reviewed OpenClaw and Unsloth client handoffs with visible executable and argument plans

See [Requirements (German, normative)](REQUIREMENTS.md) and the
[architecture](docs/architecture.md) for the exact scope and security boundaries. The
[ADR index](docs/decisions/README.md) records why durable constraints exist, and the
[roadmap](docs/roadmap.md) records phase gates without weakening them into a generic MVP.

## Build

Requirements:

- macOS 15 or later
- Apple Silicon
- Xcode 26.3 or later with Swift 6

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Set your Apple Developer Team ID in Config/Local.xcconfig.
open WTM.xcodeproj
```

Command-line verification:

```sh
./scripts/test
```

Build and launch the current Debug app through the project-local entrypoint:

```sh
./script/build_and_run.sh --verify
```

The Codex workspace exposes the same entrypoint as its `Run` action. The script also accepts
`--debug`, `--logs`, and `--telemetry`; every mode stops an older WTM process and rebuilds
before launching.

The labeled-control UI smoke test additionally requires macOS Developer Tools security.
Hosted CI falls back to ad-hoc test-runner signing without hardened runtime:

```sh
sudo DevToolsSecurity -enable
./scripts/test-ui
```

The local configuration is ignored by Git. Signing certificates, Team IDs, and
notarization credentials must never be committed.

## Release

Stable releases are created only by an exact `vMAJOR.MINOR.PATCH` tag through the protected
`release` Environment. The workflow signs, notarizes, staples, mounts, copies, and starts
the DMG payload before it publishes a GitHub Release. See
[GitHub configuration](docs/github-configuration.md) for the required Environment secrets.

## Extend WTM

Read the [public extension guide](https://powtac.github.io/wtm/extend.html) and the
[technical adapter guide](docs/adapters.md) before proposing a provider or tool. Data-only
definitions and compiled adapters have intentionally different capability and review
requirements. The static website is versioned in [`website/`](website/); its deployment
activates only after the repository becomes public.

## License

Apache License 2.0. Test fixtures are generated placeholders and contain no model weights.
