import Foundation
import Testing
import WTMDomain
import WTMPersistence

@Test("Local connections persist explicitly and newer schemas cannot be overwritten")
func localConnectionPersistence() throws {
  let root = FileManager.default.temporaryDirectory.appending(path: "wtm-connections-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appending(path: "connections.json")
  let store = try JSONLocalConnectionStore(url: url)
  #expect(store.connection(serviceID: "localai", installationID: "model") == nil)
  let connection = LocalModelConnection(
    endpoint: connectionTestURL("http://127.0.0.1:8080"), modelReference: "Exact-ID")
  try store.set(connection, serviceID: "localai", installationID: "model")
  #expect(
    try JSONLocalConnectionStore(url: url).connection(serviceID: "localai", installationID: "model")
      == connection)
  try store.set(nil, serviceID: "localai", installationID: "model")
  #expect(
    try JSONLocalConnectionStore(url: url).connection(serviceID: "localai", installationID: "model")
      == nil)
  try store.set(connection, serviceID: "localai", installationID: "model")
  try store.set(connection, serviceID: "open-webui", installationID: "other")
  try store.removeAll()
  let reset = try JSONLocalConnectionStore(url: url)
  #expect(reset.connection(serviceID: "localai", installationID: "model") == nil)
  #expect(reset.connection(serviceID: "open-webui", installationID: "other") == nil)
  try Data(#"{"schemaVersion":999,"services":{}}"#.utf8).write(to: url)
  #expect(throws: (any Error).self) { try JSONLocalConnectionStore(url: url) }
}

private func connectionTestURL(_ value: String) -> URL {
  guard let url = URL(string: value) else { preconditionFailure("Invalid test URL") }
  return url
}
