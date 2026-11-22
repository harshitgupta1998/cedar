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
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 100_000
        else { throw NotesError.invalidNotes }
    }
}

enum NotesError: LocalizedError {
    case invalidGeneratedNotes, modelMissing, invalidModel, loadFailed, inputTooLong, emptyResult, outputTooLong, invalidNotes, transcriptChanged, insufficientMemory, notesChanged
    case downloadStorage(String)

    var errorDescription: String? {
        switch self {
        case .invalidGeneratedNotes: return "The model couldn’t produce concise, structured notes. Your previous notes are unchanged. Try again after correcting unclear transcript text."
        case .downloadStorage(let size): return "Free at least \(size) to download this model."
        case .notesChanged: return "These notes changed. Reopen them to use the latest saved version."
        case .modelMissing: return "Download the selected notes model first."
        case .invalidModel: return "The model failed verification. Remove it and download it again."
        case .insufficientMemory: return "There isn’t enough app memory for Qwen3 0.6B right now. Close other apps and retry. Your saved notes are unchanged."
        case .loadFailed: return "The local model couldn’t run. Close other apps and try again."
        case .inputTooLong: return "This transcript exceeds the long-notes limit (16,000 words, 180,000 characters or 64 sections). Split it into shorter recordings."
        case .emptyResult: return "The model produced no notes. Try again with a clearer, short English transcript."
        case .outputTooLong: return "The model didn’t finish a section within the output limit. Your saved notes are unchanged. Try again or edit repetitive transcript text."
        case .invalidNotes: return "The notes couldn’t be saved because their contents are invalid."
        case .transcriptChanged: return "The transcript changed during processing. Generate notes again using the saved text."
        }
    }
}

/// Generated claims stay separate from proposed follow-ups. Evidence is checked against source text.
struct NotesSection: Decodable, Sendable {
    struct Action: Decodable, Sendable {
        let task: String
        let owner: String?
        let due: String?
        let evidence: String
    }
    struct FollowUp: Decodable, Sendable {
        let text: String
        let evidence: String
    }
    let summary: String
    let actions: [Action]
    let followUps: [FollowUp]
    var omittedItems = 0

