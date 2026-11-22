import Darwin
import Foundation

@main
struct EvaluateNotes {
    struct Fixture: Decodable {
        let id: String
        let text: String
        let requiredAny: [[String]]
        let forbidden: [String]
        let summaryRequiredAny: [[String]]?
        let actionsRequired: [String]?
        let actionsForbidden: [String]?
        let followUpsRequiredAny: [[String]]?
    }
    struct Result: Encodable {
        let id: String
        let output: String
        let seconds: Double
        let missingGroups: [[String]]
        let forbiddenMatches: [String]
        let error: String?
        let sectionFailures: [String]
        var passed: Bool { error == nil && missingGroups.isEmpty && forbiddenMatches.isEmpty && sectionFailures.isEmpty }
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
            print("Usage: evaluate-notes fixtures.json model.gguf results.json qwen06")
            exit(2)
        }
        let model: NotesModel
        switch CommandLine.arguments[4] {
        case "qwen06": model = .qwen06
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
            let summary = text.components(separatedBy: "\n\nAction items").first ?? text
            let actions = text.components(separatedBy: "\n\nAction items").dropFirst().first?.components(separatedBy: "\n\nSuggested follow-ups").first ?? ""
            let followUps = text.components(separatedBy: "\n\nSuggested follow-ups").dropFirst().first?.components(separatedBy: "\n\nReview note").first ?? ""
            var sectionFailures = [String]()
            for group in fixture.summaryRequiredAny ?? [] where !group.contains(where: { summary.localizedCaseInsensitiveContains($0) }) {
                sectionFailures.append("Summary missing one of: \(group)")
            }
            for value in fixture.actionsRequired ?? [] where !actions.localizedCaseInsensitiveContains(value) { sectionFailures.append("Actions missing: \(value)") }
            for value in fixture.actionsForbidden ?? [] where actions.localizedCaseInsensitiveContains(value) { sectionFailures.append("Forbidden action: \(value)") }
            for group in fixture.followUpsRequiredAny ?? [] where !group.contains(where: { followUps.localizedCaseInsensitiveContains($0) }) {
                sectionFailures.append("Follow-ups missing one of: \(group)")
            }
            results.append(Result(id: fixture.id, output: text, seconds: Date().timeIntervalSince(start),
                                  missingGroups: missing, forbiddenMatches: forbidden, error: failure, sectionFailures: sectionFailures))
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
