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

  @MainActor
  func testCleanupPreviewShowsReviewedOperationsWithoutExecutingThem() throws {
    let homeURL = FileManager.default.temporaryDirectory.appending(
      path: "wtm-ui-cleanup-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let modelsURL = homeURL.appending(path: ".models", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)
    let modelURL = modelsURL.appending(path: "Fixture-Q4_K_M.gguf")
    try Data("fixture".utf8).write(to: modelURL)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let application = XCUIApplication()
    application.launchEnvironment["WTM_SETTINGS_NAMESPACE"] =
      "de.powtac.whatthemodel.ui-tests.cleanup.\(UUID().uuidString)"
    application.launchEnvironment["WTM_UI_TEST_HOME_DIRECTORY"] = homeURL.path
    application.launch()
    defer { application.terminate() }

    let sourceToggle =
      application.descendants(matching: .any)["source-toggle-default:models"]
    XCTAssertTrue(sourceToggle.waitForExistence(timeout: 5))
    sourceToggle.click()
    let startScan = application.buttons["Start Scan"]
    XCTAssertTrue(startScan.isEnabled)
    startScan.click()

    let modelName = application.staticTexts["Fixture-Q4_K_M"].firstMatch
    XCTAssertTrue(modelName.waitForExistence(timeout: 10))
    modelName.click()
    let review = application.buttons["Review Cleanup…"].firstMatch
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    review.click()

    XCTAssertTrue(application.staticTexts["Planned Operations"].waitForExistence(timeout: 5))
    XCTAssertTrue(application.staticTexts["Fixture-Q4_K_M.gguf"].exists)
    XCTAssertTrue(application.buttons["Move to Trash"].exists)
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path))
    application.buttons["Cancel"].click()
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path))
  }
}
