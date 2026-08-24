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
