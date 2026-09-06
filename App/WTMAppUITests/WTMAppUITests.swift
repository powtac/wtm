import AppKit
import XCTest

final class WTMAppUITests: XCTestCase {
  @MainActor
  private func launch(_ application: XCUIApplication) {
    application.launchEnvironment["WTM_UI_TEST_MODE"] = "1"
    application.launchEnvironment["WTM_DISABLE_AUTOMATIC_UPDATE_CHECK"] = "1"
    application.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    application.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    application.launch()

    // A previous crashed local run can leave macOS' recovery alert in front of the app.
    let recoveryButton = application.dialogs.buttons["Don’t Reopen"].firstMatch
    if recoveryButton.waitForExistence(timeout: 1) {
      recoveryButton.click()
    }
  }

  @MainActor
  func testUpdateEntryPointsAreVisible() throws {
    let application = XCUIApplication()
    application.launchEnvironment["WTM_SETTINGS_NAMESPACE"] =
      "de.powtac.whatthemodel.ui-tests.updates.\(UUID().uuidString)"
    application.launchEnvironment["WTM_UI_TEST_SHOW_ABOUT"] = "1"
    launch(application)
    defer { application.terminate() }

    XCTAssertTrue(application.staticTexts["Choose Model Sources"].waitForExistence(timeout: 5))

    XCTAssertTrue(
      application.staticTexts["Local Model Inventory"].waitForExistence(timeout: 5),
      "About window is missing"
    )
    XCTAssertTrue(
      application.buttons["Check for Updates…"].exists,
      "About update button is missing"
    )
    XCTAssertTrue(application.links["Repository on GitHub"].exists, "Repository link is missing")
    XCTAssertTrue(application.links["Apache License 2.0"].exists, "License link is missing")
    XCTAssertTrue(
      application.links["Download Latest Release"].exists,
      "Download link is missing"
    )
  }

