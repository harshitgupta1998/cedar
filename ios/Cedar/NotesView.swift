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

    private var generating: Bool { controller.activeRecordingID == recordingID }
    private var showsFeedback: Bool { controller.lastRecordingID == nil || controller.lastRecordingID == recordingID }

    var body: some View {
        List {
            Section("Offline notes · Experimental") {
                Text("Generate a short summary on this iPhone. Review names, dates and decisions against your transcript.")
                    .font(.subheadline)
                Picker("Notes model", selection: $controller.selectedModel) {
                    ForEach(NotesModel.allCases) { model in Text(model.name).tag(model) }
                }
                .disabled(controller.isBusy)
                .accessibilityIdentifier("notes.model")
                Text(controller.selectedModel == .smol360 ? "Compact model · 271 MB" : "Larger model · 1.11 GB · Uses more memory")
                    .font(.caption).foregroundStyle(.secondary)
                if controller.modelReady {
                    Label("\(controller.selectedModel.downloadSize) model installed", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("notes.modelReady")
                    Button(notes == nil ? "Generate notes" : "Generate again") {
                        if notes == nil { generate() } else { replaceNotes = true }
                    }
                    .disabled(controller.isBusy || transcription.isBusy || audio.recordingID != nil || transcript == nil)
                    .accessibilityIdentifier("notes.generate")
                    Text("Start with a short English recording, around five minutes or less.")
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
                    Text("Keep Cedar open while processing.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let recovery = store.recoveryNotice {
                Section { Label(recovery, systemImage: "arrow.clockwise.circle").font(.footnote) }
            }
            if let error = loadError ?? store.loadError ?? (showsFeedback ? controller.errorMessage : nil) {
                Section("Couldn’t finish") { Text(error).accessibilityIdentifier("notes.error") }
            }
            if let notes {
                Section(notes.isEdited ? "Edited notes" : "Generated notes") {
                    Text(NotesModel(rawValue: notes.modelID)?.name ?? notes.modelID)
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
            Section {
                Button("Model licenses and source") { showLicenses = true }
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
        } catch { loadError = error.localizedDescription }
    }
}

private struct NotesLicensesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("SmolLM2 360M Instruct by Hugging Face · Apache 2.0. Q4_K_M conversion by Unsloth.")
                    Text("Qwen3 1.7B by the Qwen team · Apache 2.0. Q4_K_M conversion by Unsloth.")
                    Link("Qwen model and license", destination: URL(string: "https://huggingface.co/Qwen/Qwen3-1.7B")!)
                    Link("Original model", destination: URL(string: "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct")!)
                    Link("Compressed model", destination: URL(string: "https://huggingface.co/unsloth/SmolLM2-360M-Instruct-GGUF")!)
                    Text(license("SmolLM2")).font(.caption).textSelection(.enabled)
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
