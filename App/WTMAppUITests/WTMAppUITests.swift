import XCTest

final class WTMAppUITests: XCTestCase {
  @MainActor
  func testSourceSetupAppearsOnFirstLaunch() throws {
    let application = XCUIApplication()
    application.launch()

    XCTAssertTrue(application.staticTexts["Choose Model Sources"].waitForExistence(timeout: 5))
  }
}
