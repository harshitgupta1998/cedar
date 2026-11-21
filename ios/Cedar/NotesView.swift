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

    private var generating: Bool { controller.activeRecordingID == recordingID }
    private var showsFeedback: Bool { controller.lastRecordingID == nil || controller.lastRecordingID == recordingID }

    var body: some View {
        List {
            Section("Offline notes · Experimental") {
                Text("SmolLM2 360M turns short English transcripts into a short summary. Review generated details against your transcript.")
                    .font(.subheadline)
                if controller.modelReady {
                    Label("271 MB model installed", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("notes.modelReady")
                    Button(notes == nil ? "Generate notes" : "Generate again") {
                        if notes == nil { generate() } else { replaceNotes = true }
                    }
                    .disabled(controller.isBusy || transcription.isBusy || audio.recordingID != nil || transcript == nil)
                    .accessibilityIdentifier("notes.generate")
                    Text("Start with recordings around five minutes or less. The current limit is 3,500 input tokens, including instructions.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Download model · 271 MB") { controller.download() }
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("notes.download")
                    Text("Downloads model files from Hugging Face. Once installed, notes work in Airplane Mode. Your transcript is processed on this iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if controller.isBusy && (generating || controller.activeRecordingID == nil) {
                    ProgressView(controller.phase)
                    Button("Cancel", role: .cancel) { controller.cancel() }
                        .accessibilityIdentifier("notes.cancel")
                    Text("Keep Cedar open while processing.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = loadError ?? (showsFeedback ? controller.errorMessage : nil) {
                Section("Couldn’t finish") { Text(error).accessibilityIdentifier("notes.error") }
            }
            if let notes {
                Section("Generated notes") {
                    if let transcript, !notes.matches(transcript) {
                        Label("Transcript changed. Generate again to update these notes.", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.footnote)
                    }
                    Text(notes.text).textSelection(.enabled).accessibilityIdentifier("notes.text")
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
                    Link("Original model", destination: URL(string: "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct")!)
                    Link("Compressed model", destination: URL(string: "https://huggingface.co/unsloth/SmolLM2-360M-Instruct-GGUF")!)
                    Text(license("SmolLM2")).font(.caption).textSelection(.enabled)
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
