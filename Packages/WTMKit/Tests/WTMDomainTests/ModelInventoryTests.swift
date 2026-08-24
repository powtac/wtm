import Foundation
import Testing

@testable import WTMDomain

@Test("Timestamp semantics do not imply cross-session persistence")
func timestampKindsRemainScanScoped() {
  #expect(TimestampKind.allCases.contains(.observedThisScan))
  #expect(!TimestampKind.allCases.map(\.rawValue).contains("firstSeen"))
}

@Test("Model age uses the earliest change timestamp and excludes scan observation")
func earliestChangeTimestampIsHonest() {
  let oldestChange = Date(timeIntervalSince1970: 100)
  let identity = ModelIdentity(id: "model", displayName: "Model")
  let variant = ModelVariant(id: "model:variant", identityID: identity.id, format: .gguf)
  let installation = ModelInstallation(
    id: "source:model",
    identity: identity,
    variant: variant,
    sourceID: "source",
    providerID: .manual,
    rootURL: URL(filePath: "/tmp/model"),
    state: .stored,
    artifacts: [],
    timestamps: [
      ObservedTimestamp(
        value: Date(timeIntervalSince1970: 10),
        kind: .observedThisScan,
        confidence: .confirmed
      ),
      ObservedTimestamp(
        value: Date(timeIntervalSince1970: 200),
        kind: .fileModification,
        confidence: .heuristic
      ),
      ObservedTimestamp(value: oldestChange, kind: .fileCreation, confidence: .derived),
    ]
  )

  #expect(installation.earliestChangeTimestamp?.value == oldestChange)
  #expect(installation.earliestChangeTimestamp?.kind == .fileCreation)
}

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
