import AVFoundation
import Foundation

struct Recording: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case recording, saved, interrupted, recovered, needsRecovery

        var label: String {
            switch self {
            case .recording: return "Recording"
            case .saved: return "Saved on this iPhone"
            case .interrupted: return "Interrupted · audio kept"
            case .recovered: return "Recovered after app closed"
            case .needsRecovery: return "Audio needs recovery"
            }
        }
    }

    let id: UUID
    var title: String
    let createdAt: Date
    var duration: TimeInterval
    var status: Status
    let formatVersion: Int

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), duration: TimeInterval = 0,
         status: Status = .recording) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.status = status
        self.formatVersion = 1
    }
}

@MainActor
final class RecordingStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var deletedRecordings: [Recording] = []
    @Published private(set) var loadError: String?
    @Published private(set) var transcriptUpdates = 0
    let root: URL
    private let files = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
        reload(recoverUnfinished: true)
    }

    private static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--test-store"), args.indices.contains(index + 1),
           let id = UUID(uuidString: args[index + 1]) {
            return base.appendingPathComponent("CedarUITests/\(id.uuidString)", isDirectory: true)
        }
        #endif
        return base.appendingPathComponent("Recordings", isDirectory: true)
    }

    private var trash: URL { root.appendingPathComponent(".Trash", isDirectory: true) }

    private func directory(_ id: UUID, deleted: Bool = false) -> URL {
        (deleted ? trash : root).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func audioURL(for id: UUID, deleted: Bool = false) -> URL {
        directory(id, deleted: deleted).appendingPathComponent("audio.caf")
    }

    private func ensureDirectories() throws {
        for url in [root, trash] {
            try files.createDirectory(at: url, withIntermediateDirectories: true,
                                      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
    }

    private func write(_ recording: Recording, deleted: Bool = false) throws {
        let data = try JSONEncoder().encode(recording)
        try data.write(to: directory(recording.id, deleted: deleted).appendingPathComponent("manifest.json"),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func readDirectory(_ location: URL, deleted: Bool, recover: Bool) throws -> [Recording] {
        var result: [Recording] = []
        let directories = try files.contentsOfDirectory(at: location, includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles])
        for folder in directories {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            do {
                let manifest = folder.appendingPathComponent("manifest.json")
                var item = try JSONDecoder().decode(Recording.self, from: Data(contentsOf: manifest))
                guard item.id == id, item.formatVersion == 1 else { throw StoreError.invalidManifest }
                if recover && item.status == .recording {
                    let duration = Self.readableDuration(at: audioURL(for: id, deleted: deleted))
                    item.duration = duration ?? item.duration
                    item.status = duration != nil ? .recovered : .needsRecovery
                    try write(item, deleted: deleted)
                }
                result.append(item)
            } catch {
                // Preserve the folder and audio even if metadata cannot be decoded or updated.
                loadError = "Some recordings could not be loaded. Their files are still on this iPhone. Try reopening Cedar."
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    func reload(recoverUnfinished: Bool = false) {
        loadError = nil
        do {
            try ensureDirectories()
            recordings = try readDirectory(root, deleted: false, recover: recoverUnfinished)
            deletedRecordings = try readDirectory(trash, deleted: true, recover: recoverUnfinished)
        } catch {
            loadError = "Cedar couldn’t read its local library. Your existing files have not been removed."
        }
    }

    func create() throws -> Recording {
        try ensureDirectories()
        let capacity = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < 20_000_000 { throw StoreError.lowStorage }
        let item = Recording(title: "Recording \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        try files.createDirectory(at: directory(item.id), withIntermediateDirectories: false,
                                  attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        // The manifest exists before the microphone starts writing audio.
        try write(item)
        recordings.insert(item, at: 0)
        return item
    }

    func finish(id: UUID, duration: TimeInterval, status: Recording.Status) throws {
        guard var item = recordings.first(where: { $0.id == id }) else { throw StoreError.notFound }
        let readable = Self.readableDuration(at: audioURL(for: id))
        item.duration = readable ?? max(0, duration)
        item.status = readable == nil ? .needsRecovery : status
        try write(item)
        recordings[recordings.firstIndex(where: { $0.id == id })!] = item
    }

    func rename(_ item: Recording, to title: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        guard var current = recordings.first(where: { $0.id == item.id }) else { throw StoreError.notFound }
        current.title = String(title.prefix(120))
        try write(current)
        recordings[recordings.firstIndex(where: { $0.id == item.id })!] = current
    }

    func moveToRecentlyDeleted(_ item: Recording) throws {
        guard item.status != .recording else { throw StoreError.stillRecording }
        try ensureDirectories()
        try files.moveItem(at: directory(item.id), to: directory(item.id, deleted: true))
        reload()
    }

    func restore(_ item: Recording) throws {
        try files.moveItem(at: directory(item.id, deleted: true), to: directory(item.id))
        reload()
    }

    func loadTranscript(for id: UUID) throws -> Transcript? {
        let url = directory(id).appendingPathComponent("transcript.json")
        guard files.fileExists(atPath: url.path) else { return nil }
        let document = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: url))
        try document.validate(for: id)
        return document
    }

    @discardableResult
    func saveTranscript(_ document: Transcript) throws -> Transcript {
        guard let item = recordings.first(where: { $0.id == document.recordingID }), item.status != .recording else {
            throw StoreError.notFound
        }
        let previous = try loadTranscript(for: document.recordingID)
        var next = document
        next.revision = (previous?.revision ?? 0) + 1
        next.updatedAt = Date()
        try next.validate(for: item.id)
        if let previous {
            let archive = directory(item.id).appendingPathComponent("TranscriptRevisions", isDirectory: true)
            try files.createDirectory(at: archive, withIntermediateDirectories: true,
                                      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try JSONEncoder().encode(previous).write(to: archive.appendingPathComponent("revision-\(previous.revision).json"),
                                                     options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try JSONEncoder().encode(next).write(to: directory(item.id).appendingPathComponent("transcript.json"),
                                             options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        transcriptUpdates += 1
        return next
    }

    static func readableDuration(at url: URL) -> TimeInterval? {
        guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return nil }
        return player.duration
    }

    enum StoreError: LocalizedError {
        case lowStorage, notFound, invalidManifest, emptyTitle, stillRecording
        var errorDescription: String? {
            switch self {
            case .lowStorage: return "There is not enough free space to start. Free some storage on your iPhone and try again."
            case .notFound: return "This recording could not be found."
            case .invalidManifest: return "This recording’s metadata could not be read."
            case .emptyTitle: return "Please enter a name for the recording."
            case .stillRecording: return "Stop and save this recording before moving it."
            }
        }
    }
}
