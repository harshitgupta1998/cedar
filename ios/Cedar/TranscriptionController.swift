import Foundation
import Combine
import UIKit

@MainActor
final class TranscriptionController: ObservableObject {
    @Published private(set) var capability: SpeechCapability?
    @Published private(set) var checking = false
    @Published private(set) var activeRecordingID: UUID?
    @Published private(set) var lastOperationRecordingID: UUID?
    @Published private(set) var phase = ""
    @Published private(set) var processedThrough: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var permissionDenied = false

    var isBusy: Bool { activeRecordingID != nil }
    private let store: RecordingStore
    private let provider: any TranscriptionProvider
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private var refreshID = UUID()

    init(store: RecordingStore, provider: (any TranscriptionProvider)? = nil) {
        self.store = store
        self.provider = provider ?? AppleTranscriptionProvider()
    }

    func refresh(localeID: String) async {
        let token = UUID()
        refreshID = token
        checking = true
        let result = await provider.capability(for: localeID)
        guard refreshID == token, !Task.isCancelled else { return }
        capability = result
        checking = false
        // Diagnostics contain capability metadata only, never audio or transcript text.
        struct Diagnostic: Codable {
            let checkedAt: Date
            let osVersion: String
            let capability: SpeechCapability
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let data = try? JSONEncoder().encode(Diagnostic(checkedAt: Date(), osVersion: UIDevice.current.systemVersion, capability: result)) {
            try? data.write(to: base.appendingPathComponent("speech-capability.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func transcribe(_ item: Recording, localeID: String) {
        guard !isBusy else { return }
        begin(item.id, phase: "Transcribing on this iPhone…") { [self] in
            let current = await provider.capability(for: localeID)
            capability = current
            guard current.readiness == .ready else { throw TranscriptionError.unavailable(current.message) }
            if let max = current.maxDuration, item.duration > max {
                throw TranscriptionError.unavailable("This iPhone’s fallback recognizer supports clips up to \(Int(max)) seconds. Choose a shorter recording.")
            }
            let segments = try await provider.transcribe(url: store.audioURL(for: item.id), capability: current) { [weak self] time in
                self?.processedThrough = time
            }
            try Task.checkCancellation()
            guard !segments.isEmpty else { throw TranscriptionError.noSpeech }
            let transcript = Transcript(recordingID: item.id, localeID: current.localeID,
                                        provider: current.engine.rawValue, segments: segments)
            _ = try store.saveTranscript(transcript)
            phase = "Transcript saved on this iPhone."
        }
    }

    func download(for item: Recording, localeID: String) {
        guard !isBusy else { return }
        begin(item.id, phase: "Downloading language model…") { [self] in
            let current = await provider.capability(for: localeID)
            try Task.checkCancellation()
            try await provider.downloadModel(for: current)
            try Task.checkCancellation()
            await refresh(localeID: localeID)
            phase = "Language ready. Tap Transcribe to continue."
        }
    }

    func cancel(for id: UUID) {
        guard activeRecordingID == id else { return }
        operation?.cancel()
        provider.cancel()
    }

    private func begin(_ recordingID: UUID, phase initialPhase: String,
                       work: @escaping @MainActor () async throws -> Void) {
        let token = UUID()
        operationID = token
        activeRecordingID = recordingID
        lastOperationRecordingID = recordingID
        processedThrough = 0
        errorMessage = nil
        permissionDenied = false
        phase = initialPhase
        operation = Task { [self] in
            defer {
                if operationID == token { activeRecordingID = nil; operation = nil; operationID = nil }
            }
            do { try await work() }
            catch is CancellationError { phase = "Cancelled. Your audio and any previous transcript have been kept." }
            catch {
                if Task.isCancelled { phase = "Cancelled. Your audio and any previous transcript have been kept." }
                else {
                    errorMessage = error.localizedDescription
                    if case TranscriptionError.permissionDenied = error { permissionDenied = true }
                    phase = "Transcription didn’t finish. You can retry."
                }
            }
        }
    }
}
