import XCTest

final class CedarUITests: XCTestCase {
    @MainActor
    func testWelcomeNavigation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome.heading"].waitForExistence(timeout: 10))
        app.buttons["welcome.getStarted"].tap()
        XCTAssertTrue(app.staticTexts["library.heading"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitForExistence(timeout: 5))
    }
}
