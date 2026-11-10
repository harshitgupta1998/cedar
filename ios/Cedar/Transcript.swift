import Foundation

struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startMS: Int
    let endMS: Int
    var text: String

    init(id: UUID = UUID(), startMS: Int, endMS: Int, text: String) {
        self.id = id
        self.startMS = startMS
        self.endMS = endMS
        self.text = text
    }
}

struct Transcript: Codable, Equatable, Sendable {
    let formatVersion: Int
    let recordingID: UUID
    let localeID: String
    let provider: String
    let createdAt: Date
    var updatedAt: Date
    var revision: Int
    var edited: Bool
    var segments: [TranscriptSegment]

    var text: String { segments.map(\.text).joined(separator: "\n\n") }

    init(recordingID: UUID, localeID: String, provider: String, segments: [TranscriptSegment]) {
        self.formatVersion = 1
        self.recordingID = recordingID
        self.localeID = localeID
        self.provider = provider
        self.createdAt = Date()
        self.updatedAt = Date()
        self.revision = 1
        self.edited = false
        self.segments = segments
    }

    func validate(for id: UUID) throws {
        guard formatVersion == 1, recordingID == id, revision > 0, !segments.isEmpty,
              Set(segments.map(\.id)).count == segments.count,
              segments.allSatisfy({ $0.startMS >= 0 && $0.endMS >= $0.startMS && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw TranscriptionError.invalidTranscript }
        var previousStart = -1
        for segment in segments {
            guard segment.startMS >= previousStart else { throw TranscriptionError.invalidTranscript }
            previousStart = segment.startMS
        }
    }
}

struct SpeechCapability: Codable, Equatable, Sendable {
    enum Engine: String, Codable { case speechAnalyzer, dictationAnalyzer, legacy, unavailable }
    enum Readiness: String, Codable { case ready, downloadRequired, unavailable }
    let engine: Engine
    let localeID: String
    let readiness: Readiness
    let message: String
    let maxDuration: TimeInterval?
}

enum TranscriptionError: LocalizedError {
    case unavailable(String), permissionDenied, downloadRequired, noSpeech, invalidTranscript, busy, timedOut
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .permissionDenied: return "Speech recognition access is off. Enable it in Settings to transcribe saved audio."
        case .downloadRequired: return "Download the language model first, then try again."
        case .noSpeech: return "No speech was recognized. Try a clearer recording or another language. Your audio and any previous transcript have been kept."
        case .invalidTranscript: return "The transcript could not be saved because its text or timestamps are invalid."
        case .busy: return "Wait for the current transcription to finish, or cancel it first."
        case .timedOut: return "Transcription took too long. Your audio and any previous transcript have been kept. You can retry."
        }
    }
}
