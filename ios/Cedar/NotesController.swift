import Combine
import CryptoKit
import Foundation

@MainActor
final class NotesController: ObservableObject {
    nonisolated static let modelBytes: Int64 = 270_590_560
    nonisolated static let modelSHA256 = "16c7f1667fea34bacad196a57b548effcb37614db4ab5677a20c8c7b823b9e63"
    static let modelURL = URL(string: "https://huggingface.co/unsloth/SmolLM2-360M-Instruct-GGUF/resolve/391ed11137586e383b1be0fab9acf01d282c2e11/SmolLM2-360M-Instruct-Q4_K_M.gguf")!
    static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CedarModels", isDirectory: true)
    }
    static var installedModelURL: URL { modelDirectory.appendingPathComponent("SmolLM2-360M-Q4_K_M.gguf") }

    @Published private(set) var modelReady = FileManager.default.fileExists(atPath: installedModelURL.path)
    @Published private(set) var isBusy = false
    @Published private(set) var activeRecordingID: UUID?
    @Published private(set) var lastRecordingID: UUID?
    @Published private(set) var phase = ""
    @Published private(set) var errorMessage: String?
    private let engine = LocalNotesEngine()
    private var job: Task<Void, Never>?

    nonisolated static func verifyModel(at url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            bytes += Int64(data.count)
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard bytes == modelBytes, digest == modelSHA256 else { throw NotesError.invalidModel }
    }

    func download() {
        guard !isBusy else { return }
        isBusy = true
        lastRecordingID = nil
        errorMessage = nil
        phase = "Downloading 271 MB model…"
        job = Task {
            let staging = Self.modelDirectory.appendingPathComponent("download-\(UUID().uuidString).partial")
            defer {
                try? FileManager.default.removeItem(at: staging)
                isBusy = false
                job = nil
            }
            do {
                try FileManager.default.createDirectory(at: Self.modelDirectory, withIntermediateDirectories: true)
                let available = try Self.modelDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage
                if let available, available < Self.modelBytes * 2 { throw RecordingStore.StoreError.lowStorage }
                let (temporary, response) = try await URLSession.shared.download(from: Self.modelURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: temporary, to: staging)
                phase = "Verifying model…"
                let verification = Task.detached { try Self.verifyModel(at: staging) }
                try await withTaskCancellationHandler {
                    try await verification.value
                } onCancel: { verification.cancel() }
                try Task.checkCancellation()
                // The previous verified model remains until its replacement is complete.
                if FileManager.default.fileExists(atPath: Self.installedModelURL.path) {
                    _ = try FileManager.default.replaceItemAt(Self.installedModelURL, withItemAt: staging)
                } else {
                    try FileManager.default.moveItem(at: staging, to: Self.installedModelURL)
                }
                var modelFile = Self.installedModelURL
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try modelFile.setResourceValues(values)
                modelReady = true
                phase = "Model ready for offline notes."
            } catch {
                phase = ""
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    func removeModel() {
        guard !isBusy else { return }
        do {
            if FileManager.default.fileExists(atPath: Self.installedModelURL.path) {
                try FileManager.default.removeItem(at: Self.installedModelURL)
            }
            modelReady = false
            phase = ""
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func generate(from transcript: Transcript, store: RecordingStore) {
        guard !isBusy, modelReady else { return }
        isBusy = true
        activeRecordingID = transcript.recordingID
        lastRecordingID = transcript.recordingID
        phase = "Generating notes on this iPhone…"
        errorMessage = nil
        job = Task {
            defer { isBusy = false; activeRecordingID = nil; job = nil }
            do {
                let start = ContinuousClock.now
                let output = try await engine.summarize(transcript.text, modelURL: Self.installedModelURL)
                try Task.checkCancellation()
                guard let current = try store.loadTranscript(for: transcript.recordingID),
                      LocalNotes.fingerprint(current) == LocalNotes.fingerprint(transcript)
                else { throw NotesError.transcriptChanged }
                let elapsed = start.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let notes = LocalNotes(recordingID: transcript.recordingID, transcriptRevision: transcript.revision,
                                       transcriptFingerprint: LocalNotes.fingerprint(transcript), modelID: LocalNotesEngine.modelID,
                                       createdAt: Date(), processingSeconds: seconds, text: output)
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
