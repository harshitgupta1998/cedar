import SwiftUI

struct TranscriptView: View {
    let recordingID: UUID
    @EnvironmentObject private var store: RecordingStore
    @EnvironmentObject private var controller: TranscriptionController
    @EnvironmentObject private var audio: AudioController
    @AppStorage("transcription.locale") private var localeID = Locale.preferredLanguages.first ?? "en-US"
    @State private var transcript: Transcript?
    @State private var loadError: String?
    @State private var showEditor = false
    @State private var showReplace = false

    private var item: Recording? { store.recordings.first { $0.id == recordingID } }
    private var busy: Bool { controller.activeRecordingID == recordingID }
    private var showsFeedback: Bool { controller.lastOperationRecordingID == recordingID }

    var body: some View {
        List {
            Section {
                Text("Turn your recording into words.")
                    .font(.system(.title2, design: .serif))
                Text("Transcription runs on this iPhone. Review the words against your audio before relying on them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Language", selection: $localeID) {
                    ForEach(AppleTranscriptionProvider.languages, id: \.self) { id in
                        Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id)
                    }
                }
                .disabled(controller.isBusy)
                .accessibilityIdentifier("transcript.language")
                if controller.checking {
                    ProgressView("Checking on-device support…")
                } else if let capability = controller.capability {
                    Text(capability.message)
                        .font(.footnote)
                        .accessibilityIdentifier("transcript.capability")
                    if capability.readiness == .downloadRequired {
                        Button("Download language") {
                            guard let item else { return }
                            controller.download(for: item, localeID: localeID)
                        }
                        .disabled(controller.isBusy)
                        Text("This downloads Apple’s language model. Your audio stays on your iPhone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if capability.readiness == .ready {
                        Button(transcript == nil ? "Transcribe recording" : "Transcribe again") {
                            if transcript == nil { begin() } else { showReplace = true }
                        }
                        .disabled(controller.isBusy || audio.recordingID != nil)
                        .accessibilityIdentifier("transcript.start")
                    }
                }
            }

            if busy {
                Section {
                    ProgressView(controller.phase)
                    if controller.processedThrough > 0 {
                        Text("Processed through \(audioTime(controller.processedThrough))")
                            .font(.caption)
                    }
                    Button("Cancel transcription", role: .cancel) { controller.cancel(for: recordingID) }
                        .accessibilityIdentifier("transcript.cancel")
                    Text("Keep Cedar open while processing. Leaving this screen cancels the task.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if showsFeedback && !controller.phase.isEmpty {
                Section { Text(controller.phase).font(.footnote) }
            }

            if let error = (showsFeedback ? controller.errorMessage : nil) ?? loadError {
                Section("Couldn’t finish") {
                    Text(error)
                        .accessibilityIdentifier("transcript.error")
                    if showsFeedback && controller.permissionDenied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }

            if let transcript {
                Section {
                    Label(transcript.edited ? "Edited transcript" : "Saved transcript", systemImage: "doc.text")
                    Text("\(Locale.current.localizedString(forIdentifier: transcript.localeID) ?? transcript.localeID) · Revision \(transcript.revision)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Edit transcript") { showEditor = true }
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("transcript.edit")
                }
                Section("Tap a timestamp to listen") {
                    ForEach(transcript.segments) { segment in
                        VStack(alignment: .leading, spacing: 12) {
                            Button(audioTime(Double(segment.startMS) / 1000)) {
                                guard let item else { return }
                                if audio.playingID != recordingID || !audio.isPlaying { audio.togglePlayback(item) }
                                audio.seek(to: Double(segment.startMS) / 1000)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Play from \(audioTime(Double(segment.startMS) / 1000))")
                            Text(segment.text)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CedarStyle.cream)
        .tint(CedarStyle.forest)
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: localeID) {
            loadTranscript()
            await controller.refresh(localeID: localeID)
        }
        .onChange(of: store.transcriptUpdates) { _, _ in loadTranscript() }
        .onDisappear { controller.cancel(for: recordingID) }
        .sheet(isPresented: $showEditor) {
            if let transcript { TranscriptEditor(document: transcript) }
        }
        .confirmationDialog("Replace the current transcript?", isPresented: $showReplace, titleVisibility: .visible) {
            Button("Transcribe again") { begin() }
        } message: {
            Text("The new transcript will replace the current text. Previous revisions are retained locally.")
        }
    }

    private func begin() {
        guard let item else { return }
        audio.stopPlayback()
        controller.transcribe(item, localeID: localeID)
    }

    private func loadTranscript() {
        do { transcript = try store.loadTranscript(for: recordingID); loadError = nil }
        catch { loadError = "The saved transcript could not be read. Your audio and transcript file have been kept." }
    }
}

private struct TranscriptEditor: View {
    @EnvironmentObject private var store: RecordingStore
    @Environment(\.dismiss) private var dismiss
    @State var document: Transcript
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Correct each segment’s words. Timestamps keep pointing to the original audio.")
                        .font(.footnote)
                }
                ForEach($document.segments) { $segment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(audioTime(Double(segment.startMS) / 1000)).font(.caption).monospacedDigit()
                        TextField("Transcript text", text: $segment.text, axis: .vertical)
                            .lineLimit(2...10)
                            .accessibilityLabel("Text at \(audioTime(Double(segment.startMS) / 1000))")
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle("Edit transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { document.edited = true; _ = try store.saveTranscript(document); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            }
            .alert("Couldn’t save transcript", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(CedarStyle.forest)
    }
}
