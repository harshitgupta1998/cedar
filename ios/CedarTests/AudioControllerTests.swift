import AVFoundation
import Combine
import XCTest
@testable import Cedar

final class AudioControllerTests: XCTestCase {
    @MainActor
    private func requireSimulatorMicrophone() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Audio integration tests only run on the simulator.")
        #endif
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw XCTSkip("Grant microphone access to Cedar in the simulator before running audio integration tests.")
        }
    }

    @MainActor
    private func verifyRecordingStops(for name: Notification.Name, userInfo: [AnyHashable: Any]?) async throws {
        try requireSimulatorMicrophone()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarAudioTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(root: root)
        let notifications = NotificationCenter()
        let controller = AudioController(store: store, notifications: notifications)
        defer { controller.stopRecording(); controller.stopPlayback() }
        await controller.startRecording()
        let id = try XCTUnwrap(controller.recordingID, controller.errorMessage ?? "Microphone did not start")
        // Capture real frames through AVAudioRecorder before injecting the system notification.
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertGreaterThan(controller.elapsed, 0)
        let stopped = expectation(description: "Interruption stops the recorder")
        let observation = controller.$recordingID.dropFirst().filter { $0 == nil }.prefix(1).sink { _ in stopped.fulfill() }
        notifications.post(name: name, object: AVAudioSession.sharedInstance(), userInfo: userInfo)
        await fulfillment(of: [stopped], timeout: 3)
        withExtendedLifetime(observation) { }
        XCTAssertNil(controller.recordingID)
        let item = try XCTUnwrap(store.recordings.first { $0.id == id })
        XCTAssertEqual(item.status, .interrupted)
        XCTAssertGreaterThan(item.duration, 0)
        XCTAssertNotNil(RecordingStore.readableDuration(at: store.audioURL(for: id)))
        XCTAssertEqual(RecordingStore(root: root).recordings[0].status, .interrupted)
        // Ending an interruption must never reopen the microphone without a new Record tap.
        notifications.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(controller.recordingID)
        controller.togglePlayback(item)
        XCTAssertTrue(controller.isPlaying, controller.errorMessage ?? "Retained audio did not play")
        controller.stopPlayback()
    }

    @MainActor
    func testInterruptionKeepsAudioAndDoesNotAutomaticallyResume() async throws {
        try await verifyRecordingStops(for: AVAudioSession.interruptionNotification, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ])
    }

    @MainActor
    func testDisconnectedInputKeepsAudio() async throws {
        try await verifyRecordingStops(for: AVAudioSession.routeChangeNotification, userInfo: [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        ])
    }

    @MainActor
    func testMediaServiceResetKeepsAudio() async throws {
        try await verifyRecordingStops(for: AVAudioSession.mediaServicesWereResetNotification, userInfo: nil)
    }
}

extension AudioControllerTests {
    @MainActor
    func testLiveBookmarksUseRecorderClockAndFailureDoesNotStopCapture() async throws {
        try requireSimulatorMicrophone()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarBookmarkCapture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(root: root)
        let controller = AudioController(store: store)
        defer { controller.stopRecording(); controller.stopPlayback() }
        await controller.startRecording()
        let id = try XCTUnwrap(controller.recordingID)
        try await Task.sleep(for: .seconds(1))
        controller.bookmarkRecordingMoment()
        let mark = try XCTUnwrap(store.loadBookmarks(for: id).items.first)
        XCTAssertGreaterThan(mark.positionMS, 500)
        XCTAssertEqual(controller.recordingID, id)
        XCTAssertEqual(store.recordings[0].status, .recording)
        let elapsed = controller.elapsed
        let file = root.appendingPathComponent(id.uuidString).appendingPathComponent("bookmarks.json")
        let damaged = Data("bad file".utf8)
        try damaged.write(to: file)
        controller.bookmarkRecordingMoment()
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(controller.recordingID, id)
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThan(controller.elapsed, elapsed)
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        controller.stopRecording()
        XCTAssertEqual(store.recordings[0].status, .saved)
        XCTAssertGreaterThan(store.recordings[0].duration, 1.5)
        XCTAssertNotNil(RecordingStore.readableDuration(at: store.audioURL(for: id)))
    }

    @MainActor
    func testPausedPlaybackBookmarksUseActualPlayerPosition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarBookmarkPlayback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(root: root)
        let item = try store.create()
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let file = try AVAudioFile(forWriting: store.audioURL(for: item.id), settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000)!
            buffer.frameLength = 32_000
            buffer.floatChannelData![0].initialize(repeating: 0, count: 32_000)
            try file.write(from: buffer)
        }
        try store.finish(id: item.id, duration: 2, status: .saved)
        let controller = AudioController(store: store)
        defer { controller.stopPlayback() }
        XCTAssertThrowsError(try controller.bookmarkPlaybackPosition())
        controller.togglePlayback(store.recordings[0])
        controller.pausePlayback()
        controller.seek(to: 0.75)
        let bookmark = try controller.bookmarkPlaybackPosition()
        XCTAssertEqual(bookmark.positionMS, 750, accuracy: 2)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(try store.loadBookmarks(for: item.id).items, [bookmark])
    }
}
