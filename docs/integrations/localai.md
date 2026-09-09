# LocalAI runtime

Status: implemented in this checkout, unreleased. Provider-managed tests only.

Select a stored GGUF installation, expand Configure Local Connection in its LocalAI section,
and save the local API root and exact API model ID. Start LocalAI separately. Saving does
not contact it. The root must use HTTP, numeric `127.0.0.1` or `::1`, and an explicit port;
paths, query strings, credentials and fragments are rejected. No endpoint or model mapping
is guessed from a filename.

Readiness calls `GET /readyz` and `GET /v1/models`. A separately previewed test checks the
exact model ID and calls `POST /v1/chat/completions` with `max_tokens: 1` and `stream: false`.
The full model may load. Plans expire after 120 seconds and bind the endpoint/model ID;
changing that mapping invalidates the preview and execution. HTTP responses are bounded to
1 MiB, with 10-second request and 30-second resource timeouts. Redirects, cookies, proxies,
caches and credential storage are disabled. Authentication-required endpoints fail closed.

Reachability is unauthenticated. Successful inference proves an API response, not LocalAI
manufacturer identity or equality with the scanned local weights. No provider process is
adopted, started or stopped. Credentials, downloads and server configuration edits are absent.
Connections persist as local settings; runtime evidence and output do not.

Official contracts: [health and model listing](https://localai.io/docs/basics/troubleshooting/),
[chat API examples](https://localai.io/docs/basics/try/index.html), and
[native binary platforms](https://localai.io/docs/reference/binaries/).

`LocalAIRuntimeAdapterTests.swift` and `RuntimeHTTPContractTests.swift` verify explicit
mapping, stale bindings, partial weights, exact request bodies, missing credentials,
HTTP/auth/redirect failures and response limits using synthetic transports. A live LocalAI
backend has not been verified for this change.
