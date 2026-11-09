import XCTest

final class CedarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--test-store", UUID().uuidString]
    }

    private func openLibrary() {
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome.heading"].waitForExistence(timeout: 10))
        app.buttons["welcome.getStarted"].tap()
        XCTAssertTrue(app.staticTexts["library.heading"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWelcomeNavigation() {
        openLibrary()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordSaveRelaunchPlayRenameDeleteAndRestore() {
        openLibrary()
        app.buttons["recorder.start"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            if permission.buttons["Allow"].exists { permission.buttons["Allow"].tap() }
            else if permission.buttons["OK"].exists { permission.buttons["OK"].tap() }
        }
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 10))
        // Wait for actual captured time, rather than stopping immediately after the UI switches.
        let timer = app.staticTexts["recorder.elapsed"]
        expectation(for: NSPredicate(format: "label >= %@", "00:03"), evaluatedWith: timer)
        waitForExpectations(timeout: 10)
        app.buttons["recorder.stop"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this iPhone."].waitForExistence(timeout: 5))
        app.terminate()
        openLibrary()
        let recording = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.tap()
        app.buttons["playback.toggle"].tap()
        XCTAssertEqual(app.buttons["playback.toggle"].label, "Pause")
        app.buttons["playback.toggle"].tap()
        XCTAssertEqual(app.staticTexts["playback.status"].label, "Paused")
        app.sliders["Playback position"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["Recording options"].tap()
        app.buttons["Rename"].tap()
        let field = app.alerts["Rename recording"].textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Cedar test conversation")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Cedar test conversation"].waitForExistence(timeout: 5))
        app.buttons["Recording options"].tap()
        app.buttons["Move to Recently Deleted"].tap()
        app.buttons["Move recording"].tap()
        XCTAssertTrue(app.staticTexts["library.heading"].waitForExistence(timeout: 5))
        app.buttons["Recently deleted"].tap()
        app.buttons["Restore Cedar test conversation"].tap()
        app.buttons["Done"].tap()
        let restored = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cedar test conversation")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        restored.tap()
        XCTAssertEqual(app.staticTexts["recording.title"].label, "Cedar test conversation")
    }
}
