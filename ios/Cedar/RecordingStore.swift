import AVFoundation
import Foundation

struct NotesRevision: Identifiable {
    let id: UUID
    let notes: LocalNotes
}

struct Recording: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
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
    @Published private(set) var notesUpdates = 0
    @Published private(set) var checklistUpdates = 0
    @Published private(set) var bookmarkUpdates = 0
    @Published private(set) var recoveryNotice: String?
    private var activeRecordings = Set<UUID>()
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

    private func decodeRecording(_ data: Data, id: UUID) throws -> Recording {
        let item = try JSONDecoder().decode(Recording.self, from: data)
        guard item.id == id, item.formatVersion == 1, item.duration.isFinite, item.duration >= 0,
              item.createdAt.timeIntervalSinceReferenceDate.isFinite else { throw StoreError.invalidManifest }
        return item
    }

    private func write(_ recording: Recording, deleted: Bool = false) throws {
        let folder = directory(recording.id, deleted: deleted)
        let manifest = folder.appendingPathComponent("manifest.json")
        let data = try JSONEncoder().encode(recording)
        if let previous = try? Data(contentsOf: manifest),
           (try? decodeRecording(previous, id: recording.id)) != nil {
            try previous.write(to: folder.appendingPathComponent("manifest-backup.json"),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try data.write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func preserveDamagedFile(_ url: URL) throws {
        guard files.fileExists(atPath: url.path) else { return }
        let archive = url.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        try files.createDirectory(at: archive, withIntermediateDirectories: true,
                                  attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try files.copyItem(at: url, to: archive.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
    }

    private func readDirectory(_ location: URL, deleted: Bool, recover: Bool) throws -> [Recording] {
        var result: [Recording] = []
        let folders = try files.contentsOfDirectory(at: location, includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let manifest = folder.appendingPathComponent("manifest.json")
            var item: Recording
            var damagedManifest = false
            do {
                let data = try Data(contentsOf: manifest)
                // Preserve unsupported future formats for a newer app to open.
                if let future = try? JSONDecoder().decode(Recording.self, from: data), future.formatVersion != 1 {
                    loadError = "Some recordings need a newer version of Cedar. Their files are retained."
                    continue
                }
                item = try decodeRecording(data, id: id)
            } catch {
                damagedManifest = true
                if let data = try? Data(contentsOf: folder.appendingPathComponent("manifest-backup.json")),
                   let backup = try? decodeRecording(data, id: id) {
                    item = backup
                } else {
                    let date = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                    item = Recording(id: id, title: "Recovered recording", createdAt: date, status: .needsRecovery)
                }
            }
            let shouldRecover = damagedManifest || (recover && [.recording, .needsRecovery].contains(item.status))
            if shouldRecover && !activeRecordings.contains(id) {
                let duration = Self.readableDuration(at: audioURL(for: id, deleted: deleted))
                item.duration = duration ?? item.duration
                item.status = duration == nil ? .needsRecovery : .recovered
                do {
                    if damagedManifest { try preserveDamagedFile(manifest) }
                    try write(item, deleted: deleted)
                    if damagedManifest { recoveryNotice = "Recovered recording details. Review the recovered audio before relying on it." }
                } catch {
                    loadError = "Recovered files are visible, but Cedar couldn’t save their details. Free some storage and retry recovery."
                }
            }
            result.append(item)
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    func retryRecovery(for id: UUID) throws {
        guard !activeRecordings.contains(id) else { throw StoreError.stillRecording }
        reload(recoverUnfinished: true)
        guard let item = recordings.first(where: { $0.id == id }) else { throw StoreError.notFound }
        if item.status == .needsRecovery { throw StoreError.unreadableAudio }
    }

    private func loadRecoverable<T: Decodable>(at url: URL, revisions: String,
                                               validate: (T) throws -> Void, date: (T) -> Date) throws -> T? {
        let exists = files.fileExists(atPath: url.path)
        var originalError: Error?
        if exists {
            do {
                let document = try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
                try validate(document)
                return document
            } catch { originalError = error }
        }
        let archive = url.deletingLastPathComponent().appendingPathComponent(revisions)
        let candidates = (try? files.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)) ?? []
        let valid: [(T, Data)] = candidates.filter { $0.pathExtension == "json" }.compactMap { candidate in
            guard let data = try? Data(contentsOf: candidate),
                  let document = try? JSONDecoder().decode(T.self, from: data),
                  (try? validate(document)) != nil else { return nil }
            return (document, data)
        }
        guard let latest = valid.max(by: { date($0.0) < date($1.0) }) else {
            if let originalError { throw originalError }
            return nil
        }
        recoveryNotice = "Recovered an earlier saved revision. Review the restored text before continuing."
        do {
            try preserveDamagedFile(url)
            try latest.1.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            loadError = "An earlier revision is available, but Cedar couldn’t save the recovery. Its original files are retained."
        }
        return latest.0
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
        activeRecordings.insert(item.id)
        recordings.insert(item, at: 0)
        return item
    }

    func finish(id: UUID, duration: TimeInterval, status: Recording.Status) throws {
        defer { activeRecordings.remove(id) }
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
        guard let current = recordings.first(where: { $0.id == item.id }) else { throw StoreError.notFound }
        guard current.status != .recording, !activeRecordings.contains(item.id) else { throw StoreError.stillRecording }
        try ensureDirectories()
        try files.moveItem(at: directory(item.id), to: directory(item.id, deleted: true))
        reload()
    }

    func restore(_ item: Recording) throws {
        try files.moveItem(at: directory(item.id, deleted: true), to: directory(item.id))
        reload()
    }

    func loadTranscript(for id: UUID) throws -> Transcript? {
        try loadRecoverable(at: directory(id).appendingPathComponent("transcript.json"), revisions: "TranscriptRevisions",
                            validate: { (document: Transcript) in try document.validate(for: id) }, date: { $0.updatedAt })
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

    func loadNotes(for id: UUID) throws -> LocalNotes? {
        try loadRecoverable(at: directory(id).appendingPathComponent("notes.json"), revisions: "NotesRevisions",
                            validate: { (notes: LocalNotes) in try notes.validate(for: id) }, date: { $0.updatedAt ?? $0.createdAt })
    }

    func saveNotes(_ notes: LocalNotes) throws {
        guard let item = recordings.first(where: { $0.id == notes.recordingID }), item.status != .recording else {
            throw StoreError.notFound
        }
        try notes.validate(for: item.id)
        guard let transcript = try loadTranscript(for: item.id), notes.matches(transcript) else {
            throw NotesError.transcriptChanged
        }
        try writeNotes(notes)
    }

    func editNotes(_ original: LocalNotes, text: String) throws {
        guard try loadNotes(for: original.recordingID) == original else { throw NotesError.notesChanged }
        var edited = original
        edited.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.edited = true
        edited.updatedAt = Date()
        try writeNotes(edited)
    }

    func notesRevisions(for id: UUID) throws -> [NotesRevision] {
        let folder = directory(id).appendingPathComponent("NotesRevisions", isDirectory: true)
        guard files.fileExists(atPath: folder.path) else { return [] }
        return try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).compactMap { url in
            guard url.pathExtension == "json", let revisionID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url), let notes = try? JSONDecoder().decode(LocalNotes.self, from: data),
                  (try? notes.validate(for: id)) != nil else { return nil }
            return NotesRevision(id: revisionID, notes: notes)
        }.sorted { ($0.notes.updatedAt ?? $0.notes.createdAt) > ($1.notes.updatedAt ?? $1.notes.createdAt) }
    }

    func restoreNotes(_ revision: NotesRevision, replacing original: LocalNotes) throws {
        guard try loadNotes(for: original.recordingID) == original else { throw NotesError.notesChanged }
        let url = directory(original.recordingID).appendingPathComponent("NotesRevisions/\(revision.id.uuidString).json")
        var restored = try JSONDecoder().decode(LocalNotes.self, from: Data(contentsOf: url))
        try restored.validate(for: original.recordingID)
        restored.updatedAt = Date()
        try writeNotes(restored)
    }

    private func writeNotes(_ notes: LocalNotes) throws {
        guard let item = recordings.first(where: { $0.id == notes.recordingID }), item.status != .recording else {
            throw StoreError.notFound
        }
        try notes.validate(for: item.id)
        if let previous = try loadNotes(for: item.id) {
            let archive = directory(item.id).appendingPathComponent("NotesRevisions", isDirectory: true)
            try files.createDirectory(at: archive, withIntermediateDirectories: true,
                                      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try JSONEncoder().encode(previous).write(to: archive.appendingPathComponent("\(UUID().uuidString).json"),
                                                     options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try JSONEncoder().encode(notes).write(to: directory(item.id).appendingPathComponent("notes.json"),
                                              options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        notesUpdates += 1
    }

    func loadBookmarks(for id: UUID) throws -> RecordingBookmarks {
        guard recordings.contains(where: { $0.id == id }) else { throw StoreError.notFound }
        let url = directory(id).appendingPathComponent("bookmarks.json")
        guard files.fileExists(atPath: url.path) else { return RecordingBookmarks(formatVersion: 1, recordingID: id, items: []) }
        do {
            var document = try JSONDecoder().decode(RecordingBookmarks.self, from: Data(contentsOf: url))
            try document.validate(for: id)
            document.items.sort { $0.positionMS == $1.positionMS ? $0.createdAt < $1.createdAt : $0.positionMS < $1.positionMS }
            return document
        } catch { throw BookmarkError.unreadable }
    }

    private func writeBookmarks(_ document: RecordingBookmarks) throws {
        guard recordings.contains(where: { $0.id == document.recordingID }) else { throw StoreError.notFound }
        try document.validate(for: document.recordingID)
        try JSONEncoder().encode(document).write(to: directory(document.recordingID).appendingPathComponent("bookmarks.json"),
                                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        bookmarkUpdates += 1
    }

    @discardableResult
    func addBookmark(recordingID: UUID, seconds: TimeInterval, title: String? = nil) throws -> RecordingBookmark {
        guard let recording = recordings.first(where: { $0.id == recordingID }) else { throw StoreError.notFound }
        let milliseconds = seconds * 1000
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < Double(Int.max) else { throw BookmarkError.invalidPosition }
        if !activeRecordings.contains(recordingID) {
            guard ![.recording, .needsRecovery].contains(recording.status), seconds <= recording.duration + 0.001 else { throw BookmarkError.invalidPosition }
        }
        var document = try loadBookmarks(for: recordingID)
        let item = RecordingBookmark(id: UUID(), positionMS: Int(milliseconds.rounded(.down)),
                                     title: title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Bookmark at \(audioTime(seconds))", createdAt: Date())
        document.items.append(item)
        try writeBookmarks(document)
        return item
    }

    func renameBookmark(_ original: RecordingBookmark, recordingID: UUID, title: String) throws {
        var document = try loadBookmarks(for: recordingID)
        guard let index = document.items.firstIndex(where: { $0.id == original.id }), document.items[index] == original else { throw BookmarkError.changed }
        document.items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try writeBookmarks(document)
    }

    func removeBookmark(_ original: RecordingBookmark, recordingID: UUID) throws {
        var document = try loadBookmarks(for: recordingID)
        guard document.items.contains(original) else { throw BookmarkError.changed }
        document.items.removeAll { $0.id == original.id }
        try writeBookmarks(document)
    }

    func loadChecklist(for id: UUID) throws -> RecordingChecklist {
        guard recordings.contains(where: { $0.id == id }) else { throw StoreError.notFound }
        let url = directory(id).appendingPathComponent("checklist.json")
        guard files.fileExists(atPath: url.path) else { return RecordingChecklist(formatVersion: 1, recordingID: id, items: []) }
        do {
            let document = try JSONDecoder().decode(RecordingChecklist.self, from: Data(contentsOf: url))
            try document.validate(for: id)
            return document
        } catch { throw ChecklistError.unreadable }
    }

    private func writeChecklist(_ document: RecordingChecklist) throws {
        guard recordings.contains(where: { $0.id == document.recordingID && $0.status != .recording }) else { throw StoreError.notFound }
        try document.validate(for: document.recordingID)
        try JSONEncoder().encode(document).write(to: directory(document.recordingID).appendingPathComponent("checklist.json"),
                                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        checklistUpdates += 1
    }

    @discardableResult
    func addChecklistAction(_ action: SuggestedAction, notes: LocalNotes) throws -> ChecklistItem {
        guard try loadNotes(for: notes.recordingID) == notes,
              SuggestedAction.parse(notes.text).contains(action) else { throw NotesError.notesChanged }
        let source = try loadTranscript(for: notes.recordingID)
        guard let source, notes.matches(source) else { throw NotesError.transcriptChanged }
        var document = try loadChecklist(for: notes.recordingID)
        let key = NotesSection.normalized(action.title + "|" + (action.quote ?? ""))
        if let existing = document.items.first(where: { $0.importKey == key }) { return existing }
        let verifiedQuote = action.quote.flatMap { TranscriptSources.locations(for: $0, in: source).isEmpty ? nil : $0 }
        let item = ChecklistItem(id: UUID(), title: action.title, owner: action.owner, due: action.due, isComplete: false,
                                 createdAt: Date(), sourceQuote: verifiedQuote, transcriptFingerprint: verifiedQuote == nil ? nil : notes.transcriptFingerprint, importKey: key)
        document.items.append(item)
        try writeChecklist(document)
        return item
    }

    func setChecklistComplete(_ item: ChecklistItem, recordingID: UUID, complete: Bool) throws {
        var document = try loadChecklist(for: recordingID)
        guard let index = document.items.firstIndex(where: { $0.id == item.id }) else { throw ChecklistError.changed }
        document.items[index].isComplete = complete
        try writeChecklist(document)
    }

    func saveChecklistTask(recordingID: UUID, original: ChecklistItem?, title: String, owner: String, due: String) throws {
        var document = try loadChecklist(for: recordingID)
        func optional(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        if let original {
            guard let index = document.items.firstIndex(where: { $0.id == original.id }), document.items[index] == original else { throw ChecklistError.changed }
            document.items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            document.items[index].owner = optional(owner)
            document.items[index].due = optional(due)
            if document.items[index].title != original.title || document.items[index].owner != original.owner || document.items[index].due != original.due {
                document.items[index].sourceQuote = nil
                document.items[index].transcriptFingerprint = nil
            }
        } else {
            document.items.append(ChecklistItem(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), owner: optional(owner), due: optional(due), isComplete: false,
                                                createdAt: Date(), sourceQuote: nil, transcriptFingerprint: nil, importKey: nil))
        }
        try writeChecklist(document)
    }

    static func readableDuration(at url: URL) -> TimeInterval? {
        guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return nil }
        return player.duration
    }

    enum StoreError: LocalizedError {
        case lowStorage, notFound, invalidManifest, emptyTitle, stillRecording, unreadableAudio
        var errorDescription: String? {
            switch self {
            case .unreadableAudio: return "The audio still can’t be played. Cedar has kept the original file."
            case .lowStorage: return "There is not enough free space to start. Free some storage on your iPhone and try again."
            case .notFound: return "This recording could not be found."
            case .invalidManifest: return "This recording’s metadata could not be read."
            case .emptyTitle: return "Please enter a name for the recording."
            case .stillRecording: return "Stop and save this recording before moving it."
            }
        }
    }
}
