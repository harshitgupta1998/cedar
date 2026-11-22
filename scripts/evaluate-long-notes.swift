import Darwin
import Foundation

/// Synthetic text throughput/coverage check; no microphone, transcription or real audio is involved.
@main
struct EvaluateLongNotes {
    struct Report: Encodable {
        let modelID: String
        let promptVersion: String
        let environment: String
        let sourceWords: Int
        let equivalentMinutesAt150WordsPerMinute: Double
        let seconds: Double
        let peakResidentMiB: Double
        let sections: Int
        let containsEarlyFact: Bool
        let containsMiddleFact: Bool
        let containsFinalFact: Bool
        let missingFacts: [String]
        let output: String
    }
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: evaluate-long-notes model.gguf results.json")
            exit(2)
        }
        let facts = [
            "Maya will test recording on Monday. Automatic cloud uploads were rejected.",
            "Jordan will check summary accuracy on Tuesday. The app name stays Cedar.",
            "Priya will review the demo on Wednesday. No replacement recorder was approved.",
            "Lee will send invitations on Thursday. The final approved budget is 350 dollars.",
            "Riya will export only text notes on Saturday. Audio must stay on the phone.",
            "Noor will review microphone permissions on Tuesday. The appointment is at 3 pm, not 2 pm.",
            "Sam might review the proposal if approved. The proposal is pending and no work is assigned to Sam.",
            "Alex already sent the invoice. No further client email is required.",
            "Zoe will review transcripts on Friday. Spanish support has no owner or deadline."
        ]
        let filler = "We reviewed this topic carefully during the meeting. The discussion repeated the same facts without adding a new decision. Participants checked the existing notes against the source and agreed that accuracy matters. No additional owners, deadlines or tasks were assigned during this discussion."
        // About 9,000 words, equivalent to an hour at 150 spoken words/minute.
        let source = facts.map { fact in
            ([fact] + Array(repeating: filler, count: 23) + [fact]).joined(separator: " ")
        }.joined(separator: "\n\n")
        let start = Date()
        let model = NotesModel.qwen06
        let output = try await LocalNotesEngine().summarize(source, modelURL: URL(fileURLWithPath: CommandLine.arguments[1])) { section, total in
            print("Section \(section)/\(total)")
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let words = source.split(whereSeparator: \.isWhitespace).count
        let report = Report(modelID: model.rawValue, promptVersion: model.promptVersion,
                            environment: "macOS / Metal / llama.cpp b9000; synthetic text, not a recording",
                            sourceWords: words, equivalentMinutesAt150WordsPerMinute: Double(words) / 150,
                            seconds: Date().timeIntervalSince(start), peakResidentMiB: Double(usage.ru_maxrss) / 1_048_576,
                            sections: output.components(separatedBy: "Section ").count - 1,
                            containsEarlyFact: output.contains("Maya") && output.contains("Monday"),
                            containsMiddleFact: output.contains("Noor") && output.contains("3 pm"),
                            containsFinalFact: output.contains("Zoe") && output.contains("Friday"),
                            missingFacts: ["Maya", "Monday", "Jordan", "Tuesday", "Priya", "Wednesday", "Lee", "Thursday", "350", "Riya", "Saturday", "Noor", "3 pm", "Sam", "pending", "Alex", "invoice", "Zoe", "Friday"].filter { !output.localizedCaseInsensitiveContains($0) },
                            output: output)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("\(words) words in \(report.sections) sections, \(report.seconds) seconds")
        guard report.containsEarlyFact, report.containsMiddleFact, report.containsFinalFact, report.missingFacts.isEmpty else { exit(1) }
    }
}
