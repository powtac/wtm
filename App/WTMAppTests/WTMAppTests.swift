import Testing
import WTMDomain

@testable import WTM

@MainActor
@Test("Built-in sources require explicit consent")
func builtInSourcesAreDisabled() {
  let model = AppComposition.makeInventoryViewModel()

  #expect(model.sources.allSatisfy { !$0.isEnabled })
}

@MainActor
@Test("Known inventory values use product strings")
func inventoryValuesUseProductStrings() {
  #expect(ProviderID.huggingFace.localizedName == "Hugging Face")
  #expect(InstallationState.incomplete.localizedName == "Incomplete")
}