    enum CodingKeys: String, CodingKey { case summary, actions, followUps }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    static func parse(_ json: String, source: String, summary suppliedSummary: String? = nil) throws -> Self {
        let result: Self
        do {
            if let suppliedSummary {
                struct Extraction: Decodable { let actions: [Action]; let followUps: [FollowUp] }
                let extracted = try JSONDecoder().decode(Extraction.self, from: Data(json.utf8))
                result = Self(summary: suppliedSummary, actions: extracted.actions, followUps: extracted.followUps)
            } else { result = try JSONDecoder().decode(Self.self, from: Data(json.utf8)) }
        }
        catch { throw NotesError.invalidGeneratedNotes }
        let summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.split(whereSeparator: \.isWhitespace).count <= 120,
              !summary.contains("<think>"), result.actions.count <= 3, result.followUps.count <= 2
        else { throw NotesError.invalidGeneratedNotes }
        let sourceWords = source.split(whereSeparator: \.isWhitespace).count
        // Reject near-verbatim long transcripts instead of presenting them as a concise summary.
        if sourceWords > 150 && summary.split(whereSeparator: \.isWhitespace).count > sourceWords / 2 {
            throw NotesError.invalidGeneratedNotes
        }
        func grounded(_ quote: String) -> Bool {
            let words = quote.split(whereSeparator: \.isWhitespace).count
            return words >= (sourceWords <= 12 ? min(2, sourceWords) : 3) && words <= 45 && normalized(source).contains(normalized(quote))
        }
        func expandedQuote(_ quote: String) -> String {
            let sourceText = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let quoted = quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !quoted.isEmpty, let range = sourceText.range(of: quoted, options: .caseInsensitive) else { return quote }
            let prefix = sourceText[..<range.lowerBound]
            let suffix = sourceText[range.upperBound...]
            let start = prefix.lastIndex(where: { ".!?".contains($0) }).map { sourceText.index(after: $0) } ?? sourceText.startIndex
            let stop = suffix.firstIndex(where: { ".!?".contains($0) })
            let end = quoted.last.map({ ".!?".contains($0) }) == true
                ? range.upperBound : (stop.map { sourceText.index(after: $0) } ?? sourceText.endIndex)
            let expanded = String(sourceText[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            return expanded.split(whereSeparator: \.isWhitespace).count <= 45 ? expanded : quote
        }
        func specified(_ value: String?) -> String? {
            guard let value, !["not specified", "unspecified", "unknown", "none", "null", "not assigned", "not mentioned", "not given", "n/a", "i", "we", "you", "he", "she", "they", "it", ""].contains(normalized(value)) else { return nil }
            return value
        }
        var actions = result.actions.map {
            Action(task: $0.task, owner: specified($0.owner), due: specified($0.due), evidence: expandedQuote($0.evidence))
        }.filter { action in
            guard !action.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  action.task.count < 90, grounded(action.evidence) else { return false }
            for value in [action.owner, action.due].compactMap({ $0 }) {
                guard !value.isEmpty, value.count <= 100,
                      normalized(action.evidence).contains(normalized(value)) else { return false }
            }
            if let due = action.due,
               due.range(of: #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|today|tomorrow|tonight|noon|midnight|morning|afternoon|evening|asap|soon|later|week|month|year|quarter|day|hour|minute|end|[0-9]+)\b"#, options: .regularExpression) == nil { return false }
            if action.evidence.range(of: #"(?i)\b(audio|recordings?|transcripts?|notes|data) (must|will|should) (stay|remain)\b"#, options: .regularExpression) != nil { return false }
            let future = #"\b(will|must|shall|please|remember|assigned)\b|\b(agreed to|need to|going to|let us|let's)\b|^(send|buy|review|test|check|prepare|export|schedule|confirm|finish|complete|call|email|keep|do)\b"#
            guard action.evidence.range(of: future, options: [.regularExpression, .caseInsensitive]) != nil,
                  detailsGrounded(action.task, evidence: action.evidence) else { return false }
            if let owner = action.owner, owner.range(of: #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|today)\b"#, options: .regularExpression) != nil { return false }
            // Clearly conditional, negated or completed statements cannot become committed next steps.
            let blocked = #"\b(might|may(?!\s+[0-9])|would|could|unless|pending|if|already|completed|rejected|cancelled|canceled)\b|\b(will not|must not|do not|don't|decided not|no further|no additional|not assigned|no work|no owner|not approved)\b"#
            return action.evidence.range(of: blocked, options: [.regularExpression, .caseInsensitive]) == nil
        }
        let omittedActions = result.actions.count - actions.count
        // A short, direct personal reminder is itself an explicit task, even if extraction misses it.
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if actions.isEmpty, sourceWords <= 35,
           (normalized(source).hasPrefix("remember to ") || normalized(source).hasPrefix("please ")),
           source.range(of: #"(?i)\b(if|might|may|not|example|quoted|cancelled|already)\b"#, options: .regularExpression) == nil {
            actions = [Action(task: cleanSource, owner: nil, due: nil, evidence: cleanSource)]
        }
        // Recover unambiguous named commitments the small extractor may omit.
        // Source sentences remain visible; do not resolve pronouns or infer missing people/dates.
        if source.range(of: #"(?i)\b(example|hypothetical|quoted|cancelled|canceled|reassigned|corrected|instead)\b"#, options: .regularExpression) == nil {
            let sentences = source.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            let assignment = try NSRegularExpression(pattern: #"^([A-Z][a-zA-Z'’-]*(?: [A-Z][a-zA-Z'’-]*){0,2}) (?:will|volunteered to|agreed to|is assigned to) (?!not\b)(.+)$"#)
            let date = try NSRegularExpression(pattern: #"(?i)\b(?:on|by|before) ([^.!?]+)$"#)
            let day = #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight|next week|january|february|march|april|may|june|july|august|september|october|november|december|[0-9]+)\b"#
            for sentence in sentences where actions.count < 20 {
                let sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                let range = NSRange(sentence.startIndex..., in: sentence)
                guard let match = assignment.firstMatch(in: sentence, range: range),
                      let ownerRange = Range(match.range(at: 1), in: sentence),
                      sentence.range(of: #"(?i)\b(if|unless|might|may|pending|already|not)\b"#, options: .regularExpression) == nil else { continue }
                let owner = String(sentence[ownerRange])
                guard owner.range(of: day, options: .regularExpression) == nil,
                      !["i", "we", "you", "he", "she", "they", "it"].contains(normalized(owner)) else { continue }
                var due: String?
                if let match = date.firstMatch(in: sentence, range: range), let dueRange = Range(match.range(at: 1), in: sentence) {
                    let candidate = String(sentence[dueRange])
                    if candidate.range(of: day, options: .regularExpression) != nil { due = candidate }
                }
                if !actions.contains(where: { normalized($0.evidence).trimmingCharacters(in: .punctuationCharacters) == normalized(sentence).trimmingCharacters(in: .punctuationCharacters) }) {
                    actions.append(Action(task: sentence, owner: owner, due: due, evidence: sentence))
                }
            }
        }
        let followUps = result.followUps.filter {
            let question = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let unresolved = #"\b(pending|unclear|unassigned|unknown|blocked|waiting|if|might|may|revisit|should|could|risk|concern|missing)\b|\b(no owner|no deadline|not assigned|not agreed|not decided|not approved|not finished|no work|without a date)\b"#
            return question.hasSuffix("?") && question.count <= 240 && grounded($0.evidence)
                && $0.evidence.range(of: unresolved, options: [.regularExpression, .caseInsensitive]) != nil
                && detailsGrounded(question, evidence: $0.evidence)
        }
        return Self(summary: summary, actions: actions, followUps: followUps,
                    omittedItems: omittedActions + result.followUps.count - followUps.count)
    }

    private static func detailsGrounded(_ text: String, evidence: String) -> Bool {
        let pattern = #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|today|january|february|march|april|may|june|july|august|september|october|november|december|[0-9]+(?::[0-9]+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).allSatisfy {
            guard let range = Range($0.range, in: text) else { return false }
            return normalized(evidence).contains(normalized(String(text[range])))
        }
    }

    static func render(overview: String, sections: [Self], sourceSummary: Bool = false) -> String {
        var parts = ["Summary\n\(overview)" + (sourceSummary ? "\n\nSummary method: selected complete transcript statements." : "")]
        var actions = [String]()
        var suggestions = [String]()
        var seenActions = Set<String>()
        var seenSuggestions = Set<String>()
        for (index, section) in sections.enumerated() {
            let reference = sections.count == 1 ? "Source" : "Source · section \(index + 1)"
            for action in section.actions {
                let key = normalized(action.task).trimmingCharacters(in: .punctuationCharacters) + "|" + normalized(action.owner ?? "") + "|" + normalized(action.due ?? "")
                guard seenActions.insert(key).inserted else { continue }
                actions.append("• \(action.task)\n  Owner: \(action.owner ?? "Not specified") · Due: \(action.due ?? "Not specified")\n  \(reference): “\(action.evidence)”")
            }
            for suggestion in section.followUps {
                guard seenSuggestions.insert(normalized(suggestion.text)).inserted else { continue }
                suggestions.append("• \(suggestion.text)\n  \(reference): “\(suggestion.evidence)”")
            }
        }
        let qualification = sections.count > 1 ? "\nIn transcript order; later sections may change or cancel earlier actions." : ""
        parts.append("Action items\(qualification)\n" + (actions.isEmpty ? "No confirmed next steps identified." : actions.joined(separator: "\n\n")))
        parts.append("Suggested follow-ups · Not commitments\n" + (suggestions.isEmpty ? "No additional follow-ups identified." : suggestions.joined(separator: "\n\n")))
        let omitted = sections.reduce(0) { $0 + $1.omittedItems }
        if omitted > 0 { parts.append("Review note\n\(omitted) generated item(s) were omitted because their source evidence or action details could not be verified.") }
        if sections.count > 1 {
            parts.append("Section summaries\n" + sections.enumerated().map {
                "Section \($0.offset + 1) of \(sections.count)\n\($0.element.summary)"
            }.joined(separator: "\n\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

/// Short factual input helps the 0.6B model condense long passages without copying them wholesale.
enum NotesSourceSelection {
    static func select(_ source: String) throws -> String {
        let words = source.split(whereSeparator: \.isWhitespace).count
        guard words > 120 else { return source }
        var sentences = [String]()
        source.enumerateSubstrings(in: source.startIndex..., options: .bySentences) { value, _, _, _ in
            if let value {
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { sentences.append(clean) }
            }
        }
        let budget = min(90, max(30, words / 3))
        var seen = Set<String>()
        let candidates = sentences.enumerated().compactMap { index, text -> (Int, String, Int, Int)? in
            let count = text.split(whereSeparator: \.isWhitespace).count
            guard count <= min(45, budget), seen.insert(NotesSection.normalized(text)).inserted else { return nil }
            var score = index == 0 ? 5 : 0
            if text.range(of: #"(?i)\b(decided|agreed|approved|rejected|final|instead|corrected)\b"#, options: .regularExpression) != nil { score += 6 }
            if text.range(of: #"(?i)\b(will|volunteered|assigned|must)\b"#, options: .regularExpression) != nil { score += 4 }
            if text.range(of: #"^[A-Z][a-zA-Z'’-]*(?: [A-Z][a-zA-Z'’-]*){0,2} (will|volunteered to|agreed to) "#, options: .regularExpression) != nil { score += 5 }
            if text.range(of: #"(?i)\b(pending|unknown|blocked|unresolved|unclear)\b|not finished|no owner|no deadline|no decision|not yet"#, options: .regularExpression) != nil { score += 4 }
            if text.range(of: #"(?i)accuracy matters|no additional|repeated the same|checked the existing notes"#, options: .regularExpression) != nil { score -= 10 }
            return (index, text, count, score)
        }.sorted { $0.3 == $1.3 ? $0.0 > $1.0 : $0.3 > $1.3 }
        var selected = [(Int, String)]()
        var used = 0
        for candidate in candidates where selected.count < 5 {
            guard used + candidate.2 <= budget else { continue }
            selected.append((candidate.0, candidate.1))
            used += candidate.2
        }
        guard !selected.isEmpty else { throw NotesError.invalidGeneratedNotes }
        return selected.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: " ")
    }
}