  @MainActor
  func testSourceSetupAppearsOnFirstLaunch() throws {
    let application = XCUIApplication()
    application.launchEnvironment["WTM_SETTINGS_NAMESPACE"] =
      "de.powtac.whatthemodel.ui-tests.\(UUID().uuidString)"
    launch(application)

    XCTAssertTrue(application.staticTexts["Choose Model Sources"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      application.staticTexts[
        "No microphone, audio capture, Media Library, Apple Music, or speech recognition access."
      ].exists
    )
    XCTAssertTrue(application.buttons["Start Scan"].exists)
    XCTAssertTrue(application.buttons["Add MLX Folder…"].exists)
    XCTAssertFalse(application.buttons["Start Scan"].isEnabled)

    let sourceToggle = application.descendants(matching: .any)["source-toggle-default:models"]
    XCTAssertTrue(sourceToggle.exists)
    XCTAssertFalse(sourceToggle.label.isEmpty, "Source toggle needs a VoiceOver label")
    snapshot("01-source-setup")
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
    try modelFixtureData().write(to: modelURL)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let application = XCUIApplication()
    application.launchEnvironment["WTM_SETTINGS_NAMESPACE"] =
      "de.powtac.whatthemodel.ui-tests.cleanup.\(UUID().uuidString)"
    application.launchEnvironment["WTM_UI_TEST_HOME_DIRECTORY"] = homeURL.path
    launch(application)
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
    snapshot("02-model-inventory")
    XCTAssertTrue(application.descendants(matching: .any)["app-version"].exists)
    NSPasteboard.general.clearContents()
    modelName.rightClick()
    let copyMenu = application.menuItems["Copy"].firstMatch
    XCTAssertTrue(copyMenu.waitForExistence(timeout: 5))
    copyMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
    XCTAssertTrue(application.menuItems["Model Name"].waitForExistence(timeout: 5))
    XCTAssertTrue(application.menuItems["Absolute Model Path"].waitForExistence(timeout: 5))
    let providerModelCopy = application.menuItems["Provider / Model Name"].firstMatch
    XCTAssertTrue(providerModelCopy.waitForExistence(timeout: 5))
    providerModelCopy.click()
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "manual/Fixture-Q4_K_M")
    XCTAssertTrue(
      application.descendants(matching: .any)["inventory-scan-button"].exists
    )
    XCTAssertTrue(
      application.descendants(matching: .any)["inventory-filter-menu"].exists
    )
    let searchField = application.descendants(matching: .any)["inventory-search-field"]
    XCTAssertTrue(searchField.exists)
    let scanControlY = application.descendants(matching: .any)["inventory-scan-button"].frame.minY
    XCTAssertEqual(searchField.frame.minY, scanControlY, accuracy: 3)

    let oldSection = application.staticTexts["sidebar-section-old"]
    XCTAssertTrue(oldSection.waitForExistence(timeout: 15))
    oldSection.click()
    XCTAssertTrue(
      application.staticTexts["No Models Match This View"].waitForExistence(timeout: 5)
    )
    application.buttons["Show All Models"].click()
    XCTAssertTrue(modelName.waitForExistence(timeout: 5))

    let issuesSection = application.staticTexts["sidebar-section-issues"]
    XCTAssertTrue(issuesSection.waitForExistence(timeout: 5))
    issuesSection.click()
    XCTAssertTrue(application.staticTexts["No Issues"].waitForExistence(timeout: 5))
    XCTAssertEqual(
      application.descendants(matching: .any)["inventory-scan-button"].frame.minY,
      scanControlY,
      accuracy: 2
    )
    application.staticTexts["sidebar-section-all"].click()
    XCTAssertTrue(modelName.waitForExistence(timeout: 5))

    modelName.click()
    let review = application.buttons["Review Cleanup…"].firstMatch
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    review.click()

    XCTAssertTrue(application.staticTexts["Planned Operations"].waitForExistence(timeout: 5))
    snapshot("03-cleanup-preview")
    let deletionModel =
      application.descendants(matching: .any)["deletion-preview-model-Fixture-Q4_K_M"]
    XCTAssertTrue(deletionModel.waitForExistence(timeout: 5))
    XCTAssertTrue(deletionModel.label.contains("Fixture-Q4_K_M"))
    XCTAssertTrue(application.buttons["Move to Trash"].exists)
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path))
    application.buttons["Cancel"].click()
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path))

    let settings = application.buttons["sidebar-settings-button"]
    XCTAssertTrue(settings.waitForExistence(timeout: 15))
    settings.click()
    let generalSettings = application.buttons["General"].firstMatch
    XCTAssertTrue(generalSettings.waitForExistence(timeout: 5))
    generalSettings.click()
    XCTAssertTrue(
      application.descendants(matching: .any)["Scan on Launch"].waitForExistence(timeout: 5)
    )
    XCTAssertTrue(application.buttons["Check for Updates…"].exists)
  }

  @MainActor
  func testRuntimePreviewShowsExecutableArgumentsAndOwnershipBeforeLaunch() throws {
    let homeURL = FileManager.default.temporaryDirectory.appending(
      path: "wtm-ui-runtime-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let modelsURL = homeURL.appending(path: ".models", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)
    let modelURL = modelsURL.appending(path: "Runtime-Fixture-Q4_K_M.gguf")
    try modelFixtureData().write(to: modelURL)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let application = XCUIApplication()
    application.launchEnvironment["WTM_SETTINGS_NAMESPACE"] =
      "de.powtac.whatthemodel.ui-tests.runtime.\(UUID().uuidString)"
    application.launchEnvironment["WTM_UI_TEST_HOME_DIRECTORY"] = homeURL.path
    application.launchEnvironment["WTM_UI_TEST_RUNTIME_EXECUTABLE"] = "/usr/bin/true"
    launch(application)
    defer { application.terminate() }

    let sourceToggle = application.descendants(matching: .any)["source-toggle-default:models"]
    XCTAssertTrue(sourceToggle.waitForExistence(timeout: 5))
    sourceToggle.click()
    application.buttons["Start Scan"].click()

    let modelName = application.staticTexts["Runtime-Fixture-Q4_K_M"].firstMatch
    XCTAssertTrue(modelName.waitForExistence(timeout: 10))
    modelName.click()

    let readinessCheck = application.descendants(matching: .any)["runtime-check-llama-cpp"]
    XCTAssertTrue(readinessCheck.waitForExistence(timeout: 5))
    readinessCheck.click()
    let runtimeTest = application.descendants(matching: .any)["runtime-test-llama-cpp"]
    XCTAssertTrue(runtimeTest.waitForExistence(timeout: 5))
    runtimeTest.click()

    XCTAssertTrue(
      application.descendants(matching: .any)["runtime-plan-title"].waitForExistence(timeout: 5)
    )
    XCTAssertTrue(application.staticTexts["/usr/bin/true"].exists)
    let modelArgument = application.descendants(matching: .any)["runtime-argument-1"]
    XCTAssertTrue(modelArgument.exists)
    XCTAssertTrue(application.buttons["Start and Verify"].exists)
    XCTAssertTrue(application.staticTexts["WTM can stop only this process instance."].exists)
    application.buttons["Cancel"].click()
  }

  @MainActor
  func testSettingsSectionsForScreenshots() throws {
    continueAfterFailure = false
    let homeURL = FileManager.default.temporaryDirectory.appending(
      path: "wtm-ui-settings-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let modelsURL = homeURL.appending(path: ".models", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)
    try modelFixtureData().write(to: modelsURL.appending(path: "Settings-Fixture-Q4_K_M.gguf"))
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let application = XCUIApplication()
    application.launchEnvironment["WTM_SETTINGS_NAMESPACE"] =
      "de.powtac.whatthemodel.ui-tests.settings.\(UUID().uuidString)"
    application.launchEnvironment["WTM_UI_TEST_HOME_DIRECTORY"] = homeURL.path
    launch(application)
    defer { application.terminate() }

    let sourceToggle = application.descendants(matching: .any)["source-toggle-default:models"]
    XCTAssertTrue(sourceToggle.waitForExistence(timeout: 5))
    sourceToggle.click()
    application.buttons["Start Scan"].click()
    XCTAssertTrue(
      application.staticTexts["Settings-Fixture-Q4_K_M"].waitForExistence(timeout: 10)
    )

    let settings = application.buttons["sidebar-settings-button"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.click()

    captureSettingsSection(
      application, tab: "General", header: "Scanning", name: "settings-general-scanning"
    )
    captureSettingsSection(
      application, tab: "General", header: "Model Age", name: "settings-general-age"
    )
    captureSettingsSection(
      application, tab: "General", header: "Updates", name: "settings-general-updates"
    )
    captureSettingsSection(
      application, tab: "General", header: "Menu Bar", name: "settings-general-menu-bar"
    )
    captureSettingsSection(
      application, tab: "General", header: "Inventory Data", name: "settings-general-inventory"
    )
    captureSettingsSection(
      application, tab: "General", header: "Defaults", name: "settings-general-defaults"
    )

    captureSettingsSection(
      application, tab: "Sources", header: "Enabled Sources", name: "settings-sources-enabled"
    )
    captureSettingsSection(
      application, tab: "Sources", header: "Mounted Drives", name: "settings-sources-volumes"
    )

    captureSettingsSection(
      application,
      tab: "Integrations",
      header: "Runtime Tools",
      name: "settings-integrations-runtimes"
    )
    captureSettingsSection(
      application,
      tab: "Integrations",
      header: "Storage Providers",
      name: "settings-integrations-storage"
    )
    captureSettingsSection(
      application, tab: "Integrations", header: "Clients", name: "settings-integrations-clients"
    )
    captureSettingsSection(
      application,
      tab: "Integrations",
      header: "Extending WTM",
      name: "settings-integrations-extension"
    )

    captureSettingsSection(
      application, tab: "Security", header: "Scan Access", name: "settings-security-access"
    )
    captureSettingsSection(
      application, tab: "Security", header: "Cleanup Audit", name: "settings-security-audit"
    )
  }

  @MainActor
  private func captureSettingsSection(
    _ application: XCUIApplication,
    tab: String,
    header: String,
    name: String
  ) {
    let tabButton = application.buttons[tab].firstMatch
    XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "Missing settings tab: \(tab)")
    tabButton.click()
    let section = application.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", header)
    ).firstMatch
    XCTAssertTrue(section.waitForExistence(timeout: 5), "Missing settings section: \(header)")

    for _ in 0..<8 where !section.isHittable {
      application.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500)
    }
    XCTAssertTrue(section.isHittable, "Settings section is not visible: \(header)")
    let scrollView = application.scrollViews.firstMatch
    let offset = section.frame.minY - scrollView.frame.minY - 20
    if offset > 40 {
      scrollView.scroll(byDeltaX: 0, deltaY: -offset)
    }
    snapshot(name)
  }

  @MainActor
  private func snapshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
    attachment.name = "WTM--\(name)--"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func modelFixtureData() -> Data {
    var data = Data("GGUF".utf8)
    appendLittleEndian(UInt32(3), to: &data)
    appendLittleEndian(UInt64(1), to: &data)
    appendLittleEndian(UInt64(0), to: &data)
    return data
  }

  private func appendLittleEndian(_ value: UInt32, to data: inout Data) {
    for shift in stride(from: 0, through: 24, by: 8) {
      data.append(UInt8((value >> UInt32(shift)) & 0xff))
    }
  }

  private func appendLittleEndian(_ value: UInt64, to data: inout Data) {
    for shift in stride(from: 0, through: 56, by: 8) {
      data.append(UInt8((value >> UInt64(shift)) & 0xff))
    }
  }
}
