import AVFoundation
import XCTest
@testable import Cedar

final class LocalNotesTests: XCTestCase {
    @MainActor
    func testNotesPersistDetectTranscriptChangesAndFollowTrashRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarNotesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(root: root)
        let item = try store.create()
        try store.finish(id: item.id, duration: 1, status: .saved)
        var transcript = try store.saveTranscript(Transcript(recordingID: item.id, localeID: "en-US", provider: "test",
            segments: [TranscriptSegment(startMS: 0, endMS: 100, text: "Review Cedar on Friday.")]))
        let notes = LocalNotes(recordingID: item.id, transcriptRevision: transcript.revision,
                               transcriptFingerprint: LocalNotes.fingerprint(transcript), modelID: "test",
                               createdAt: Date(), processingSeconds: 1, text: "Review Cedar on Friday.")
        try store.saveNotes(notes)
        XCTAssertEqual(try RecordingStore(root: root).loadNotes(for: item.id), notes)
        try store.saveNotes(notes)
        let revisions = root.appendingPathComponent(item.id.uuidString).appendingPathComponent("NotesRevisions")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: revisions.path).count, 1)
        transcript.segments[0].text = "Review Cedar on Monday."
        transcript = try store.saveTranscript(transcript)
        XCTAssertFalse(notes.matches(transcript))
        XCTAssertThrowsError(try store.saveNotes(notes))
        XCTAssertEqual(try store.loadNotes(for: item.id), notes)
        try store.moveToRecentlyDeleted(store.recordings[0])
        try store.restore(store.deletedRecordings[0])
        XCTAssertEqual(try store.loadNotes(for: item.id), notes)
    }

    @MainActor
    func testNotesArchiveFailurePreservesPreviousNotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarNotesFailure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(root: root)
        let item = try store.create()
        try store.finish(id: item.id, duration: 1, status: .saved)
        let transcript = try store.saveTranscript(Transcript(recordingID: item.id, localeID: "en-US", provider: "test",
            segments: [TranscriptSegment(startMS: 0, endMS: 100, text: "Source")]))
        let notes = LocalNotes(recordingID: item.id, transcriptRevision: transcript.revision,
                               transcriptFingerprint: LocalNotes.fingerprint(transcript), modelID: "test",
                               createdAt: Date(), processingSeconds: 1, text: "Original notes")
        try store.saveNotes(notes)
        let blocker = root.appendingPathComponent(item.id.uuidString).appendingPathComponent("NotesRevisions")
        try Data("block archive".utf8).write(to: blocker)
        XCTAssertThrowsError(try store.saveNotes(notes))
        XCTAssertEqual(try store.loadNotes(for: item.id), notes)
    }

    func testInvalidModelCannotPassVerification() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid model".utf8).write(to: url)
        XCTAssertThrowsError(try NotesController.verifyModel(at: url))
    }

    @MainActor
    func testLocalModelSummarizesSyntheticNote() async throws {
        let url = NotesController.installedModelURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Install the pinned 271 MB model to run real offline inference.")
        }
        let engine = LocalNotesEngine()
        let source = "We tested Cedar today. Offline transcription and saving edits both worked. Maya will test a longer recording on Friday. We decided to keep audio on the phone."
        let start = ContinuousClock.now
        let text = try await engine.summarize(source, modelURL: url)
        print("CEDAR_SYNTHETIC_NOTES \(text)")
        print("CEDAR_NOTES_ELAPSED \(start.duration(to: .now))")
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Cedar") || text.localizedCaseInsensitiveContains("transcription"))
        let longerSource = """
        Today we reviewed the Cedar recording app. Offline transcription worked on a short recording, and the text edits were still there after closing and reopening the app. We have not finished the thirty-minute recording test yet. Please do not mark that as complete. Maya volunteered to do that test on Friday. She will record for thirty minutes with Airplane Mode on and the screen locked, then listen near the start and the end. If it fails, she will write down the duration shown by the app.
        
        We discussed adding automatic cloud uploads. Alex suggested sending every recording to a server as soon as it finishes. After discussing privacy, we rejected that suggestion. The agreed decision is to keep recording and transcription on the phone. A future cloud option would require the user to choose it explicitly. We are not building that cloud option this week.
        
        The next thing we want to evaluate is a small local model for summaries. It should run after transcription has finished. We should measure how long it takes, how much memory it uses, and whether it invents facts. Jordan will compare the generated notes with the transcript on Monday. Jordan is checking accuracy, while Maya is checking recording reliability. Those are different tasks on different days.
        
        There was a question about renaming Cedar to another name. Nobody made a decision on that today. We also discussed possible support for Spanish, but no one was assigned that work and there is no deadline. The first experiment will use English transcripts. We agreed that the first release of offline notes should be labeled experimental.
        
        To wrap up, our immediate tasks are Maya's longer recording test on Friday and Jordan's summary accuracy review on Monday. The app name stays Cedar for now. We should review the experiment after both tasks are complete before deciding whether the small model is good enough for longer conversations.
        """
        let longerStart = ContinuousClock.now
        let longerNotes = try await engine.summarize(longerSource, modelURL: url)
        print("CEDAR_LONGER_SYNTHETIC_NOTES \(longerNotes)")
        print("CEDAR_LONGER_NOTES_ELAPSED \(longerStart.duration(to: .now))")
        XCTAssertTrue(longerNotes.contains("Friday"))
        XCTAssertTrue(longerNotes.contains("Monday"))
        do {
            _ = try await engine.summarize(String(repeating: "Long transcript. ", count: 5_000), modelURL: url)
            XCTFail("Oversized input must produce a clear error without truncation")
        } catch NotesError.inputTooLong { }
    }
}
