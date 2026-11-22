import Foundation
import SwiftUI

struct SourceLocation: Identifiable, Equatable, Sendable {
    let id: UUID
    let startMS: Int
    let endMS: Int
}

struct SourceExcerpt: Identifiable {
    var id: String { quote }
    let quote: String
    let locations: [SourceLocation]
}

enum TranscriptSources {
    static func locations(for quote: String, in transcript: Transcript) -> [SourceLocation] {
        let needle = quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !needle.isEmpty else { return [] }
        var text = ""
        var spans = [(NSRange, TranscriptSegment)]()
        for segment in transcript.segments {
            if !text.isEmpty { text += " " }
            let start = text.utf16.count
            let part = segment.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text += part
            spans.append((NSRange(location: start, length: part.utf16.count), segment))
        }
        var result = [SourceLocation]()
        var remaining = text.startIndex..<text.endIndex
        while let match = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: remaining) {
            let range = NSRange(match, in: text)
            let touched = spans.filter { NSIntersectionRange($0.0, range).length > 0 }.map(\.1)
            if let first = touched.first, let last = touched.last, !result.contains(where: { $0.id == first.id }) {
                result.append(SourceLocation(id: first.id, startMS: first.startMS, endMS: last.endMS))
            }
            remaining = match.upperBound..<text.endIndex
        }
        return result
    }

    static func excerpts(in notes: String) -> [String] {
        var values = [String]()
        let summary = notes.components(separatedBy: "\n\nAction items").first ?? ""
        if summary.hasPrefix("Summary\n") {
            let content = String(summary.dropFirst("Summary\n".count)).components(separatedBy: "\n\nSummary method:").first ?? ""
            content.enumerateSubstrings(in: content.startIndex..., options: .bySentences) { sentence, _, _, _ in
                if let sentence { values.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
        }
        for line in notes.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard clean.hasPrefix("Source"), let start = clean.firstIndex(of: "“"), let end = clean.lastIndex(of: "”"), start < end else { continue }
            values.append(String(clean[clean.index(after: start)..<end]))
        }
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert(NotesSection.normalized($0)).inserted }
    }
}

struct SuggestedAction: Identifiable, Equatable {
    var id: String { title + "|" + (quote ?? "") }
    let title: String
    var owner: String?
    var due: String?
    var quote: String?

    static func parse(_ text: String) -> [Self] {
        guard let start = text.range(of: "\n\nAction items"),
              let end = text.range(of: "\n\nSuggested follow-ups", range: start.upperBound..<text.endIndex) else { return [] }
        var items = [Self]()
        for raw in text[start.upperBound..<end.lowerBound].components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("• ") {
                items.append(Self(title: String(line.dropFirst(2))))
            } else if !items.isEmpty, line.hasPrefix("Owner: ") {
                let fields = line.dropFirst(7).components(separatedBy: " · Due: ")
                items[items.count - 1].owner = fields[0] == "Not specified" ? nil : fields[0]
                if fields.count == 2 { items[items.count - 1].due = fields[1] == "Not specified" ? nil : fields[1] }
            } else if !items.isEmpty, line.hasPrefix("Source"), let a = line.firstIndex(of: "“"), let b = line.lastIndex(of: "”"), a < b {
                items[items.count - 1].quote = String(line[line.index(after: a)..<b])
            }
        }
        var seen = Set<String>()
        return items.filter { !$0.title.isEmpty && seen.insert($0.id).inserted }
    }
}

struct ChecklistItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var owner: String?
    var due: String?
    var isComplete: Bool
    let createdAt: Date
    var sourceQuote: String?
    var transcriptFingerprint: String?
    let importKey: String?
}

struct RecordingChecklist: Codable {
    let formatVersion: Int
    let recordingID: UUID
    var items: [ChecklistItem]

    func validate(for id: UUID) throws {
        guard formatVersion == 1, recordingID == id, items.count <= 500,
              Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 500
                  && ($0.owner?.count ?? 0) <= 200 && ($0.due?.count ?? 0) <= 200
                  && ($0.sourceQuote?.count ?? 0) <= 5_000
                  && ($0.transcriptFingerprint == nil || $0.transcriptFingerprint?.count == 64) }) else { throw ChecklistError.invalid }
    }
}

enum ChecklistError: LocalizedError {
    case invalid, unreadable, changed
    var errorDescription: String? {
        switch self {
        case .invalid: return "Use a task of 1–500 characters and owner/due labels up to 200 characters. Each recording can hold 500 tasks."
        case .unreadable: return "The saved checklist couldn’t be read. Its existing file has been kept. Try loading it again."
        case .changed: return "This task changed. Reopen it before editing."
        }
    }
}

struct LibrarySearchKey: Equatable {
    let query: String
    let recordings: [Recording]
    let transcripts: Int
    let notes: Int
}

struct LibrarySearchResult: Sendable {
    var snippets: [UUID: String] = [:]
    var unreadableFiles = 0
}

