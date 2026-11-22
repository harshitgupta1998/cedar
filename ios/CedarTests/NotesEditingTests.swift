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
    func testReplacementModelProducesFinalSummaryWithoutReasoningTags() async throws {
        let model = NotesModel.qwen06
        guard FileManager.default.fileExists(atPath: model.installedURL.path) else {
            throw XCTSkip("Install the 397 MB Qwen3 model for real inference.")
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
    @MainActor
    func testHourEquivalentTranscriptOnPhysicalDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Hour-length Metal inference is checked by the Mac benchmark and physical-device run.")
        #else
        let model = NotesModel.qwen06
        guard FileManager.default.fileExists(atPath: model.installedURL.path) else {
            throw XCTSkip("Install Qwen3 0.6B for the hour-length device benchmark.")
        }
        let facts = [
            "Maya will test recording on Monday. Automatic cloud uploads were rejected.",
            "Jordan will check summary accuracy on Tuesday. The app name stays Cedar.",
            "Priya will review the demo on Wednesday. No replacement recorder was approved.",
            "Lee will send invitations on Thursday. The final approved budget is 350 dollars.",
            "Riya will export only text notes on Saturday. Audio must stay on the phone.",
            "Noor will review microphone permissions on Tuesday. The appointment is at 3 pm, not 2 pm.",
            "Sam might review the proposal if approved. The proposal is pending and no work is assigned to Sam.",
            "Alex already sent the invoice. No further client email is required.",
            "Zoe will review transcripts on Friday. Spanish support has no owner or deadline."
        ]
        let filler = "We reviewed this topic carefully during the meeting. The discussion repeated the same facts without adding a new decision. Participants checked the existing notes against the source and agreed that accuracy matters. No additional owners, deadlines or tasks were assigned during this discussion."
        // About 9,000 words, equivalent to an hour at 150 spoken words/minute.
        let source = facts.map { fact in
            ([fact] + Array(repeating: filler, count: 23) + [fact]).joined(separator: " ")
        }.joined(separator: "\n\n")
        let start = Date()
        let available = os_proc_available_memory()
        let output = try await LocalNotesEngine().summarize(source, modelURL: model.installedURL) { section, total in
            print("CEDAR_HOUR_PROGRESS \(section)/\(total)")
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let sections = output.components(separatedBy: "\n").filter { $0.range(of: #"^Section [0-9]+ of [0-9]+$"#, options: .regularExpression) != nil }.count
        let missing = ["Maya", "Monday", "Jordan", "Tuesday", "Priya", "Wednesday", "Lee", "Thursday", "350", "Riya", "Saturday", "Noor", "3 pm", "Sam", "pending", "Alex", "invoice", "Zoe", "Friday"].filter { !output.localizedCaseInsensitiveContains($0) }
        let report: [String: Any] = ["modelID": model.rawValue, "promptVersion": model.promptVersion,
            "environment": "Physical iPhone 13 / Metal / XCTest; synthetic text, not audio",
            "sourceWords": source.split(whereSeparator: \.isWhitespace).count,
            "seconds": Date().timeIntervalSince(start), "availableBytesAtStart": available,
            "peakResidentMiB": Double(usage.ru_maxrss) / 1_048_576, "sections": sections,
            "missingFacts": missing, "output": output]
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("qwen06-hour-benchmark.json"), options: .atomic)
        print("CEDAR_HOUR_SECONDS \(Date().timeIntervalSince(start))")
        print("CEDAR_HOUR_AVAILABLE_BYTES \(available)")
        print("CEDAR_HOUR_PEAK_RESIDENT_BYTES \(usage.ru_maxrss)")
        print("CEDAR_HOUR_MISSING_FACTS \(missing)")
        XCTAssertGreaterThan(sections, 8)
        XCTAssertTrue(output.contains("Maya") && output.contains("Monday"))
        XCTAssertTrue(output.contains("Zoe") && output.contains("Friday"))
        XCTAssertTrue(output.contains("Section \(sections) of \(sections)"))
        XCTAssertFalse(output.contains("<think>"))
        #endif
    }

}

extension NotesEditingTests {
    @MainActor
    private func featureFixture() throws -> (RecordingStore, LocalNotes, SuggestedAction, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CedarFeatures-\(UUID())")
        let store = RecordingStore(root: root)
        let item = try store.create()
        try store.finish(id: item.id, duration: 10, status: .saved)
        let transcript = try store.saveTranscript(Transcript(recordingID: item.id, localeID: "en-US", provider: "test",
            segments: [TranscriptSegment(startMS: 2000, endMS: 9000, text: "Maya will test Cedar on Friday.")]))
        let text = """
        Summary
        Maya will test Cedar on Friday.

        Action items
        • Test Cedar
          Owner: Maya · Due: Friday
          Source: “Maya will test Cedar on Friday.”

        Suggested follow-ups · Not commitments
        • What should we test next?
        """
        let notes = LocalNotes(recordingID: item.id, transcriptRevision: transcript.revision,
                               transcriptFingerprint: LocalNotes.fingerprint(transcript), modelID: "test",
                               createdAt: Date(), processingSeconds: 1, text: text)
        try store.saveNotes(notes)
        return (store, notes, try XCTUnwrap(SuggestedAction.parse(text).first), root)
    }

    func testSourceReferencesSpanSegmentsAndOfferRepeatedOccurrences() {
        let first = TranscriptSegment(startMS: 0, endMS: 1000, text: "Maya will")
        let second = TranscriptSegment(startMS: 1000, endMS: 2000, text: "test Cedar on Friday.")
        let third = TranscriptSegment(startMS: 5000, endMS: 6000, text: "Maya will test Cedar on Friday.")
        let transcript = Transcript(recordingID: UUID(), localeID: "en-US", provider: "test", segments: [first, second, third])
        let matches = TranscriptSources.locations(for: "MAYA WILL\nTEST CEDAR ON FRIDAY.", in: transcript)
        XCTAssertEqual(matches.map(\.startMS), [0, 5000])
        XCTAssertEqual(matches.map(\.endMS), [2000, 6000])
        XCTAssertTrue(TranscriptSources.locations(for: "An invented sentence", in: transcript).isEmpty)
        XCTAssertTrue(TranscriptSources.locations(for: "  ", in: transcript).isEmpty)
    }

    @MainActor
    func testChecklistImportIsExplicitIdempotentAndSurvivesNotesEditsAndTrash() throws {
        let (store, notes, action, root) = try featureFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(try store.loadChecklist(for: notes.recordingID).items.isEmpty)
        let item = try store.addChecklistAction(action, notes: notes)
        XCTAssertEqual(item.owner, "Maya")
        XCTAssertEqual(item.due, "Friday")
        try store.setChecklistComplete(item, recordingID: notes.recordingID, complete: true)
        let duplicate = try store.addChecklistAction(action, notes: notes)
        XCTAssertEqual(duplicate.id, item.id)
        XCTAssertTrue(duplicate.isComplete)
        let reopened = RecordingStore(root: root)
        XCTAssertEqual(try reopened.loadChecklist(for: notes.recordingID).items.count, 1)
        try reopened.editNotes(notes, text: notes.text + "\nHuman correction")
        XCTAssertTrue(try reopened.loadChecklist(for: notes.recordingID).items[0].isComplete)
        try reopened.moveToRecentlyDeleted(reopened.recordings[0])
        XCTAssertThrowsError(try reopened.loadChecklist(for: notes.recordingID))
        try reopened.restore(reopened.deletedRecordings[0])
        XCTAssertEqual(try reopened.loadChecklist(for: notes.recordingID).items[0].id, item.id)
    }

    @MainActor
    func testChecklistEditsRemoveAttributionAndRejectStaleSnapshotsOrTranscript() throws {
        let (store, notes, action, root) = try featureFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try store.addChecklistAction(action, notes: notes)
        try store.saveChecklistTask(recordingID: notes.recordingID, original: item, title: "My corrected task", owner: "Me", due: "Tomorrow")
        let edited = try XCTUnwrap(store.loadChecklist(for: notes.recordingID).items.first)
        XCTAssertNil(edited.sourceQuote)
        XCTAssertNil(edited.transcriptFingerprint)
        XCTAssertThrowsError(try store.saveChecklistTask(recordingID: notes.recordingID, original: item, title: "Stale", owner: "", due: ""))
        XCTAssertThrowsError(try store.saveChecklistTask(recordingID: notes.recordingID, original: edited, title: " ", owner: "", due: ""))
        var transcript = try XCTUnwrap(store.loadTranscript(for: notes.recordingID))
        transcript.segments[0].text = "Maya will test Cedar on Monday."
        _ = try store.saveTranscript(transcript)
        XCTAssertThrowsError(try store.addChecklistAction(action, notes: notes))
        XCTAssertEqual(try store.loadChecklist(for: notes.recordingID).items[0], edited)
    }

    @MainActor
    func testCorruptChecklistIsPreservedAndCannotBeOverwrittenByAnAdd() throws {
        let (store, notes, action, root) = try featureFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(notes.recordingID.uuidString).appendingPathComponent("checklist.json")
        let damaged = Data("damaged checklist".utf8)
        try damaged.write(to: url)
        XCTAssertThrowsError(try store.addChecklistAction(action, notes: notes))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    @MainActor
    func testLocalSearchFindsTitleTranscriptAndNotesAndExcludesTrash() throws {
        let (store, notes, _, root) = try featureFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.rename(store.recordings[0], to: "Café pilot")
        XCTAssertTrue(try LibrarySearch.scan(store.recordings, root: root, query: "CAFE").snippets[notes.recordingID]?.hasPrefix("Title") == true)
        XCTAssertTrue(try LibrarySearch.scan(store.recordings, root: root, query: "Friday").snippets[notes.recordingID]?.hasPrefix("Transcript") == true)
        XCTAssertTrue(try LibrarySearch.scan(store.recordings, root: root, query: "commitments").snippets[notes.recordingID]?.hasPrefix("Notes") == true)
        XCTAssertTrue(try LibrarySearch.scan(store.recordings, root: root, query: "not present").snippets.isEmpty)
        try Data("bad JSON".utf8).write(to: root.appendingPathComponent(notes.recordingID.uuidString).appendingPathComponent("notes.json"))
        let incomplete = try LibrarySearch.scan(store.recordings, root: root, query: "Café")
        XCTAssertEqual(incomplete.unreadableFiles, 1)
        XCTAssertNotNil(incomplete.snippets[notes.recordingID])
        try store.moveToRecentlyDeleted(store.recordings[0])
        XCTAssertTrue(try LibrarySearch.scan(store.recordings, root: root, query: "Friday").snippets.isEmpty)
    }
}
