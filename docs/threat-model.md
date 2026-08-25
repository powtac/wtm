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
| A malformed tool manifest expands capabilities | Decode a versioned closed schema; reject unknown roles, placeholders, environment keys, endpoints, and schema versions; normalize every import to a new disabled unapproved definition after complete preview |
| An exported tool manifest leaks local identity | Disable the exported definition and remove validation evidence, approval state, and home-directory paths before writing JSON |
| Convention discovery duplicates an imported override | Persist one override per runtime and suppress the discovered default whenever a valid stored definition exists for that runtime |
| Runtime state survives as a false live claim | Keep process handles, runtime state, endpoints, and logs in memory; recheck providers after every app launch |

## Explicitly absent in Phase 3

Client handoff, OpenClaw, Unsloth, downloads, remote inference endpoints, dynamic code
plugins, Terminal automation, privileged helpers, and unattended execution remain out of
scope. Provider-managed processes are not treated as WTM-owned merely because their port or
model name is known.

## Phase 4 threats and controls

| Threat | Control |
|---|---|
| Menu-bar state diverges or starts a second scanner | Native status item is a passive projection of the single ephemeral inventory model and owns no scanner, persistence, or refresh loop |
| Menu lifecycle consumes unbounded CPU or memory in hosted execution | Use `NSStatusItem`/`NSMenu`; omit it from hosted unit-test processes after the rejected SwiftUI `MenuBarExtra` lifecycle showed a symbol-update loop |
| Client handoff mutates persistent defaults or claims runtime ownership | Short-lived reviewed handoff plans only; no client-config rewrite and no adoption of client/provider processes |
| A client executable, interpreter, or script changes after preview | Bind protected canonical identities and revalidate immediately before direct process launch |
| OpenClaw receives an ambiguous model name or stale endpoint | Require provider-qualified Ollama identity and fresh WTM inference evidence on numeric loopback |
| Unsloth enables unrelated tools, training, or public access | Reviewed API-only arguments disable tools and Cloudflare; training, installation, and public binds remain absent |
| Closing the app leaves a WTM-owned client process behind | Track the exact process handle and perform bounded owned-process shutdown during app termination |

## Explicitly absent in Phase 4

Generic MLX storage/runtime support, model downloads, package installation, training
orchestration, remote inference endpoints, public tunnels, client-config mutation, and
unattended handoff remain out of scope.

## Phase 5 threats and controls

| Threat | Control |
|---|---|
| A partial workflow publishes `latest` | Keep the GitHub Release draft until every build, trust, backup, and attestation gate succeeds; publish only in the final step |
| Signing credentials persist on a runner | Store credentials only in the protected release Environment, import into an ephemeral keychain, and delete it unconditionally |
| Signed app and distributed DMG differ | Notarize/staple both layers, mount the final DMG, copy its app, then repeat code-signing, Gatekeeper, and process-start checks |
| Release artifacts contain credentials | Reject credential file types and high-confidence secret patterns before upload; publish checksums, SPDX SBOM, and build metadata |
| Private preparation accidentally becomes public | Require the exact repository, public visibility, exact SemVer tag, matching app version, and explicit Pages/release jobs |
| Mutable third-party Actions alter the release | Pin Actions to full commit hashes and grant each job only explicit token permissions |

## Deferred Phase 6 and 7 boundaries

Phase 6 MLX storage is read-only and requires licensed fixtures, structural evidence,
false-positive handling, and the existing path/symlink controls. MLX runtime execution is a
separate sub-gate: interpreter identity alone is insufficient because Python package and
module resolution can change executed code. It must bind and revalidate interpreter, entry
point, package/distribution identity, protected model resources, working directory,
arguments, and allowlisted environment; it rejects module-path injection and inputs that
can trigger implicit Hub downloads. If this cannot be guaranteed, Phase 6 remains
storage-only.

Phase 7 is the sole planned model-download boundary. Before implementation it requires a
separate threat model covering license acceptance, Keychain authentication, canonical HTTPS
sources and redirect validation, immutable revisions, staging/resume/atomic finalization,
checksums, temporary disk pressure, cancellation cleanup, unsafe serialization, remote code,
and the rule that downloaded content is never automatically executed. No Phase 8 capability
is currently authorized.
