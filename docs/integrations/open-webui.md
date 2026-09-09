# Open WebUI client

Status: implemented in this checkout, unreleased. Browser handoff only.

For a stored installation, configure the local WebUI root and its exact WebUI model ID.
Complete a WTM runtime inference test for that installation, then preview the client handoff.
The URL contains exactly one encoded `model` parameter. The plan expires within 120 seconds
and no later than its inference evidence. The broker revalidates the installation, expiry,
root endpoint and complete query before the app opens the browser.

Only HTTP numeric loopback with an explicit port is accepted. The browser handles login;
WTM neither reads credentials nor contacts a WebUI API. The model reference and its backend
association are user-supplied and are not authenticated by WTM. Browser history may retain
the selected model ID. The handoff does not submit a prompt, enable tools, start a server,
change provider configuration or claim process/storage ownership.

The official [URL parameter contract](https://docs.openwebui.com/features/chat-conversations/chat-features/url-params/)
defines `model` selection. WTM excludes `q`, which would automatically submit a prompt,
and every other parameter. The [quick start](https://docs.openwebui.com/getting-started/quick-start/)
describes running the upstream browser service on a macOS host.

`OpenWebUIClientAdapterTests.swift` verifies model encoding, fresh evidence, expiry, external
endpoint rejection and injected query rejection. App tests cover settings isolation and
preview invalidation. A live authenticated WebUI session has not been verified for this change.
