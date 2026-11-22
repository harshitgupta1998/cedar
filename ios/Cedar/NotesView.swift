import SwiftUI

struct NotesView: View {
    let recordingID: UUID
    @EnvironmentObject private var store: RecordingStore
    @EnvironmentObject private var controller: NotesController
    @EnvironmentObject private var transcription: TranscriptionController
    @EnvironmentObject private var audio: AudioController
    @Environment(\.scenePhase) private var scenePhase
    @State private var transcript: Transcript?
    @State private var notes: LocalNotes?
    @State private var loadError: String?
    @State private var replaceNotes = false
    @State private var showLicenses = false
    @State private var showEditor = false
    @State private var showHistory = false
    @State private var copied = false
    @State private var addedActions = Set<String>()
    @State private var sourceExcerpts: [SourceExcerpt] = []
    @State private var bookmarkFeedback: String?

    private var generating: Bool { controller.activeRecordingID == recordingID }
    private var showsFeedback: Bool { controller.lastRecordingID == nil || controller.lastRecordingID == recordingID }

    var body: some View {
        List {
            Section("Offline notes · Experimental") {
                Text("Get a concise summary, source-backed action items and suggested follow-up questions. Suggestions are not commitments. Review the notes against your transcript.")
                    .font(.subheadline)
                Text("Qwen3 0.6B · 397 MB download")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("notes.model")
                if controller.modelReady {
                    Label("\(controller.selectedModel.downloadSize) model installed", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("notes.modelReady")
                    Button(notes == nil ? "Generate notes" : "Generate again") {
                        if notes == nil { generate() } else { replaceNotes = true }
                    }
                    .disabled(controller.isBusy || transcription.isBusy || audio.recordingID != nil || transcript == nil)
                    .accessibilityIdentifier("notes.generate")
                    Text("Long English transcripts are split into sections in transcript order. Later sections may revise earlier decisions. Designed for up to about an hour of speech (16,000 words maximum); device validation is ongoing. Processing may take several minutes.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Download model · \(controller.selectedModel.downloadSize)") { controller.download() }
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("notes.download")
                    Text("Downloads model files from Hugging Face. Once installed, notes work in Airplane Mode. Your transcript is processed on this iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if controller.isBusy && (generating || controller.activeRecordingID == nil) {
                    if let progress = controller.downloadProgress {
                        ProgressView(value: progress) { Text(controller.phase) }
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption).monospacedDigit()
                    } else {
                        ProgressView(controller.phase)
                    }
                    if let start = controller.startedAt {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text("Elapsed \(audioTime(context.date.timeIntervalSince(start)))")
                                .font(.caption).monospacedDigit()
                        }
                    }
                    Button("Cancel", role: .cancel) { controller.cancel() }
                        .accessibilityIdentifier("notes.cancel")
                    Text("Keep Cedar open while processing. The screen stays awake; leaving the app cancels this run.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let recovery = store.recoveryNotice {
                Section { Label(recovery, systemImage: "arrow.clockwise.circle").font(.footnote) }
            }
            if let error = loadError ?? store.loadError ?? audio.errorMessage ?? (showsFeedback ? controller.errorMessage : nil) {
                Section("Couldn’t finish") { Text(error).accessibilityIdentifier("notes.error") }
            }
            if let notes {
                Section(notes.isEdited ? "Edited notes" : "Generated notes") {
                    Text(NotesModel.displayName(for: notes.modelID))
                        .font(.caption).foregroundStyle(.secondary)
                    if let transcript, !notes.matches(transcript) {
                        Label("Transcript changed. Generate again to update these notes.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                    Text(notes.text).textSelection(.enabled).accessibilityIdentifier("notes.text")
                    Button("Edit notes") { showEditor = true }
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("notes.edit")
                    Button {
                        UIPasteboard.general.string = notes.text
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy notes", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityIdentifier("notes.copy")
                    ShareLink(item: notes.text, preview: SharePreview("Cedar notes")) {
                        Label("Share notes", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("notes.share")
                    Button("Previous versions") { showHistory = true }
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("notes.history")
                    Text("Generated in \(notes.processingSeconds.formatted(.number.precision(.fractionLength(1)))) seconds · Transcript revision \(notes.transcriptRevision)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let notes {
                Section("Listen to the source") {
                    if let transcript, notes.matches(transcript) {
                        Text("Playback starts at the matched transcript segment, not an exact word. For repeated text, choose a timestamp.").font(.caption).foregroundStyle(.secondary)
                        if sourceExcerpts.isEmpty { Text("No exact transcript matches found. Open Transcript to check these notes against the audio.").font(.footnote) }
                        ForEach(sourceExcerpts) { excerpt in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(excerpt.quote).font(.subheadline)
                                ForEach(excerpt.locations) { match in
                                    Button { play(match) } label: { Label("Listen from \(audioTime(Double(match.startMS) / 1000))", systemImage: "play.circle") }
                                        .disabled(audio.recordingID != nil || transcription.isBusy || controller.isBusy)
                                        .accessibilityIdentifier("notes.source.\(match.id)")
                                }
                            }.buttonStyle(.borderless).padding(.vertical, 4)
                        }
                        if audio.playingID == recordingID {
                            Button(audio.isPlaying ? "Pause source audio" : "Resume source audio") {
                                if audio.isPlaying { audio.pausePlayback() }
                                else if let item = store.recordings.first(where: { $0.id == recordingID }) { audio.togglePlayback(item) }
                            }.accessibilityIdentifier("notes.pauseSource")
                            Button("Bookmark source position") {
                                do {
                                    let marker = try audio.bookmarkPlaybackPosition()
                                    bookmarkFeedback = "Bookmarked \(audioTime(marker.seconds))."
                                } catch { loadError = error.localizedDescription }
                            }.accessibilityIdentifier("notes.bookmarkSource")
                            if let bookmarkFeedback { Text(bookmarkFeedback).font(.caption) }
                        }
                    } else { Text("The transcript changed. Regenerate notes before using source playback.").font(.footnote) }
                }
                Section("Keep track of actions") {
                    Text("Save a task explicitly to track it here. Suggested follow-up questions aren’t imported automatically.").font(.caption)
                    ForEach(SuggestedAction.parse(notes.text)) { action in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(action.title)
                            Button(addedActions.contains(action.id) ? "Added to checklist" : "Add to checklist") {
                                do { _ = try store.addChecklistAction(action, notes: notes); addedActions.insert(action.id) }
                                catch { loadError = error.localizedDescription }
                            }
                            .disabled(controller.isBusy || transcript.map { !notes.matches($0) } != false || addedActions.contains(action.id))
                            .accessibilityIdentifier("notes.addAction")
                        }
                    }
                    NavigationLink { ChecklistView(recordingID: recordingID) } label: { Label("Open action checklist", systemImage: "checklist") }
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("notes.checklist")
                }
            }
            Section {
                Button("Model licenses and source") { showLicenses = true }
                if controller.retiredModelsRemain {
                    Button("Remove old downloads") { controller.removeRetiredModels() }
                        .disabled(controller.isBusy)
                }
                if controller.modelReady {
                    Button("Remove downloaded model", role: .destructive) { controller.removeModel() }
                        .disabled(controller.isBusy)
                }
            }
        }
        .navigationTitle("Offline notes")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(CedarStyle.cream)
        .tint(CedarStyle.forest)
        .task { load() }
        .onChange(of: store.notesUpdates) { _, _ in load() }
        .onChange(of: store.transcriptUpdates) { _, _ in load() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { controller.cancel() } }
        .onDisappear { if generating { controller.cancel() } }
        .confirmationDialog("Replace generated notes?", isPresented: $replaceNotes, titleVisibility: .visible) {
            Button("Generate again") { generate() }
        } message: { Text("The current notes are retained as a local revision.") }
        .sheet(isPresented: $showLicenses) { NotesLicensesView() }
        .sheet(isPresented: $showEditor) { if let notes { NotesEditor(document: notes) } }
        .sheet(isPresented: $showHistory) { if let notes { NotesHistoryView(document: notes) } }
    }

    private func play(_ source: SourceLocation) {
        guard let item = store.recordings.first(where: { $0.id == recordingID }) else { return }
        audio.errorMessage = nil
        if audio.playingID != recordingID || !audio.isPlaying { audio.togglePlayback(item) }
        if audio.playingID == recordingID { audio.seek(to: Double(source.startMS) / 1000) }
    }

    private func generate() {
        guard let transcript else { return }
        audio.stopPlayback()
        controller.generate(from: transcript, store: store)
    }

    private func load() {
        do {
            transcript = try store.loadTranscript(for: recordingID)
            notes = try store.loadNotes(for: recordingID)
            loadError = nil
            copied = false
            addedActions = []
            if let notes, let transcript, notes.matches(transcript) {
                sourceExcerpts = TranscriptSources.excerpts(in: notes.text).compactMap { quote in
                    let matches = TranscriptSources.locations(for: quote, in: transcript)
                    return matches.isEmpty ? nil : SourceExcerpt(quote: quote, locations: matches)
                }
            } else { sourceExcerpts = [] }
        } catch { loadError = error.localizedDescription }
    }
}

private struct NotesLicensesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Qwen3 0.6B by the Qwen team · Apache 2.0. Q4_K_M conversion by Unsloth.")
                    Link("Qwen model and license", destination: URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B")!)
                    Link("Compressed model", destination: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF")!)
                    Text(license("Qwen")).font(.caption).textSelection(.enabled)
                }
                Section("llama.cpp · MIT") {
                    Link("Runtime source · b9000", destination: URL(string: "https://github.com/ggml-org/llama.cpp/tree/b9000")!)
                    Text(license("llama")).font(.caption).textSelection(.enabled)
                }
            }
            .navigationTitle("Licenses")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func license(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

private struct NotesEditor: View {
    @EnvironmentObject private var store: RecordingStore
    @Environment(\.dismiss) private var dismiss
    @State private var original: LocalNotes
    @State private var text: String
    @State private var errorMessage: String?

    init(document: LocalNotes) {
        _original = State(wrappedValue: document)
        _text = State(wrappedValue: document.text)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .accessibilityLabel("Notes text")
                .accessibilityIdentifier("notes.editField")
                .navigationTitle("Edit notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try store.editNotes(original, text: text); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("notes.save")
                    }
                }
                .alert("Couldn’t save notes", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
        }
        .tint(CedarStyle.forest)
    }
}

private struct NotesHistoryView: View {
    @EnvironmentObject private var store: RecordingStore
    @Environment(\.dismiss) private var dismiss
    @State private var original: LocalNotes
    @State private var revisions: [NotesRevision] = []
    @State private var errorMessage: String?

    init(document: LocalNotes) { _original = State(wrappedValue: document) }

    var body: some View {
        NavigationStack {
            List {
                if revisions.isEmpty { Text("No previous versions yet.") }
                ForEach(revisions) { revision in
                    Section {
                        Text((revision.notes.updatedAt ?? revision.notes.createdAt).formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(revision.notes.text).textSelection(.enabled)
                        Button("Restore this version") {
                            do { try store.restoreNotes(revision, replacing: original); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }
                        .accessibilityIdentifier("notes.restore")
                    }
                }
            }
            .navigationTitle("Previous versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do { revisions = try store.notesRevisions(for: original.recordingID) }
                catch { errorMessage = error.localizedDescription }
            }
            .alert("Couldn’t open version", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(CedarStyle.forest)
    }
}
