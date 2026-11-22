import CryptoKit
import Foundation

enum NotesModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case smol360 = "SmolLM2-360M-Instruct-Q4_K_M"

    case qwen17 = "Qwen3-1.7B-Q4_K_M"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .smol360: return "SmolLM2 360M"
        case .qwen17: return "Qwen3 1.7B"
        }
    }
    var downloadSize: String { self == .smol360 ? "271 MB" : "1.11 GB" }
    var bytes: Int64 {
        switch self {
        case .smol360: return 270_590_560
        case .qwen17: return 1_107_409_472
        }
    }
    var sha256: String {
        switch self {
        case .smol360: return "16c7f1667fea34bacad196a57b548effcb37614db4ab5677a20c8c7b823b9e63"
        case .qwen17: return "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897"
        }
    }
    var url: URL {
        switch self {
        case .smol360:
            return URL(string: "https://huggingface.co/unsloth/SmolLM2-360M-Instruct-GGUF/resolve/391ed11137586e383b1be0fab9acf01d282c2e11/SmolLM2-360M-Instruct-Q4_K_M.gguf")!
        case .qwen17:
            return URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-Q4_K_M.gguf")!

        }
    }
    var contextTokens: UInt32 { self == .smol360 ? 4_096 : 2_048 }
    var inputTokens: Int32 { self == .smol360 ? 3_500 : 1_600 }
    var memoryHeadroom: UInt64 { self == .smol360 ? 256_000_000 : 512_000_000 }
    var promptVersion: String { self == .smol360 ? "faithful-v2" : "faithful-v3/non-thinking" }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CedarModels", isDirectory: true)
    }
    var installedURL: URL {
        let filename = self == .smol360 ? "SmolLM2-360M-Q4_K_M.gguf" : "\(rawValue).gguf"
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