enum LibrarySearch {
    static func snippet(_ text: String, query: String) -> String? {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 85, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start == text.startIndex ? "" : "…") + excerpt + (end == text.endIndex ? "" : "…")
    }

    static func scan(_ recordings: [Recording], root: URL, query: String) throws -> LibrarySearchResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return LibrarySearchResult() }
        var result = LibrarySearchResult()
        for recording in recordings {
            try Task.checkCancellation()
            if let match = snippet(recording.title, query: query) { result.snippets[recording.id] = "Title · " + match }
            let folder = root.appendingPathComponent(recording.id.uuidString)
            for name in ["transcript.json", "notes.json"] {
                try Task.checkCancellation()
                let url = folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try autoreleasepool {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 32_000_000 else { throw ChecklistError.invalid }
                        let data = try Data(contentsOf: url)
                        let text: String
                        if name == "transcript.json" {
                            let document = try JSONDecoder().decode(Transcript.self, from: data)
                            try document.validate(for: recording.id)
                            text = document.text
                        } else {
                            let document = try JSONDecoder().decode(LocalNotes.self, from: data)
                            try document.validate(for: recording.id)
                            text = document.text
                        }
                        if result.snippets[recording.id] == nil, let match = snippet(text, query: query) {
                            result.snippets[recording.id] = (name == "transcript.json" ? "Transcript · " : "Notes · ") + match
                        }
                    }
                } catch { result.unreadableFiles += 1 }
            }
        }
        return result
    }
}

struct ChecklistView: View {
    let recordingID: UUID
    @EnvironmentObject private var store: RecordingStore
    @State private var items: [ChecklistItem] = []
    @State private var editing: ChecklistItem?
    @State private var adding = false
    @State private var sourceFingerprint: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Confirm extracted tasks before relying on them. This checklist stays on your iPhone.").font(.footnote)
                Button("Add task") { adding = true }.accessibilityIdentifier("checklist.add")
            }
            Section("Tasks · \(items.filter { !$0.isComplete }.count) open") {
                if items.isEmpty { Text("No tasks yet. Add one here or save an action from Offline notes.") }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            do { try store.setChecklistComplete(item, recordingID: recordingID, complete: !item.isComplete); load() }
                            catch { errorMessage = error.localizedDescription }
                        } label: {
                            Label(item.title, systemImage: item.isComplete ? "checkmark.circle.fill" : "circle")
                                .strikethrough(item.isComplete)
                        }
                        .accessibilityLabel("\(item.isComplete ? "Reopen" : "Complete") task: \(item.title)")
                        .accessibilityIdentifier("checklist.toggle.\(item.id)")
                        Text("Owner: \(item.owner ?? "Not specified") · Due: \(item.due ?? "Not specified")").font(.caption).foregroundStyle(.secondary)
                        if let quote = item.sourceQuote {
                            Text("Source: “\(quote)”").font(.caption).foregroundStyle(.secondary)
                            if item.transcriptFingerprint != sourceFingerprint {
                                Label("Source transcript changed. Review this task.", systemImage: "exclamationmark.triangle").font(.caption)
                            }
                        }
                        Button("Edit task") { editing = item }.font(.subheadline)
                            .accessibilityIdentifier("checklist.edit.\(item.id)")
                    }.buttonStyle(.borderless).padding(.vertical, 5)
                }
            }
            if let errorMessage { Section("Couldn’t update checklist") { Text(errorMessage); Button("Try loading again") { load() } } }
        }
        .navigationTitle("Action checklist")
        .scrollContentBackground(.hidden).background(CedarStyle.cream).tint(CedarStyle.forest)
        .task { load() }
        .onChange(of: store.checklistUpdates) { _, _ in load() }
        .onChange(of: store.transcriptUpdates) { _, _ in load() }
        .sheet(isPresented: $adding) { ChecklistEditor(recordingID: recordingID, original: nil) }
        .sheet(item: $editing) { item in ChecklistEditor(recordingID: recordingID, original: item) }
    }

    private func load() {
        do {
            items = try store.loadChecklist(for: recordingID).items
            sourceFingerprint = try store.loadTranscript(for: recordingID).map { LocalNotes.fingerprint($0) }
            errorMessage = nil
        }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ChecklistEditor: View {
    let recordingID: UUID
    let original: ChecklistItem?
    @EnvironmentObject private var store: RecordingStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var owner = ""
    @State private var due = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $title, axis: .vertical).accessibilityIdentifier("checklist.title")
                TextField("Owner (optional)", text: $owner).accessibilityIdentifier("checklist.owner")
                TextField("Due (optional)", text: $due).accessibilityIdentifier("checklist.due")
                Text("Due is a text label. No reminder or calendar event is created.").font(.caption)
                if original?.sourceQuote != nil { Text("Editing task details removes its generated source attribution.").font(.caption) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(original == nil ? "New task" : "Edit task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try store.saveChecklistTask(recordingID: recordingID, original: original, title: title, owner: owner, due: due)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("checklist.save")
                }
            }
            .onAppear { title = original?.title ?? ""; owner = original?.owner ?? ""; due = original?.due ?? "" }
        }.tint(CedarStyle.forest)
    }
}

struct TranscriptFindRequest: Equatable {
    let query: String
    let revision: Int
}

struct TranscriptFindResult: Sendable {
    var ids: [UUID] = []
    var highlighted: [UUID: AttributedString] = [:]
}

enum TranscriptFind {
    static func scan(_ segments: [TranscriptSegment], query: String) throws -> TranscriptFindResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return TranscriptFindResult() }
        var result = TranscriptFindResult()
        for segment in segments {
            try Task.checkCancellation()
            guard segment.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
            result.ids.append(segment.id)
            var styled = AttributedString()
            var remaining = segment.text.startIndex..<segment.text.endIndex
            while let match = segment.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: remaining) {
                try Task.checkCancellation()
                styled.append(AttributedString(String(segment.text[remaining.lowerBound..<match.lowerBound])))
                var emphasized = AttributedString(String(segment.text[match]))
                emphasized.inlinePresentationIntent = .stronglyEmphasized
                styled.append(emphasized)
                remaining = match.upperBound..<segment.text.endIndex
            }
            styled.append(AttributedString(String(segment.text[remaining])))
            result.highlighted[segment.id] = styled
        }
        return result
    }
}
