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
            throw XCTSkip("Install the pinned 397 MB model to run real offline inference.")
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
            _ = try await engine.summarize(String(repeating: "Long transcript. ", count: 9_000), modelURL: url)
            XCTFail("Oversized input must produce a clear error without truncation")
        } catch NotesError.inputTooLong { }
    }
    func testHourLengthChunkPlanPreservesEveryWordAndStaysWithinBudget() throws {
        let source = (0..<10_800).map { "word\($0)." }.joined(separator: " ")
        let chunks = try NotesChunker.chunks(source) { $0.split(separator: " ").count <= 700 }
        XCTAssertGreaterThan(chunks.count, 10)
        XCTAssertLessThanOrEqual(chunks.count, NotesChunker.maxSections)
        XCTAssertEqual(chunks.joined(separator: " "), source)
        XCTAssertTrue(chunks.allSatisfy { $0.split(separator: " ").count <= 700 })
        XCTAssertTrue(chunks.last!.contains("word10799."))
    }

    func testChunkingHandlesWhitespaceAndRejectsUnprocessableInputWithoutTruncation() throws {
        let chunks = try NotesChunker.chunks("First.\n\nThen café 😊.\tFinally done.") {
            $0.split(separator: " ").count <= 3
        }
        XCTAssertEqual(chunks.joined(separator: " "), "First. Then café 😊. Finally done.")
        XCTAssertThrowsError(try NotesChunker.chunks(" \n\t") { _ in true })
        XCTAssertThrowsError(try NotesChunker.chunks("unbreakable") { _ in false })
        XCTAssertThrowsError(try NotesChunker.chunks(String(repeating: "x ", count: 16_001)) { _ in true })
        XCTAssertThrowsError(try NotesChunker.chunks(String(repeating: "x", count: 180_001)) { _ in true })
        XCTAssertThrowsError(try NotesChunker.chunks(String(repeating: "x ", count: 65)) {
            $0.split(separator: " ").count <= 1
        })
    }

    func testCancelledChunkPlanningStopsWithoutPartialResult() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try NotesChunker.chunks("First sentence. Second sentence.") { _ in true }
        }
        do { _ = try await task.value; XCTFail("Cancelled work must not return notes") }
        catch is CancellationError { }
    }

    func testRetiredWeightCleanupPreservesCurrentModelAndSavedDocuments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let retired = ["SmolLM2-360M-Q4_K_M.gguf", "Qwen3-1.7B-Q4_K_M.gguf"]
        let retained = ["Qwen3-0.6B-Q4_K_M.gguf", "notes.json", "audio.caf"]
        for file in retired + retained { try Data(file.utf8).write(to: root.appendingPathComponent(file)) }
        try NotesModel.removeRetiredModels(in: root)
        try NotesModel.removeRetiredModels(in: root)
        for file in retired { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path)) }
        for file in retained { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(file)), Data(file.utf8)) }
    }

    @MainActor
    func testMultiSectionInferenceUsesWholeSourceAndCancellationDoesNotSavePartialNotes() async throws {
        let model = NotesModel.qwen06
        guard FileManager.default.fileExists(atPath: model.installedURL.path) else {
            throw XCTSkip("Install Qwen3 0.6B for multi-section inference.")
        }
        let first = String(repeating: "Maya will test recording on Monday. No cloud upload was approved. ", count: 80)
        let last = String(repeating: "Zoe will review transcripts on Friday. Audio stays on this phone. ", count: 80)
        let result = try await LocalNotesEngine().summarize(first + last, modelURL: model.installedURL)
        XCTAssertTrue(result.contains("Section 1 of"))
        XCTAssertTrue(result.contains("Monday"))
        XCTAssertTrue(result.contains("Friday"))
        let count = result.components(separatedBy: "\n").filter { $0.range(of: #"^Section [0-9]+ of [0-9]+$"#, options: .regularExpression) != nil }.count
        XCTAssertGreaterThan(count, 1)
        XCTAssertTrue(result.contains("Section \(count) of \(count)"))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LocalNotesEngine().summarize(first, modelURL: model.installedURL)
        }
        do { _ = try await cancelled.value; XCTFail("Cancellation must throw, not return a partial summary") }
        catch is CancellationError { }
    }

    func testActionEvidenceAndMetadataAreCheckedAgainstActualSource() throws {
        let source = "Maya will test recording on Friday. Sam might review if approved. Jordan already sent the invoice."
        let json = #"""
        {"summary":"Maya will test on Friday; Sam's review is conditional and Jordan's invoice is complete.","actions":[
          {"task":"Test recording","owner":"Maya","due":"Friday","evidence":"Maya will test recording on Friday."},
          {"task":"Review the draft","owner":"Sam","due":null,"evidence":"Sam might review if approved."},
          {"task":"Send the invoice","owner":"Jordan","due":null,"evidence":"Jordan already sent the invoice."}
        ],"followUps":[{"text":"What approval is needed before Sam reviews?","evidence":"Sam might review if approved."}]}
        """#
        let parsed = try NotesSection.parse(json, source: source)
        XCTAssertEqual(parsed.actions.count, 1)
        XCTAssertEqual(parsed.actions[0].owner, "Maya")
        XCTAssertEqual(parsed.followUps.count, 1)
        XCTAssertEqual(parsed.omittedItems, 2)
        let wrongDate = json.replacingOccurrences(of: "\"due\":\"Friday\"", with: "\"due\":\"Monday\"")
        XCTAssertFalse(try NotesSection.parse(wrongDate, source: source).actions.contains { $0.due == "Monday" })
        let wrongOwner = json.replacingOccurrences(of: "\"owner\":\"Maya\"", with: "\"owner\":\"Alex\"")
        XCTAssertFalse(try NotesSection.parse(wrongOwner, source: source).actions.contains { $0.owner == "Alex" })
        let fakeQuote = json.replacingOccurrences(of: "Maya will test recording on Friday.", with: "Maya will call the client.")
        XCTAssertFalse(try NotesSection.parse(fakeQuote, source: source).actions.contains { $0.task.contains("client") })
    }

    func testUnassignedActionsAndSuggestedQuestionsRemainSeparate() throws {
        let source = "Please test recording. No owner was assigned and no deadline was agreed."
        let json = #"""
        {"summary":"Recording needs testing; the owner and deadline remain unspecified.","actions":[{"task":"Test recording","owner":null,"due":null,"evidence":"Please test recording."}],"followUps":[{"text":"Who will own the test and when is it needed?","evidence":"No owner was assigned and no deadline was agreed."},{"text":"Can we finish on Monday?","evidence":"No owner was assigned and no deadline was agreed."}]}
        """#
        let parsed = try NotesSection.parse(json, source: source)
        XCTAssertEqual(parsed.actions.count, 1)
        XCTAssertNil(parsed.actions[0].owner)
        XCTAssertNil(parsed.actions[0].due)
        XCTAssertEqual(parsed.followUps.count, 1)
        let output = NotesSection.render(overview: parsed.summary, sections: [parsed])
        XCTAssertTrue(output.contains("Owner: Not specified · Due: Not specified"))
        XCTAssertTrue(output.contains("Suggested follow-ups · Not commitments"))
        XCTAssertTrue(output.contains("Source: “Please test recording.”"))
    }

    func testNonActionsAndTranscriptCopiesCannotMasqueradeAsUsefulNotes() throws {
        let source = "Thursday is the final launch day. No further action is required."
        let json = #"""
        {"summary":"Launch is on Thursday and no additional action is needed.","actions":[{"task":"Final launch day","owner":"Thursday","due":"Thursday","evidence":"Thursday is the final launch day."}],"followUps":[{"text":"Should we launch?","evidence":"No further action is required."}]}
        """#
        let parsed = try NotesSection.parse(json, source: source)
        XCTAssertTrue(parsed.actions.isEmpty)
        XCTAssertTrue(parsed.followUps.isEmpty)
        XCTAssertThrowsError(try NotesSection.parse("not JSON", source: source))
        let echo = String(repeating: "Repeated transcript words. ", count: 60)
        let data = try JSONSerialization.data(withJSONObject: ["summary": echo, "actions": [], "followUps": []])
        XCTAssertThrowsError(try NotesSection.parse(String(decoding: data, as: UTF8.self), source: echo))
    }

    func testLongSummarySelectionKeepsCompleteSourceStatementsWithinBudget() throws {
        let source = "We reviewed the pilot. " + String(repeating: "The discussion repeated the same facts without a new decision. ", count: 30) + "The final approved budget is $350. Priya will review accuracy on Wednesday. The battery impact is still unknown."
        let selected = try NotesSourceSelection.select(source)
        XCTAssertLessThanOrEqual(selected.split(whereSeparator: \.isWhitespace).count, 90)
        XCTAssertTrue(selected.contains("The final approved budget is $350."))
        XCTAssertTrue(selected.contains("Priya will review accuracy on Wednesday."))
        XCTAssertTrue(selected.contains("The battery impact is still unknown."))
        XCTAssertTrue(selected.hasSuffix("."))
        XCTAssertLessThan(selected.count, source.count / 2)
    }

}
