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
        let originalTitle = field.value as? String ?? ""
        field.tap()
        field.typeText(" Cedar test conversation ")
        let renamedTitle = (field.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(renamedTitle.contains("Cedar test conversation"))
        XCTAssertNotEqual(renamedTitle, originalTitle)
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["recording.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["recording.title"].label, renamedTitle)
        app.buttons["Recording options"].tap()
        app.buttons["Move to Recently Deleted"].tap()
        app.buttons["Move recording"].tap()
        XCTAssertTrue(app.staticTexts["library.heading"].waitForExistence(timeout: 5))
        app.buttons["Recently deleted"].tap()
        app.buttons["Restore \(renamedTitle)"].tap()
        app.buttons["Done"].tap()
        let restored = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", renamedTitle)).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        restored.tap()
        XCTAssertEqual(app.staticTexts["recording.title"].label, renamedTitle)
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


    @MainActor
    func testTranscriptCapabilityCheckKeepsAudioAvailable() {
        openLibrary()
        startRecordingAndWaitForAudio()
        app.buttons["recorder.stop"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this iPhone."].waitForExistence(timeout: 5))
        let recording = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.tap()
        app.buttons["recording.transcript"].tap()
        XCTAssertTrue(app.staticTexts["transcript.capability"].waitForExistence(timeout: 20))
        // Checking support must not request recognition permission or process audio automatically.
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["playback.toggle"].waitForExistence(timeout: 5))
        app.buttons["playback.toggle"].tap()
        XCTAssertEqual(app.buttons["playback.toggle"].label, "Pause")
        app.buttons["playback.toggle"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testNotesEditPersistsAcrossRelaunchAndPreviousVersionRestores() {
        app.launchArguments.append("--notes-fixture")
        openLibrary()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch
        row.tap()
        app.buttons["recording.transcript"].tap()
        XCTAssertTrue(app.buttons["transcript.notes"].waitForExistence(timeout: 10))
        app.buttons["transcript.notes"].tap()
        let controls = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        controls.name = "Notes controls"
        controls.lifetime = .keepAlways
        add(controls)
        let edit = app.buttons["notes.edit"]
        for _ in 0..<3 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let field = app.textViews["notes.editField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" corrected")
        app.buttons["notes.save"].tap()
        app.terminate()
        openLibrary()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch.tap()
        app.buttons["recording.transcript"].tap()
        XCTAssertTrue(app.buttons["transcript.notes"].waitForExistence(timeout: 10))
        app.buttons["transcript.notes"].tap()
        let text = app.staticTexts["notes.text"]
        for _ in 0..<3 where !text.isHittable { app.swipeUp() }
        XCTAssertTrue(text.label.contains("corrected"))
        let history = app.buttons["notes.history"]
        for _ in 0..<3 where !history.isHittable { app.swipeUp() }
        history.tap()
        let restore = app.buttons["notes.restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.staticTexts["notes.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["notes.text"].label, "Original notes")
        let restored = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        restored.name = "Restored notes"
        restored.lifetime = .keepAlways
        add(restored)
        let copy = app.buttons["notes.copy"]
        for _ in 0..<3 where !copy.isHittable { app.swipeUp() }
        copy.tap()
        XCTAssertTrue(copy.label.contains("Copied"))
        let share = app.buttons["notes.share"]
        for _ in 0..<3 where !share.isHittable { app.swipeUp() }
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.cells["Save to Files"].exists, app.debugDescription)
        let sharing = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sharing.name = "Share notes"
        sharing.lifetime = .keepAlways
        add(sharing)
        app.otherElements["PopoverDismissRegion"].tap()
        XCTAssertTrue(app.buttons["notes.edit"].waitForExistence(timeout: 5))

    }

    @MainActor
    func testSearchSourcePlaybackAndChecklistPersistAcrossRelaunch() {
        app.launchArguments.append("--library-features-fixture")
        openLibrary()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Friday")
        let match = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.match.")).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        XCTAssertTrue(match.label.contains("Transcript"))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        search.typeText("not present")
        XCTAssertTrue(app.staticTexts.matching(identifier: "library.noSearchResults").firstMatch.waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 11))
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        let recording = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.tap()
        app.buttons["recording.transcript"].tap()
        XCTAssertTrue(app.buttons["transcript.notes"].waitForExistence(timeout: 10))
        app.buttons["transcript.notes"].tap()
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notes.source.")).firstMatch
        for _ in 0..<8 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable)
        XCTAssertTrue(source.label.contains("00:02"))
        source.tap()
        let pause = app.buttons["notes.pauseSource"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()
        let add = app.buttons["notes.addAction"].firstMatch
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertEqual(add.label, "Added to checklist")
        let checklist = app.buttons["notes.checklist"]
        for _ in 0..<4 where !checklist.isHittable { app.swipeUp() }
        XCTAssertTrue(checklist.isHittable)
        checklist.tap()
        let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "checklist.toggle.")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("Complete task"))
        toggle.tap()
        XCTAssertTrue(toggle.label.contains("Reopen task"))
        app.terminate()
        openLibrary()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recording.")).firstMatch.tap()
        app.buttons["recording.checklist"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("Reopen task"))
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "checklist.edit.")).firstMatch
        edit.tap()
        let title = app.descendants(matching: .any).matching(identifier: "checklist.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" revised ")
        app.buttons["checklist.save"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("revised"))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Persistent action checklist"
        image.lifetime = .keepAlways
        self.add(image)
    }

}
