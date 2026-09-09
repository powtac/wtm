# Jan storage

Status: implemented in this checkout, unreleased. Runtime and cleanup are not implemented.

Approve the Jan data root, suggested at `~/Library/Application Support/Jan/data`. The
adapter walks only `llamacpp/models`; it does not inventory chats, logs or extensions.
A bounded `model.yml` parser accepts a flat scalar subset: `model_path`, `name`,
`size_bytes`, `embedding`, and optional `model_sha256`. The hash is syntax-checked only;
WTM does not claim checksum verification. Unknown keys, nested YAML, aliases, duplicate
keys, invalid paths and manifests larger than 64 KiB are rejected.

A relative `llamacpp/models/.../*.gguf` path must identify an enumerated file in the same
directory as its manifest. GGUF v2/v3 headers and the declared size establish structural
completeness; missing weights and partial/split files remain incomplete. The scoped walker
bounds traversal and rejects path escapes. Physical identities support shared-byte accounting.
Legacy JSON, advanced YAML and Jan's MLX layout are unsupported; generic MLX inventory
remains a separately approved WTM source.

Contract source: [official data-folder documentation](https://www.jan.ai/docs/desktop/data-folder),
reviewed 2026-09-09. The [Mac installation guide](https://www.jan.ai/docs/desktop/install/mac)
documents upstream platform support; WTM requires macOS 15+ and Apple Silicon.

`FirstWaveStorageTests.swift` creates synthetic metadata/weights for the documented layout,
malformed headers, missing weights, traversal and unsupported YAML. No real Jan chat data
or model weights are included. Live Jan installations have not been verified for this change.
