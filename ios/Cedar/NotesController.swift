import Combine
import Foundation

@MainActor
final class NotesController: ObservableObject {
    static var installedModelURL: URL { NotesModel.smol360.installedURL }
    @Published var selectedModel: NotesModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: "notes.model") }
    }
    @Published private(set) var installedModels: Set<NotesModel>
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var startedAt: Date?
    var modelReady: Bool { installedModels.contains(selectedModel) }

    init() {
        selectedModel = NotesModel(rawValue: UserDefaults.standard.string(forKey: "notes.model") ?? "") ?? .smol360
        installedModels = Set(NotesModel.allCases.filter { FileManager.default.fileExists(atPath: $0.installedURL.path) })
        // A terminated download may leave a verified-but-uncommitted staging file.
        let staging = (try? FileManager.default.contentsOfDirectory(at: NotesModel.directory, includingPropertiesForKeys: nil)) ?? []
        for file in staging where file.lastPathComponent.hasPrefix("download-") && file.pathExtension == "partial" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Published private(set) var isBusy = false
    @Published private(set) var activeRecordingID: UUID?
    @Published private(set) var lastRecordingID: UUID?
    @Published private(set) var phase = ""
    @Published private(set) var errorMessage: String?
    private let engine = LocalNotesEngine()
    private var job: Task<Void, Never>?

    nonisolated static func verifyModel(at url: URL) throws {
        try NotesModel.smol360.verify(at: url)
    }

    func download() {
        guard !isBusy else { return }
        isBusy = true
        lastRecordingID = nil
        errorMessage = nil
        let model = selectedModel
        phase = "Downloading \(model.name)…"
        downloadProgress = 0
        job = Task {
            let staging = NotesModel.directory.appendingPathComponent("download-\(UUID().uuidString).partial")
            defer {
                try? FileManager.default.removeItem(at: staging)
                isBusy = false
                job = nil
                downloadProgress = nil
            }
            do {
                try FileManager.default.createDirectory(at: NotesModel.directory, withIntermediateDirectories: true)
                let available = try NotesModel.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage
                if let available, available < model.bytes + 50_000_000 {
                    throw NotesError.downloadStorage(ByteCountFormatter.string(fromByteCount: model.bytes + 50_000_000, countStyle: .decimal))
                }
                var modelFolder = NotesModel.directory
                var folderValues = URLResourceValues()
                folderValues.isExcludedFromBackup = true
                try modelFolder.setResourceValues(folderValues)
                let download = ModelDownload(destination: staging) { [weak self] fraction in
                    self?.downloadProgress = fraction
                }
                try await download.run(url: model.url)
                try Task.checkCancellation()
                phase = "Verifying model…"
                downloadProgress = nil
                let verification = Task.detached { try model.verify(at: staging) }
                try await withTaskCancellationHandler {
                    try await verification.value
                } onCancel: { verification.cancel() }
                try Task.checkCancellation()
                // The previous verified model remains until its replacement is complete.
                if FileManager.default.fileExists(atPath: model.installedURL.path) {
                    _ = try FileManager.default.replaceItemAt(model.installedURL, withItemAt: staging)
                } else {
                    try FileManager.default.moveItem(at: staging, to: model.installedURL)
                }
                var modelFile = model.installedURL
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try modelFile.setResourceValues(values)
                installedModels.insert(model)
                phase = "Model ready for offline notes."
            } catch {
                phase = ""
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    func removeModel() {
        guard !isBusy else { return }
        let model = selectedModel
        do {
            if FileManager.default.fileExists(atPath: model.installedURL.path) {
                try FileManager.default.removeItem(at: model.installedURL)
            }
            installedModels.remove(model)
            phase = ""
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func generate(from transcript: Transcript, store: RecordingStore) {
        guard !isBusy, modelReady else { return }
        isBusy = true
        activeRecordingID = transcript.recordingID
        lastRecordingID = transcript.recordingID
        let model = selectedModel
        phase = "Generating notes with \(model.name)…"
        startedAt = Date()
        errorMessage = nil
        job = Task {
            defer { isBusy = false; activeRecordingID = nil; job = nil; startedAt = nil }
            do {
                let start = ContinuousClock.now
                let output = try await engine.summarize(transcript.text, modelURL: model.installedURL, model: model)
                try Task.checkCancellation()
                guard let current = try store.loadTranscript(for: transcript.recordingID),
                      LocalNotes.fingerprint(current) == LocalNotes.fingerprint(transcript)
                else { throw NotesError.transcriptChanged }
                let elapsed = start.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let notes = LocalNotes(recordingID: transcript.recordingID, transcriptRevision: transcript.revision,
                                       transcriptFingerprint: LocalNotes.fingerprint(transcript), modelID: model.rawValue,
                                       createdAt: Date(), processingSeconds: seconds, text: output, promptVersion: model.promptVersion)
                try store.saveNotes(notes)
                phase = "Notes saved on this iPhone."
            } catch {
                phase = ""
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancel() { job?.cancel() }
}
