import XCTest

final class WTMAppUITests: XCTestCase {
  @MainActor
  func testSourceSetupAppearsOnFirstLaunch() throws {
    let application = XCUIApplication()
    application.launchEnvironment["WTM_SETTINGS_NAMESPACE"] =
      "de.powtac.whatthemodel.ui-tests.\(UUID().uuidString)"
    application.launch()

    XCTAssertTrue(application.staticTexts["Choose Model Sources"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      application.staticTexts[
        "No microphone, audio capture, Media Library, Apple Music, or speech recognition access."
      ].exists
    )
    XCTAssertTrue(application.buttons["Start Scan"].exists)
    XCTAssertFalse(application.buttons["Start Scan"].isEnabled)
  }
}
