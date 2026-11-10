import AVFoundation
import Combine
import XCTest
@testable import Cedar

@MainActor
private final class TestSpeechProvider: TranscriptionProvider {
    var response: Result<[TranscriptSegment], Error> = .success([
        TranscriptSegment(startMS: 0, endMS: 800, text: "Test words")
    ])
    var readiness: SpeechCapability.Readiness = .ready
    var maxDuration: TimeInterval?
    var delay: Duration?
    var ignoreCancellation = false
    var calls = 0
    var downloads = 0
    var cancellations = 0

    func capability(for localeID: String) async -> SpeechCapability {
        SpeechCapability(engine: .dictationAnalyzer, localeID: localeID, readiness: readiness,
                         message: readiness == .ready ? "Ready" : "Language download required", maxDuration: maxDuration)
    }
    func downloadModel(for capability: SpeechCapability) async throws { downloads += 1; readiness = .ready }
    func transcribe(url: URL, capability: SpeechCapability, progress: @escaping @MainActor (TimeInterval) -> Void) async throws -> [TranscriptSegment] {
        calls += 1
        if let delay {
            if ignoreCancellation { try? await Task.sleep(for: delay) }
            else { try await Task.sleep(for: delay) }
        }
        if !ignoreCancellation { try Task.checkCancellation() }
        progress(0.8)
        return try response.get()
    }
    func cancel() { cancellations += 1 }
}

