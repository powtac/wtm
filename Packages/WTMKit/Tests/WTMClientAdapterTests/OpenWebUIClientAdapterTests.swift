import ClientOpenWebUI
import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

@Test("Open WebUI encodes only the explicit model without submitting a prompt")
func webUIBrowserContract() async throws {
  let fixture = webUIFixture()
  let reference = "tiny &q=never-submit"
  let adapter = OpenWebUIClientAdapter(connection: { _ in
    LocalModelConnection(endpoint: fixture.endpoint, modelReference: reference)
  })
  let plan = try adapter.makeHandoffPlan(for: fixture.model, context: fixture.context)
  let url = try await ClientHandoffBroker().browserURL(plan: plan, installation: fixture.model)
  let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
  #expect(query == [URLQueryItem(name: "model", value: reference)])
  #expect(url.host == "127.0.0.1")
  #expect(plan.expiresAt == fixture.context.runtimeInstances.first?.lastInferenceCheck?.expiresAt)
}

@Test("Open WebUI requires fresh inference evidence and an explicit local connection")
func webUIRequiresEvidence() throws {
  let fixture = webUIFixture()
  let adapter = OpenWebUIClientAdapter(connection: { _ in
    LocalModelConnection(endpoint: fixture.endpoint, modelReference: "tiny")
  })
  #expect(throws: (any Error).self) {
    try adapter.makeHandoffPlan(for: fixture.model, context: ClientHandoffContext())
  }
  #expect(throws: (any Error).self) {
    try adapter.makeHandoffPlan(
      for: fixture.model,
      context: ClientHandoffContext(
        now: Date.now.addingTimeInterval(600), runtimeInstances: fixture.context.runtimeInstances))
  }
  let external = OpenWebUIClientAdapter(connection: { _ in
    LocalModelConnection(endpoint: webUITestURL("http://example.com:3000"), modelReference: "tiny")
  })
  #expect(throws: (any Error).self) {
    try external.makeHandoffPlan(for: fixture.model, context: fixture.context)
  }
}

@Test("Browser broker rejects injected actions and expired previews")
func webUIBrokerRevalidation() async throws {
  let fixture = webUIFixture()
  for (url, expiry) in [
    ("http://127.0.0.1:3000/?model=tiny&q=send", Date.now.addingTimeInterval(60)),
    ("http://127.0.0.1:3000/?model=tiny", Date.distantPast),
  ] {
    let plan = ClientHandoffPlan(
      adapterID: .openWebUI, installationID: fixture.model.id,
      modelReference: "tiny", createdAt: .now, expiresAt: expiry, endpoint: fixture.endpoint,
      strategy: .openURL(webUITestURL(url)))
    await #expect(throws: (any Error).self) {
      try await ClientHandoffBroker().browserURL(plan: plan, installation: fixture.model)
    }
  }
}

private func webUIFixture() -> (
  model: ModelInstallation, endpoint: URL, context: ClientHandoffContext
) {
  let endpoint = webUITestURL("http://127.0.0.1:3000")
  let model = ModelInstallation(
    id: "model", identity: ModelIdentity(id: "tiny", displayName: "Tiny"),
    variant: ModelVariant(id: "tiny", identityID: "tiny", format: .gguf), sourceID: "source",
    providerID: .manual,
    rootURL: URL(filePath: "/fixture/model.gguf"), state: .stored, artifacts: [])
  let runtime = RuntimeInstance(
    id: UUID(), adapterID: .llamaCpp, installationID: model.id,
    endpoint: webUITestURL("http://127.0.0.1:1234"),
    state: .running, ownership: .startedByWTM,
    lastInferenceCheck: RuntimeObservation(
      value: .inferenceVerified, adapterID: .llamaCpp, adapterVersion: "1",
      checkedAt: .now, expiresAt: Date.now.addingTimeInterval(60),
      evidence: "Synthetic inference fixture"))
  return (model, endpoint, ClientHandoffContext(runtimeInstances: [runtime]))
}

private func webUITestURL(_ value: String) -> URL {
  guard let url = URL(string: value) else { preconditionFailure("Invalid test URL") }
  return url
}
