# Threat Model

## Assets

- User model files and provider caches
- Local paths and inventory metadata
- Provider configuration files
- Signing and notarization credentials
- Trust in release artifacts

## Trust boundaries

- Untrusted file names, directory layouts, symlinks, and manifests enter provider adapters.
- User-selected roots cross from macOS UI into the read-only scanner.
- HTTPS model-card links leave the local application.
- GitHub Actions and release runners handle source and, later, signing credentials.

## Phase 1 threats and controls

| Threat | Control |
|---|---|
| Symlink escapes the selected root | Resolve and validate every candidate against the configured root; skip rejected entries |
| Malformed provider manifest stops all scans | Adapter-local decoding failures become issues; other sources continue |
| Shared data is counted repeatedly | Preserve physical identifiers and deduplicate allocated bytes |
| A broad manual source duplicates provider cache revisions | Reconcile identical artifact paths in favor of provider evidence; preserve distinct paths and volumes |
| A partial download is shown as usable | Provider markers such as `.incomplete` and missing Ollama blobs produce an incomplete state |
| A scan mutates source data | No action/runtime target; architecture check blocks known mutation and process APIs in scan targets |
| Secrets appear in UI or logs | Do not preview secret-like configuration; OSLog treats dynamic local data as private |
| A broad permission is implied | Consent and actual file-system access are separate states; no Full Disk Access guidance |
| Unrelated media access expands the trust boundary | No microphone, audio-capture, Media Library, Apple Music, or speech-recognition usage descriptions, entitlements, or framework imports |

## Explicitly absent in Phase 1

Deletion, process launch, local inference, executable discovery, dynamic code plugins,
privileged helpers, telemetry, and remote inventory upload are out of scope. Their later
introduction requires an ADR and an updated threat model before implementation.
Microphone input, audio capture or playback, Media Library, Apple Music, and speech
recognition access are also explicitly absent.

## Phase 2 threats and controls

| Threat | Control |
|---|---|
| A file is replaced after preview | Record a no-follow filesystem identity and reject any mismatch immediately before mutation |
| A symlink is swapped to escape the source | Validate lexical containment, source consent, symlink identity, and operation scope again at execution |
| A shared blob is deleted while still referenced | Provider action adapters build a fresh reference graph and retain every target with a remaining reference |
| A stale preview is replayed | Plans are short-lived, bound to one executor generation, and consumed once |
| Two selected models claim overlapping targets | Build and display a batch conflict graph; unresolved conflicts block execution |
| A running model is removed | Ollama `/api/ps` blocks loaded models; local macOS process metadata blocks positively identified open file targets at preview and revalidation; access-denied processes remain explicitly unverified |
| A provider partially completes deletion | Stop subsequent operations, report each result, append a redacted audit entry, and rescan affected sources |
| A partial Hugging Face action removes a still-needed blob | Execute selected snapshots and refs before blobs; stop on first failure so no later shared blob is touched |
| A reversible action is presented as permanent, or vice versa | Every operation carries explicit reversibility; irreversible provider actions require separate confirmation |
| Audit data leaks private paths or credentials | Persist only time, adapter, action kind, counts, and outcome; never persist paths, names, payloads, or file contents |
| Action code becomes a general mutation surface | Compile-time targets, immutable contracts, central Trash service, and architecture checks reject raw delete and shell APIs |

## Explicitly absent in Phase 2

Process launch, runtime lifecycle, client handoff, downloads, privileged helpers, raw
permanent filesystem deletion, telemetry, and remote inventory upload remain out of scope.
Unknown external file usage is not silently treated as safe; provider evidence is used where
available and limitations stay visible in the preview.

## Phase 3 threats and controls

| Threat | Control |
|---|---|
| A configured argument becomes shell code | Tool definitions contain an absolute executable and separate typed argument tokens; shells, scripts, interpolation, Terminal automation, and `eval` remain absent |
| An approved executable is replaced before launch | Bind confirmation to canonical no-follow file identity and signing evidence; revalidate immediately before every launch |
| A symlink changes the executable target | Resolve the canonical target during validation and reject a changed lexical path, link identity, target identity, owner, or executable mode |
| Inherited environment values inject behavior or secrets | Start with an explicit allowlisted environment; no inherited login-shell environment and no `PATH` lookup |
| A custom endpoint enables SSRF or remote exposure | Accept HTTP only on numeric loopback hosts; reject redirects, wildcard binds, hostnames, and non-loopback addresses |
| Another process captures a selected port | Check loopback availability, pass the selected port as one typed value, verify the expected health contract, and fail or retry without adopting the unknown listener |
| Timeout or Stop terminates an unrelated process | Keep live handles for WTM-started processes; never infer ownership from a name or port; provider stop requires a uniquely attributable instance |
| Ollama Stop unloads a model used by another client | Phase 3 does not expose provider stop because the current API does not identify a WTM-owned model instance |
| Health is presented as successful inference | Record static compatibility, reachable health, and inference response as separate timestamped observations |
| A minimal test exhausts unified memory | Show model size and best-effort memory estimate before opt-in inference; bound timeout and explain that the full model may load |
| Runtime output exposes tokens or personal paths | Capture only bounded ephemeral output and redact credential-like values and approved sensitive paths before display |
| A malformed tool manifest expands capabilities | Decode a versioned closed schema; reject unknown executable roles, placeholders, environment keys, and disabled imported definitions |
| Runtime state survives as a false live claim | Keep process handles, runtime state, endpoints, and logs in memory; recheck providers after every app launch |

## Explicitly absent in Phase 3

Client handoff, OpenClaw, Unsloth, downloads, remote inference endpoints, dynamic code
plugins, Terminal automation, privileged helpers, and unattended execution remain out of
scope. Provider-managed processes are not treated as WTM-owned merely because their port or
model name is known.