final class TranscriptionTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (RecordingStore, Recording, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarTranscriptTests-\(UUID().uuidString)")
        let store = RecordingStore(root: root)
        let item = try store.create()
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let file = try AVAudioFile(forWriting: store.audioURL(for: item.id), settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
            buffer.frameLength = 16_000
            buffer.floatChannelData![0].initialize(repeating: 0, count: 16_000)
            try file.write(from: buffer)
        }
        try store.finish(id: item.id, duration: 1, status: .saved)
        return (store, store.recordings[0], root)
    }

    private func document(for item: Recording, text: String = "Original words") -> Transcript {
        Transcript(recordingID: item.id, localeID: "en-US", provider: "test",
                   segments: [TranscriptSegment(startMS: 0, endMS: 900, text: text)])
    }

    @MainActor
    private func runAndWait(_ controller: TranscriptionController, action: () -> Void) async {
        let finished = expectation(description: "Transcription operation finishes")
        var started = false
        let observation = controller.$activeRecordingID.sink { id in
            if id != nil { started = true }
            else if started { finished.fulfill() }
        }
        action()
        await fulfillment(of: [finished], timeout: 4)
        withExtendedLifetime(observation) { }
    }

    @MainActor
    func testTranscriptEditsPersistTimestampsAndArchivePreviousRevision() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try Data(contentsOf: store.audioURL(for: item.id))
        let first = try store.saveTranscript(document(for: item))
        var edited = first
        edited.edited = true
        edited.segments[0].text = "Corrected words"
        let second = try store.saveTranscript(edited)
        let reopened = RecordingStore(root: root)
        XCTAssertEqual(try reopened.loadTranscript(for: item.id), second)
        XCTAssertEqual(second.revision, 2)
        XCTAssertEqual(second.segments[0].startMS, first.segments[0].startMS)
        XCTAssertEqual(second.segments[0].endMS, first.segments[0].endMS)
        let archive = store.audioURL(for: item.id).deletingLastPathComponent().appendingPathComponent("TranscriptRevisions/revision-1.json")
        XCTAssertEqual(try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: archive)), first)
        XCTAssertEqual(try Data(contentsOf: store.audioURL(for: item.id)), bytes)
        try reopened.moveToRecentlyDeleted(reopened.recordings[0])
        try reopened.restore(reopened.deletedRecordings[0])
        XCTAssertEqual(try reopened.loadTranscript(for: item.id), second)
    }

    @MainActor
    func testInvalidTranscriptCannotReplaceSavedTextOrAudio() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.saveTranscript(document(for: item))
        var invalid = original
        invalid.segments[0].text = "  "
        XCTAssertThrowsError(try store.saveTranscript(invalid))
        let wrong = Transcript(recordingID: UUID(), localeID: "en-US", provider: "test", segments: original.segments)
        XCTAssertThrowsError(try store.saveTranscript(wrong))
        let badTime = Transcript(recordingID: item.id, localeID: "en-US", provider: "test",
                                 segments: [TranscriptSegment(startMS: 200, endMS: 100, text: "Invalid timing")])
        XCTAssertThrowsError(try store.saveTranscript(badTime))
        XCTAssertEqual(try store.loadTranscript(for: item.id), original)
        XCTAssertNotNil(RecordingStore.readableDuration(at: store.audioURL(for: item.id)))
    }

    @MainActor
    func testArchiveWriteFailureKeepsSavedTranscriptAndAudio() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.saveTranscript(document(for: item))
        let audio = try Data(contentsOf: store.audioURL(for: item.id))
        let archive = store.audioURL(for: item.id).deletingLastPathComponent().appendingPathComponent("TranscriptRevisions")
        try Data("blocked directory".utf8).write(to: archive)
        XCTAssertThrowsError(try store.saveTranscript(document(for: item, text: "Replacement")))
        XCTAssertEqual(try store.loadTranscript(for: item.id), original)
        XCTAssertEqual(try Data(contentsOf: store.audioURL(for: item.id)), audio)
    }

    @MainActor
    func testSuccessfulRecognitionPersistsOnlyFinalTranscript() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = TestSpeechProvider()
        let controller = TranscriptionController(store: store, provider: provider)
        await runAndWait(controller) { controller.transcribe(item, localeID: "en-US") }
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(try store.loadTranscript(for: item.id)?.text, "Test words")
        XCTAssertEqual(controller.processedThrough, 0.8)
    }

    @MainActor
    func testCancellationDiscardsLateRecognitionAndKeepsEditedTranscript() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = try store.saveTranscript(document(for: item))
        let provider = TestSpeechProvider()
        provider.delay = .seconds(3)
        provider.ignoreCancellation = true
        let controller = TranscriptionController(store: store, provider: provider)
        let finished = expectation(description: "Cancellation finishes")
        var started = false
        let observation = controller.$activeRecordingID.sink { id in
            if id != nil { started = true } else if started { finished.fulfill() }
        }
        controller.transcribe(item, localeID: "en-US")
        await Task.yield()
        controller.cancel(for: item.id)
        await fulfillment(of: [finished], timeout: 4)
        withExtendedLifetime(observation) { }
        XCTAssertEqual(try store.loadTranscript(for: item.id), previous)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(controller.phase.hasPrefix("Cancelled"))
    }

    @MainActor
    func testDeniedPermissionKeepsPreviousTranscriptAndOffersSettingsState() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = try store.saveTranscript(document(for: item))
        let provider = TestSpeechProvider()
        provider.response = .failure(TranscriptionError.permissionDenied)
        let controller = TranscriptionController(store: store, provider: provider)
        await runAndWait(controller) { controller.transcribe(item, localeID: "en-US") }
        XCTAssertTrue(controller.permissionDenied)
        XCTAssertEqual(try store.loadTranscript(for: item.id), previous)
    }

    @MainActor
    func testNoSpeechKeepsPreviousTranscript() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = try store.saveTranscript(document(for: item))
        let provider = TestSpeechProvider()
        provider.response = .success([])
        let controller = TranscriptionController(store: store, provider: provider)
        await runAndWait(controller) { controller.transcribe(item, localeID: "en-US") }
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(try store.loadTranscript(for: item.id), previous)
    }

    @MainActor
    func testLegacyDurationLimitPreventsRecognitionCall() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = TestSpeechProvider()
        provider.maxDuration = 0.5
        let controller = TranscriptionController(store: store, provider: provider)
        await runAndWait(controller) { controller.transcribe(item, localeID: "en-US") }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertNil(try store.loadTranscript(for: item.id))
    }

    @MainActor
    func testModelDownloadDoesNotStartRecognition() async throws {
        let (store, item, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = TestSpeechProvider()
        provider.readiness = .downloadRequired
        let controller = TranscriptionController(store: store, provider: provider)
        await runAndWait(controller) { controller.download(for: item, localeID: "en-US") }
        XCTAssertEqual(provider.downloads, 1)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(controller.capability?.readiness, .ready)
        XCTAssertNil(try store.loadTranscript(for: item.id))
    }
}
