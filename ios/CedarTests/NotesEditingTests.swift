import Darwin
import os
import XCTest
@testable import Cedar

final class NotesEditingTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (RecordingStore, LocalNotes, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarEditTests-\(UUID().uuidString)")
        let store = RecordingStore(root: root)
        let item = try store.create()
        try store.finish(id: item.id, duration: 1, status: .saved)
        let transcript = try store.saveTranscript(Transcript(recordingID: item.id, localeID: "en-US", provider: "test",
            segments: [TranscriptSegment(startMS: 0, endMS: 100, text: "Source words")]))
        let notes = LocalNotes(recordingID: item.id, transcriptRevision: transcript.revision,
                               transcriptFingerprint: LocalNotes.fingerprint(transcript), modelID: "old-model",
                               createdAt: Date(), processingSeconds: 1, text: "Original notes")
        try store.saveNotes(notes)
        return (store, notes, root)
    }

    @MainActor
    func testEditsPersistAndEarlierNotesCanBeRestored() throws {
        let (store, original, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.editNotes(original, text: "Corrected notes")
        let edited = try XCTUnwrap(RecordingStore(root: root).loadNotes(for: original.recordingID))
        XCTAssertTrue(edited.isEdited)
        XCTAssertEqual(edited.text, "Corrected notes")
        XCTAssertEqual(edited.transcriptFingerprint, original.transcriptFingerprint)
        let revision = try XCTUnwrap(store.notesRevisions(for: original.recordingID).first)
        XCTAssertEqual(revision.notes, original)
        try store.restoreNotes(revision, replacing: edited)
        XCTAssertEqual(try store.loadNotes(for: original.recordingID)?.text, original.text)
        XCTAssertEqual(try store.notesRevisions(for: original.recordingID).count, 2)
    }

    @MainActor
    func testConcurrentEditsAndEmptyTextCannotOverwriteSavedNotes() throws {
        let (store, original, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try store.editNotes(original, text: " \n "))
        XCTAssertEqual(try store.loadNotes(for: original.recordingID), original)
        try store.editNotes(original, text: "Newer edit")
        XCTAssertThrowsError(try store.editNotes(original, text: "Stale edit"))
        let revision = try XCTUnwrap(store.notesRevisions(for: original.recordingID).first)
        XCTAssertThrowsError(try store.restoreNotes(revision, replacing: original))
        XCTAssertEqual(try store.loadNotes(for: original.recordingID)?.text, "Newer edit")
    }

    @MainActor
    func testEditingOutdatedNotesPreservesTheirOriginalSourceIdentity() throws {
        let (store, original, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var transcript = try XCTUnwrap(store.loadTranscript(for: original.recordingID))
        transcript.segments[0].text = "Changed source"
        transcript = try store.saveTranscript(transcript)
        try store.editNotes(original, text: "Manual correction")
        let edited = try XCTUnwrap(store.loadNotes(for: original.recordingID))
        XCTAssertFalse(edited.matches(transcript))
        XCTAssertEqual(edited.transcriptRevision, original.transcriptRevision)
        XCTAssertEqual(edited.transcriptFingerprint, original.transcriptFingerprint)
    }

    @MainActor
    func testTerminatedDownloadStagingIsCleanedWithoutRemovingOtherFiles() throws {
        let folder = NotesModel.directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent("download-\(UUID().uuidString).partial")
        let other = folder.appendingPathComponent("test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: other) }
        try Data("staging".utf8).write(to: partial)
        try Data("other".utf8).write(to: other)
        _ = NotesController()
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(try Data(contentsOf: other), Data("other".utf8))
    }

    @MainActor
    func testLargerModelProducesFinalSummaryWithoutReasoningTags() async throws {
        let model = NotesModel.qwen17
        guard FileManager.default.fileExists(atPath: model.installedURL.path) else {
            throw XCTSkip("Install the optional Qwen3 model for real inference.")
        }
        let start = Date()
        let available = os_proc_available_memory()
        let text = try await LocalNotesEngine().summarize("The proposal is pending. Sam might review it if approved. No work is assigned yet.",
                                                        modelURL: model.installedURL, model: model)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("CEDAR_LARGER_MODEL_SECONDS \(Date().timeIntervalSince(start))")
        print("CEDAR_LARGER_MODEL_AVAILABLE_BYTES \(available)")
        print("CEDAR_LARGER_MODEL_PEAK_RESIDENT_BYTES \(usage.ru_maxrss)")
        print("CEDAR_LARGER_MODEL_SYNTHETIC_SUMMARY \(text)")
        XCTAssertFalse(text.contains("<think>"))
        XCTAssertFalse(text.contains("</think>"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("pending") || text.localizedCaseInsensitiveContains("approval"))
    }
}
