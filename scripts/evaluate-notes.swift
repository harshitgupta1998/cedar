import Darwin
import Foundation

@main
struct EvaluateNotes {
    struct Fixture: Decodable {
        let id: String
        let text: String
        let requiredAny: [[String]]
        let forbidden: [String]
    }
    struct Result: Encodable {
        let id: String
        let output: String
        let seconds: Double
        let missingGroups: [[String]]
        let forbiddenMatches: [String]
        let error: String?
        var passed: Bool { error == nil && missingGroups.isEmpty && forbiddenMatches.isEmpty }
    }
    struct Report: Encodable {
        let modelID: String
        let promptVersion: String
        let environment: String
        let peakResidentMiB: Double
        let passedCases: Int
        let totalCases: Int
        let cases: [Result]
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 5 else {
            print("Usage: evaluate-notes fixtures.json model.gguf results.json smol360|qwen17")
            exit(2)
        }
        let model: NotesModel
        switch CommandLine.arguments[4] {
        case "smol360": model = .smol360
        case "qwen17": model = .qwen17
        default: print("Unknown model"); exit(2)
        }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let engine = LocalNotesEngine()
        var results = [Result]()
        for fixture in fixtures {
            let start = Date()
            var text = ""
            var failure: String?
            do {
                text = try await engine.summarize(fixture.text, modelURL: URL(fileURLWithPath: CommandLine.arguments[2]), model: model)
            } catch { failure = error.localizedDescription }
            let missing = fixture.requiredAny.filter { alternatives in
                !alternatives.contains { text.localizedCaseInsensitiveContains($0) }
            }
            let forbidden = fixture.forbidden.filter { text.localizedCaseInsensitiveContains($0) }
            results.append(Result(id: fixture.id, output: text, seconds: Date().timeIntervalSince(start),
                                  missingGroups: missing, forbiddenMatches: forbidden, error: failure))
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let report = Report(modelID: model.rawValue, promptVersion: model.promptVersion, environment: "macOS / Metal / llama.cpp b9000",
                            peakResidentMiB: Double(usage.ru_maxrss) / 1_048_576,
                            passedCases: results.filter(\.passed).count, totalCases: results.count, cases: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        print("\(report.passedCases)/\(report.totalCases) regression checks passed. Review the generated text manually.")
    }
}
