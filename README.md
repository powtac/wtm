# What The Model

[![CI](https://github.com/powtac/wtm/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/powtac/wtm/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)
[![Tests](https://img.shields.io/github/actions/workflow/status/powtac/wtm/ci.yml?branch=main&event=push&label=tests)](https://github.com/powtac/wtm/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)
[![Latest Release](https://img.shields.io/github/v/release/powtac/wtm?display_name=tag&sort=semver)](https://github.com/powtac/wtm/releases/latest)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)](https://support.apple.com/macos)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

**Website:** [powtac.github.io/wtm](https://powtac.github.io/wtm/)

*What The Model* is **a native macOS inventory for locally stored LLMs**. It explains which
models are present, where their files live, how much storage they occupy, whether a
download is incomplete, and which provider metadata belongs to each installation.

## Installation

### Manual

Download the current [WTM 0.3.7 Apple Silicon DMG directly](https://github.com/powtac/wtm/releases/download/v0.3.7/WTM-0.3.7-arm64.dmg),
verify it as shown below, then open the `.dmg` and drag `WTM.app` to `Applications`. WTM
requires macOS 15 or later on Apple Silicon.

Verify the downloaded DMG before opening it:

```sh
curl -fLO "https://github.com/powtac/wtm/releases/download/v0.3.7/WTM-0.3.7-arm64.dmg"
curl -fL "https://github.com/powtac/wtm/releases/download/v0.3.7/WTM-0.3.7.sha256" -o checksums.sha256
shasum -a 256 --ignore-missing -c checksums.sha256
```

The checksum manifest must be in the same directory as the downloaded DMG. The commands
above are pinned to the current public `v0.3.7` release.

### Homebrew Cask — not yet released

The Homebrew Cask definition is prepared in [`packaging/homebrew/Casks/wtm.rb`](packaging/homebrew/Casks/wtm.rb),
but the `powtac/wtm` tap is not published yet. Homebrew installation is therefore not
available; use the verified manual download above. The [Homebrew release guide](docs/homebrew.md)
explains the publication and update process.

When the tap is published, installation will be:

```sh
brew tap powtac/wtm
brew install --cask wtm
```

Homebrew releases will be managed from the GitHub Release and pin the exact DMG checksum;
WTM does not distribute a formula or install model runtimes.

## ✨ Features

### 🎯 Core goals

- 🔎 Provider-neutral inventory across Ollama, Hugging Face, GGUF, Safetensors, and MLX-LM
- 💾 Honest storage attribution across internal and external local drives, including shared artifacts
- 🧬 Clear model identity, ownership, configuration, runtime, and evidence relationships
- 📊 Separate `Stored`, `Loaded`, `Usable`, and `Old` states instead of one misleading status
- 🧭 Detection of complete, incomplete, orphaned, and damaged local model collections
- 🖥️ Native macOS UX with safe, traceable, and preferably reversible actions

### 🚀 App features

- 🗂️ Explicit per-source consent, search, filtering, file details, and Finder reveal
- 🧹 Cleanup previews with dependency retention, conflict detection, Trash, and targeted rescans
- 🛡️ Redacted local audit, open-file blocking, and provider-aware deletion safeguards
- 🧪 Separate integrity, compatibility, health, validation, and real-inference evidence
- ⚡ Ollama loopback verification plus reviewed, identity-bound `llama.cpp` launch plans
- 🧰 Schema-validated runtime tools with visible executable and argument plans
- 🧩 Extendable adapters with separate storage, action, runtime, and client roles — see the
  [technical adapter guide](docs/adapters.md) and [current adapter sources](Packages/WTMKit/Sources/)
- 🔌 Reviewed OpenClaw and Unsloth client handoffs without silent configuration changes
- 📍 Passive menu bar status and independent Launch at Login setting
- 🪶 Low memory footprint for responsive inventory scans and everyday use
- 🔄 Automatic weekly update checks with manual download and installation through GitHub Releases
- 🔐 Signed, notarized, stapled releases with DMG verification, checksums, SBOM, and attestation
- 🔒 Privacy-preserving release checks without inventory, model, path, hardware, or telemetry data

See [Requirements (German, normative)](REQUIREMENTS.md) and the
[architecture](docs/architecture.md) for the exact scope and security boundaries. The
[ADR index](docs/decisions/README.md) records why durable constraints exist, and the
[roadmap](docs/roadmap.md) records phase gates without weakening them into a generic MVP.

## About WTM

The current build adds explicit runtime verification, a passive menu bar inventory,
reviewed OpenClaw and Unsloth handoffs, and opt-in read-only MLX-LM storage discovery.

The [product glossary](docs/glossary.md) defines the app's UI sections and canonical
inventory vocabulary. The same glossary is available on the [public website](https://powtac.github.io/wtm/glossary.html).

## Build

Requirements:

- macOS 15 or later
- Apple Silicon
- Xcode 26.3 or later with Swift 6

```sh
cp .env.example .env.local
source .env.local
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

The local configuration and `.env.local` are ignored by Git. The repository scripts read
the local signing identity and Team ID from `.env.local`; signing certificates and
notarization credentials must never be committed.

## Release

Stable releases are created only by an exact `vMAJOR.MINOR.PATCH` tag through the protected
`release` Environment. The workflow signs, notarizes, staples, mounts, copies, and starts
the DMG payload before it publishes a GitHub Release. See
[GitHub configuration](docs/github-configuration.md) for the required Environment secrets.
WTM checks that same official stable release channel at most once per seven days. Stable-
release builds include a weekly privacy-preserving check against official GitHub Releases;
WTM never auto-installs updates, opens a shell, automates Terminal, or downloads models.
Installation remains manual.

## Extend WTM

Read the [public extension guide](https://powtac.github.io/wtm/extend.html), the
[technical adapter guide](docs/adapters.md), and the [current adapter sources](Packages/WTMKit/Sources/)
before proposing a provider or tool. Data-only definitions and compiled adapters have
intentionally different capability and review requirements. The static website is versioned
in [`website/`](website/) and deployed through GitHub Pages after every validated change on
`main`.

## License

Apache License 2.0. Test fixtures are generated placeholders and contain no model weights.
