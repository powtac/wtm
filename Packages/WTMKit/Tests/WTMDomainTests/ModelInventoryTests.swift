import Foundation
import Testing

@testable import WTMDomain

@Test("The same variant can remain distinct on different sources")
func installationsRemainSourceSpecific() {
  let identity = ModelIdentity(id: "hf:acme/tiny", displayName: "tiny")
  let variant = ModelVariant(
    id: "hf:acme/tiny:main",
    identityID: identity.id,
    format: .safetensors
  )
  let first = ModelInstallation(
    id: "source-a:tiny",
    identity: identity,
    variant: variant,
    sourceID: "source-a",
    providerID: .huggingFace,
    rootURL: URL(filePath: "/Volumes/A/tiny"),
    state: .stored,
    artifacts: []
  )
  let second = ModelInstallation(
    id: "source-b:tiny",
    identity: identity,
    variant: variant,
    sourceID: "source-b",
    providerID: .huggingFace,
    rootURL: URL(filePath: "/Volumes/B/tiny"),
    state: .stored,
    artifacts: []
  )

  #expect(first.id != second.id)
  #expect(first.variant.id == second.variant.id)
}
