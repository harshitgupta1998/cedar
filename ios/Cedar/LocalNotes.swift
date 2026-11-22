import CryptoKit
import Foundation

struct LocalNotes: Codable, Equatable, Sendable {
    let recordingID: UUID
    let transcriptRevision: Int
    let transcriptFingerprint: String
    let modelID: String
    let createdAt: Date
    let processingSeconds: Double
    var text: String
    var edited: Bool? = nil
    var updatedAt: Date? = nil
    var promptVersion: String? = nil

    var isEdited: Bool { edited == true }

    static func fingerprint(_ transcript: Transcript) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(transcript)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func matches(_ transcript: Transcript) -> Bool {
        recordingID == transcript.recordingID && transcriptFingerprint == Self.fingerprint(transcript)
    }

    func validate(for id: UUID) throws {
        guard recordingID == id, transcriptRevision > 0, transcriptFingerprint.count == 64,
              !modelID.isEmpty, processingSeconds.isFinite, processingSeconds >= 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 20_000
        else { throw NotesError.invalidNotes }
    }
}

enum NotesError: LocalizedError {
    case modelMissing, invalidModel, loadFailed, inputTooLong, emptyResult, outputTooLong, invalidNotes, transcriptChanged, insufficientMemory, notesChanged
    case downloadStorage(String)

    var errorDescription: String? {
        switch self {
        case .downloadStorage(let size): return "Free at least \(size) to download this model."
        case .notesChanged: return "These notes changed. Reopen them to use the latest saved version."
        case .modelMissing: return "Download the selected notes model first."
        case .invalidModel: return "The model failed verification. Remove it and download it again."
        case .insufficientMemory: return "There isn’t enough app memory for this model right now. Close other apps or select SmolLM2 360M."
        case .loadFailed: return "The local model couldn’t run. Close other apps and try again."
        case .inputTooLong: return "This transcript is too long for the selected model. Try a shorter recording."
        case .emptyResult: return "The model produced no notes. Try again with a clearer, short English transcript."
        case .outputTooLong: return "The model didn’t finish within the output limit. Try a shorter transcript."
        case .invalidNotes: return "The notes couldn’t be saved because their contents are invalid."
        case .transcriptChanged: return "The transcript changed during processing. Generate notes again using the saved text."
        }
    }
}
