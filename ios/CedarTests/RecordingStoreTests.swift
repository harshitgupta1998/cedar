import AVFoundation
import XCTest
@testable import Cedar

final class RecordingStoreTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CedarTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeAudio(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for i in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][i] = 0.1 * sin(Float(i) * 2 * .pi * 440 / 16_000)
        }
        try file.write(from: buffer)
    }

    @MainActor
    func testSavedAudioSurvivesRelaunchRenameTrashAndRestore() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        let audio = store.audioURL(for: item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.deletingLastPathComponent().appendingPathComponent("manifest.json").path))
        try writeAudio(to: audio)
        let originalBytes = try Data(contentsOf: audio)
        try store.finish(id: item.id, duration: 0.9, status: .saved)
        try store.rename(store.recordings[0], to: "  Test conversation  ")

        let reopened = RecordingStore(root: location)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.recordings[0].title, "Test conversation")
        XCTAssertEqual(reopened.recordings[0].duration, 1, accuracy: 0.02)
        XCTAssertEqual(reopened.recordings[0].status, .saved)
        try reopened.moveToRecentlyDeleted(reopened.recordings[0])
        XCTAssertTrue(reopened.recordings.isEmpty)
        XCTAssertEqual(try Data(contentsOf: reopened.audioURL(for: item.id, deleted: true)), originalBytes)

        let afterTrashRelaunch = RecordingStore(root: location)
        XCTAssertEqual(afterTrashRelaunch.deletedRecordings.count, 1)
        try afterTrashRelaunch.restore(afterTrashRelaunch.deletedRecordings[0])
        XCTAssertTrue(afterTrashRelaunch.deletedRecordings.isEmpty)
        XCTAssertEqual(try Data(contentsOf: afterTrashRelaunch.audioURL(for: item.id)), originalBytes)
        XCTAssertEqual(afterTrashRelaunch.recordings[0].title, "Test conversation")
    }

    @MainActor
    func testUnfinishedRecordingRecoversWithoutChangingAudio() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        try writeAudio(to: store.audioURL(for: item.id))
        let original = try Data(contentsOf: store.audioURL(for: item.id))
        let reopened = RecordingStore(root: location)
        XCTAssertEqual(reopened.recordings[0].status, .recovered)
        XCTAssertEqual(reopened.recordings[0].duration, 1, accuracy: 0.02)
        XCTAssertEqual(try Data(contentsOf: reopened.audioURL(for: item.id)), original)
        XCTAssertEqual(RecordingStore(root: location).recordings[0].status, .recovered)
    }

    @MainActor
    func testUnreadableAudioIsKeptAndMarkedForRecovery() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        let invalid = Data("unfinished audio bytes".utf8)
        try invalid.write(to: store.audioURL(for: item.id))
        let reopened = RecordingStore(root: location)
        XCTAssertEqual(reopened.recordings[0].status, .needsRecovery)
        XCTAssertThrowsError(try reopened.retryRecovery(for: item.id))
        XCTAssertEqual(try Data(contentsOf: reopened.audioURL(for: item.id)), invalid)
    }

    @MainActor
    func testCorruptManifestDoesNotDiscardSourceAudio() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        let audio = store.audioURL(for: item.id)
        try writeAudio(to: audio)
        let original = try Data(contentsOf: audio)
        try Data("invalid json".utf8).write(to: audio.deletingLastPathComponent().appendingPathComponent("manifest.json"))
        let reopened = RecordingStore(root: location)
        XCTAssertNotNil(reopened.recoveryNotice)
        XCTAssertEqual(reopened.recordings.first?.status, .recovered)
        XCTAssertEqual(try Data(contentsOf: audio), original)
    }

    @MainActor
    func testEmptyRenameAndDeletingActiveRecordingAreRejected() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        XCTAssertThrowsError(try store.rename(item, to: " \n "))
        XCTAssertThrowsError(try store.moveToRecentlyDeleted(item))
        XCTAssertEqual(store.recordings, [item])
    }

    @MainActor
    func testFailedManifestWriteKeepsAudioAndRecoversAfterStorageIsWritable() async throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        let audio = store.audioURL(for: item.id)
        try writeAudio(to: audio)
        let original = try Data(contentsOf: audio)
        let manifest = audio.deletingLastPathComponent().appendingPathComponent("manifest.json")
        let backup = manifest.appendingPathExtension("original")
        try FileManager.default.moveItem(at: manifest, to: backup)
        // A directory at the metadata destination deterministically makes the atomic write fail.
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.finish(id: item.id, duration: 1, status: .saved))
        XCTAssertEqual(store.recordings[0].status, .recording)
        XCTAssertEqual(try Data(contentsOf: audio), original)
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.moveItem(at: backup, to: manifest)
        let reopened = RecordingStore(root: location)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.recordings[0].status, .recovered)
        XCTAssertEqual(try Data(contentsOf: audio), original)
    }

    @MainActor
    func testBackupManifestRestoresTitleAndPreservesDamagedMetadata() throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        let audio = store.audioURL(for: item.id)
        try writeAudio(to: audio)
        try store.finish(id: item.id, duration: 1, status: .saved)
        try store.rename(store.recordings[0], to: "Known title")
        try store.rename(store.recordings[0], to: "Newest title")
        let folder = audio.deletingLastPathComponent()
        let damaged = Data("damaged metadata".utf8)
        try damaged.write(to: folder.appendingPathComponent("manifest.json"))
        let reopened = RecordingStore(root: location)
        XCTAssertEqual(reopened.recordings[0].title, "Known title")
        XCTAssertEqual(reopened.recordings[0].status, .recovered)
        let copies = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copies.first)), damaged)
    }

    @MainActor
    func testOrphanAudioIsVisibleEvenWhenRepairCannotBeWritten() throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let folder = location.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("audio.caf")
        try writeAudio(to: audio)
        let original = try Data(contentsOf: audio)
        // A directory at the manifest path prevents metadata repair, but must not hide playable audio.
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("manifest.json"), withIntermediateDirectories: false)
        let store = RecordingStore(root: location)
        XCTAssertEqual(store.recordings.count, 1)
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(try Data(contentsOf: audio), original)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("manifest.json"))
        try store.retryRecovery(for: store.recordings[0].id)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.recordings[0].status, .recovered)
        XCTAssertEqual(RecordingStore(root: location).recordings.count, 1)
    }

    @MainActor
    func testRecoveryAndStaleDeleteCannotChangeActiveCapture() throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        try writeAudio(to: store.audioURL(for: item.id))
        store.reload(recoverUnfinished: true)
        XCTAssertEqual(store.recordings[0].status, .recording)
        XCTAssertThrowsError(try store.retryRecovery(for: item.id))
        var stale = item
        stale.status = .saved
        XCTAssertThrowsError(try store.moveToRecentlyDeleted(stale))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioURL(for: item.id).path))
    }

    @MainActor
    func testCorruptTextFilesRecoverLatestValidRevisions() throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let item = try store.create()
        try writeAudio(to: store.audioURL(for: item.id))
        try store.finish(id: item.id, duration: 1, status: .saved)
        var transcript = Transcript(recordingID: item.id, localeID: "en-US", provider: "test",
                                    segments: [TranscriptSegment(startMS: 0, endMS: 900, text: "First text")])
        transcript = try store.saveTranscript(transcript)
        let first = transcript
        transcript.segments[0].text = "Second text"
        _ = try store.saveTranscript(transcript)
        let folder = store.audioURL(for: item.id).deletingLastPathComponent()
        try Data("bad transcript".utf8).write(to: folder.appendingPathComponent("transcript.json"))
        XCTAssertEqual(try store.loadTranscript(for: item.id), first)
        let notes = LocalNotes(recordingID: item.id, transcriptRevision: first.revision,
                               transcriptFingerprint: LocalNotes.fingerprint(first), modelID: "test",
                               createdAt: Date(), processingSeconds: 1, text: "Original notes")
        try store.saveNotes(notes)
        try store.saveNotes(notes)
        try Data("bad notes".utf8).write(to: folder.appendingPathComponent("notes.json"))
        XCTAssertEqual(try store.loadNotes(for: item.id), notes)
        XCTAssertNotNil(store.recoveryNotice)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Recovery").path).count, 2)
    }

}

