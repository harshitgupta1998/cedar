import CryptoKit
import Foundation

enum NotesModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case qwen06 = "Qwen3-0.6B-Q4_K_M"

    var id: String { rawValue }
    var name: String { "Qwen3 0.6B" }
    var downloadSize: String { "397 MB" }
    var bytes: Int64 { 396_705_472 }
    var sha256: String { "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a" }
    var url: URL {
        URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf")!
    }
    var contextTokens: UInt32 { 1_536 }
    var inputTokens: Int32 { 900 }
    var memoryHeadroom: UInt64 { 384_000_000 }
    var promptVersion: String { "source-summary-actions-v1/non-thinking" }

    static func displayName(for id: String) -> String {
        switch id {
        case "SmolLM2-360M-Instruct-Q4_K_M": return "SmolLM2 360M (previous model)"
        case "Qwen3-1.7B-Q4_K_M": return "Qwen3 1.7B (previous model)"
        default: return Self(rawValue: id)?.name ?? id
        }
    }

    /// Only retired weights are removed. Audio, transcripts, notes and unrelated files are untouched.
    static func removeRetiredModels(in directory: URL = directory) throws {
        for name in ["SmolLM2-360M-Q4_K_M.gguf", "Qwen3-1.7B-Q4_K_M.gguf"] {
            let file = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CedarModels", isDirectory: true)
    }
    var installedURL: URL {
        let filename = "\(rawValue).gguf"
        return Self.directory.appendingPathComponent(filename)
    }
    func verify(at url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            count += Int64(data.count)
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == bytes, digest == sha256 else { throw NotesError.invalidModel }
    }
}
