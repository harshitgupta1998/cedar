import XCTest

final class CedarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if !targetEnvironment(simulator)
        throw XCTSkip("These tests use isolated simulator storage and must not run against a personal device library.")
        #endif
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--test-store", UUID().uuidString]
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    private func openLibrary() {
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome.heading"].waitForExistence(timeout: 10))
        app.buttons["welcome.getStarted"].tap()
        XCTAssertTrue(app.staticTexts["library.heading"].waitForExistence(timeout: 5))
    }

    private func startRecordingAndWaitForAudio() {
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
        startRecordingAndWaitForAudio()
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

    @MainActor
    func testRecordingRecoversAfterForceQuit() {
        openLibrary()
        startRecordingAndWaitForAudio()
        app.terminate()
        openLibrary()
        let recording = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        XCTAssertTrue(recording.label.contains("Recovered after app closed"))
        recording.tap()
        app.buttons["playback.toggle"].tap()
        XCTAssertEqual(app.buttons["playback.toggle"].label, "Pause")
        app.buttons["playback.toggle"].tap()
        XCTAssertEqual(app.staticTexts["playback.status"].label, "Paused")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testMicrophoneDenialPreservesSavedPlayback() {
        openLibrary()
        startRecordingAndWaitForAudio()
        app.buttons["recorder.stop"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this iPhone."].waitForExistence(timeout: 5))
        app.terminate()
        app.resetAuthorizationStatus(for: .microphone)
        defer {
            app.terminate()
            app.resetAuthorizationStatus(for: .microphone)
        }
        openLibrary()
        app.buttons["recorder.start"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        let deny = permission.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND label != %@", "Allow", "Allow")).firstMatch
        XCTAssertTrue(deny.exists)
        deny.tap()
        XCTAssertTrue(app.alerts["Cedar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Open Settings"].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["recorder.stop"].exists)
        let recording = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.tap()
        app.buttons["playback.toggle"].tap()
        XCTAssertEqual(app.buttons["playback.toggle"].label, "Pause")
        app.buttons["playback.toggle"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }


    @MainActor
    func testLibraryControlsInPortraitAndLandscape() {
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let getStarted = app.buttons["welcome.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        for _ in 0..<4 where !getStarted.isHittable { app.swipeUp() }
        XCTAssertTrue(getStarted.isHittable)
        getStarted.tap()
        XCTAssertTrue(app.staticTexts["library.heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recorder.start"].isHittable)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "Library — portrait"
        portrait.lifetime = .keepAlways
        add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        app.swipeUp()
        XCTAssertTrue(app.buttons["recorder.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recorder.start"].isHittable)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Library — landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
    }

}