extension RecordingStoreTests {
    @MainActor
    func testBookmarksPersistThroughCaptureRecoveryRenameTrashAndRestoreWithoutChangingAudio() throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let recording = try store.create()
        try writeAudio(to: store.audioURL(for: recording.id))
        let originalAudio = try Data(contentsOf: store.audioURL(for: recording.id))
        let first = try store.addBookmark(recordingID: recording.id, seconds: 0.234, title: "Decision")
        XCTAssertEqual(first.positionMS, 234)
        XCTAssertEqual(store.recordings[0].status, .recording)
        try store.finish(id: recording.id, duration: 1, status: .saved)
        _ = try store.addBookmark(recordingID: recording.id, seconds: 0.1, title: "Earlier")
        XCTAssertEqual(try store.loadBookmarks(for: recording.id).items.map(\.positionMS), [100, 234])
        let reopened = RecordingStore(root: location)
        XCTAssertEqual(try reopened.loadBookmarks(for: recording.id).items[1], first)
        try reopened.renameBookmark(first, recordingID: recording.id, title: "Final decision")
        XCTAssertThrowsError(try reopened.renameBookmark(first, recordingID: recording.id, title: "Stale label"))
        XCTAssertThrowsError(try reopened.removeBookmark(first, recordingID: recording.id))
        try reopened.moveToRecentlyDeleted(reopened.recordings[0])
        XCTAssertThrowsError(try reopened.loadBookmarks(for: recording.id))
        try reopened.restore(reopened.deletedRecordings[0])
        let recovered = try reopened.loadBookmarks(for: recording.id).items[1]
        XCTAssertEqual(recovered.title, "Final decision")
        XCTAssertEqual(recovered.positionMS, first.positionMS)
        try reopened.removeBookmark(recovered, recordingID: recording.id)
        XCTAssertEqual(try reopened.loadBookmarks(for: recording.id).items.count, 1)
        XCTAssertEqual(try Data(contentsOf: reopened.audioURL(for: recording.id)), originalAudio)
    }

    @MainActor
    func testBookmarkValidationAndCorruptFilesCannotOverwriteExistingData() throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let recording = try store.create()
        try writeAudio(to: store.audioURL(for: recording.id))
        try store.finish(id: recording.id, duration: 1, status: .saved)
        for time in [-1.0, .infinity, .nan, 1e30, 2] {
            XCTAssertThrowsError(try store.addBookmark(recordingID: recording.id, seconds: time))
        }
        let bookmark = try store.addBookmark(recordingID: recording.id, seconds: 0.5)
        let file = location.appendingPathComponent(recording.id.uuidString).appendingPathComponent("bookmarks.json")
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try store.renameBookmark(bookmark, recordingID: recording.id, title: " \n"))
        XCTAssertThrowsError(try store.renameBookmark(bookmark, recordingID: recording.id, title: String(repeating: "x", count: 201)))
        XCTAssertEqual(try Data(contentsOf: file), before)
        let corrupt = Data("damaged bookmarks".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store.addBookmark(recordingID: recording.id, seconds: 0.7))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        let future = RecordingBookmarks(formatVersion: 99, recordingID: recording.id, items: [])
        let futureBytes = try JSONEncoder().encode(future)
        try futureBytes.write(to: file)
        XCTAssertThrowsError(try store.addBookmark(recordingID: recording.id, seconds: 0.7))
        XCTAssertEqual(try Data(contentsOf: file), futureBytes)
    }

    @MainActor
    func testBookmarksRemainWithAnUnfinishedRecordingAfterColdRecovery() throws {
        let location = root()
        defer { try? FileManager.default.removeItem(at: location) }
        let store = RecordingStore(root: location)
        let recording = try store.create()
        try writeAudio(to: store.audioURL(for: recording.id))
        let mark = try store.addBookmark(recordingID: recording.id, seconds: 0.7)
        let reopened = RecordingStore(root: location)
        XCTAssertEqual(reopened.recordings[0].status, .recovered)
        XCTAssertEqual(try reopened.loadBookmarks(for: recording.id).items, [mark])
    }
}
