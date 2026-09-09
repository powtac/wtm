# GPT4All storage

Status: implemented in this checkout, unreleased. Runtime and cleanup are not implemented.

Enable the suggested `~/Library/Application Support/nomic.ai/GPT4All` source or select the
actual download root. Only explicit source approval enables scanning. The adapter reads
GGUF v2/v3 headers through the shared scoped walker and preserves physical file identities.
It does not contact a catalog or infer a runnable model from a filename.

The `incomplete-` prefix and `.incomplete` suffix mark partial downloads. Legacy `.bin`,
split GGUF and invalid headers remain Unknown with issues. Remote `.rmodel` files are
excluded: they can contain credentials and are not local weights. Header recognition is
structural evidence, not full tensor or checksum validation.

The convention is grounded in the official
[GPT4All v3.10.0 model list source](https://github.com/nomic-ai/gpt4all/blob/v3.10.0/gpt4all-chat/src/modellist.cpp).
The [official FAQ](https://docs.gpt4all.io/gpt4all_help/faq.html) documents macOS/Metal support;
WTM still requires its own macOS 15+ Apple Silicon baseline.

`FirstWaveStorageTests.swift` builds synthetic fixtures for flat GGUF, partial markers,
legacy files, malformed headers, excluded remote configs, shared identities and symlink
escapes. No upstream model weights or credentials are copied into the fixture suite.
