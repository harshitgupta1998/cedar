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
        XCTAssertNotNil(reopened.loadError)
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

}
