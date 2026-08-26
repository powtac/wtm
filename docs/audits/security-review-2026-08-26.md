# Security Review — 2026-08-26

## Decision summary

The standard static security review found no critical, high, or medium-severity
vulnerability. Five high-confidence findings remain open at low severity. They should be
resolved before the first stable public release because they affect WTM's core trust claims:
approved filesystem scope, exact executable identity, verified local runtimes, and bounded
scanning.

This record is not a release approval. The scan covered revision
`ec6723aee840a1d77070601363fb851c98d0e5ea`; repository `HEAD` changed while the scan was
running. Re-run the review against the final release candidate after remediation.

## Audit identity and scope

| Field | Value |
|---|---|
| Date completed | 2026-08-26 |
| Codex Security scan ID | `4a7a6a61-f171-4b33-802a-6c6659fe6f53` |
| Scanned revision | `ec6723aee840a1d77070601363fb851c98d0e5ea` |
| Mode | Standard repository scan |
| Method | Offline static review with independent baseline, architecture review, focused runtime investigation, parent validation, and attack-path calibration |
| Inventory | 204 repository files mapped |
| Coverage | Partial: executable product, mutation, persistence, network, release, and security-control surfaces prioritized |
| Runtime testing | Not performed |
| Result | 5 low-severity findings; all high confidence |

External Ollama, llama.cpp, OpenClaw, Unsloth, Node, and Python implementations were not
audited. GitHub Environment protections and Apple account controls cannot be verified from
repository source.

## Validated findings

| ID | Finding | CWE | Severity | Required action |
|---|---|---|---|---|
| SEC-001 | A replaced source root can redirect scanning and cleanup | CWE-59 | Low | Bind consent to a no-follow root/ancestor identity and revalidate it before scan, planning, and mutation. |
| SEC-002 | Verified executables and scripts are reopened by path at launch | CWE-367 | Low | Eliminate or contain the check-to-launch race; reject untrusted-writable ancestor chains and use an immutable verified object or private staged copy. |
| SEC-003 | A captured llama.cpp port can be mistaken for the launched runtime | CWE-362 | Low | Preserve or authenticate port ownership and verify child identity/liveness after health and inference. |
| SEC-004 | Any listener on the Ollama port can produce verified-runtime evidence | CWE-346 | Low | Correlate the listener with Ollama or label the result as unauthenticated local evidence and do not use it as a security gate. |
| SEC-005 | Manual-folder scanning retains every file until traversal finishes | CWE-400 | Low | Add explicit scan budgets and incremental or spill-backed grouping with visible truncation. |

Primary source anchors:

- SEC-001: `Packages/WTMKit/Sources/WTMSecurity/ScopedPathPolicy.swift:14` and
  `Packages/WTMKit/Sources/WTMSecurity/DeletionTargetPolicy.swift:46`.
- SEC-002: `Packages/WTMKit/Sources/WTMRuntime/RuntimeBroker.swift:102`,
  `Packages/WTMKit/Sources/WTMRuntime/ClientHandoffBroker.swift:83`, and
  `Packages/WTMKit/Sources/WTMRuntime/FoundationProcessLauncher.swift:34`.
- SEC-003: `Packages/WTMKit/Sources/WTMRuntime/LoopbackPortAllocator.swift:14` and
  `Packages/WTMKit/Sources/WTMRuntime/RuntimeBroker.swift:274`.
- SEC-004: `Packages/WTMKit/Sources/WTMRuntime/RuntimeBroker.swift:95` and
  `Packages/WTMKit/Sources/RuntimeOllama/OllamaRuntimeTransport.swift:45`.
- SEC-005: `Packages/WTMKit/Sources/AdapterManual/ManualFolderAdapter.swift:27`.

## Remediation update

SEC-001 is fixed in the working baseline. Source consent now persists a no-follow identity for
the volume-relative root and every path component. Scan coordination, adapter traversal,
deletion planning, preview revalidation, and each Trash or provider mutation revalidate that
identity and fail closed on drift. Existing enabled sources without an identity become stale
and require access to be granted again; symlink roots are rejected.

Regression coverage replaces an approved root with a symlink before scanning and replaces a
root ancestor after deletion planning. Both paths are blocked. The complete Swift package
suite, app unit suite, and external-volume lifecycle test pass. Filesystem mutation still uses
the macOS Trash API, so descriptor-relative deletion is not available; immediate pre-mutation
revalidation is the platform-compatible control.

## Controls verified

- Production process launch does not invoke a shell; executable URL and arguments remain
  separate, stdin is null, and the environment is explicit.
- Deletion plans are serialized, short-lived, single-use, conflict-checked, and revalidated.
  Filesystem deletion uses macOS Trash and stops after the first mutation failure.
- Runtime HTTP endpoints are numeric loopback; runtime transports disable proxies, reject
  redirects, and use finite timeouts and response checks.
- No embedded credential, microphone, audio, Media Library, Apple Music, or speech capability
  was found.
- GitHub Actions are commit-pinned. Release publication validates tag, SHA, and version; uses
  an ephemeral signing keychain; verifies signing, notarization, stapling, and Gatekeeper; and
  attests artifacts before publishing a draft release.

## Rejected candidates and hardening work

- The Ollama deletion transport follows redirects. This was not reportable under the applied
  attacker model because the controlling local process gains no WTM-only credential or network
  authority. Redirects should still be rejected consistently.
- Tool-manifest import has no pre-decode byte limit. Explicit user selection and self-only
  impact kept it below the vulnerability threshold. Add a small documented limit and decode
  off the main actor.

## Release gate

The security-review activity is documented, but the public-release security gate remains
partial until:

1. SEC-001 through SEC-005 are fixed or explicitly accepted with rationale.
2. Regression tests named in the canonical scan report pass.
3. A new scan covers the final release-candidate revision.
4. The history/secret/PII, fixture-license, and trademark audits are recorded separately.

The canonical findings, coverage, SARIF export, and deterministic report remain associated
with Codex Security scan `4a7a6a61-f171-4b33-802a-6c6659fe6f53`.
