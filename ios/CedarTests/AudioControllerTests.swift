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
