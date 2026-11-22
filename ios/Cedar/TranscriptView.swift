import SwiftUI

struct TranscriptView: View {
    let recordingID: UUID
    @EnvironmentObject private var store: RecordingStore
    @EnvironmentObject private var controller: TranscriptionController
    @EnvironmentObject private var audio: AudioController
    @EnvironmentObject private var notes: NotesController
    @AppStorage("transcription.locale") private var localeID = Locale.preferredLanguages.first ?? "en-US"
    @State private var transcript: Transcript?
    @State private var loadError: String?
    @State private var showEditor = false
    @State private var showReplace = false
    @State private var findText = ""
    @State private var findResult = TranscriptFindResult()
    @State private var selectedMatch: UUID?
    @State private var completedFind: TranscriptFindRequest?
    @State private var isFinding = false
    @State private var jumpRequest = 0
    @State private var showTranscriptionOptions = false
    @State private var bookmarkFeedback: String?
    @FocusState private var findFocused: Bool

    private var findRequest: TranscriptFindRequest {
        TranscriptFindRequest(query: findText.trimmingCharacters(in: .whitespacesAndNewlines), revision: transcript?.revision ?? 0)
    }
    private var findReady: Bool { completedFind == findRequest && !isFinding }
    private var matchPosition: Int { selectedMatch.flatMap { findResult.ids.firstIndex(of: $0) } ?? 0 }


    private var item: Recording? { store.recordings.first { $0.id == recordingID } }
    private var busy: Bool { controller.activeRecordingID == recordingID }
    private var showsFeedback: Bool { controller.lastOperationRecordingID == recordingID }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let recovery = store.recoveryNotice {
                    Section { Label(recovery, systemImage: "arrow.clockwise.circle").font(.footnote) }
                }
                Section {
                    if transcript != nil {
                        DisclosureGroup("Transcription options", isExpanded: $showTranscriptionOptions) {
                            transcriptionOptions
                        }.id("transcript.top")
                    } else { transcriptionOptions.id("transcript.top") }
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

                if let error = (showsFeedback ? controller.errorMessage : nil) ?? loadError ?? audio.errorMessage {
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
                    Section {
                        NavigationLink { NotesView(recordingID: recordingID) } label: {
                            Label("Offline notes", systemImage: "sparkles")
                        }
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("transcript.notes")
                    }
                    Section("Tap a timestamp to listen") {
                        ForEach(transcript.segments) { segment in
                            segmentRow(segment).id(segment.id)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) {
                if transcript != nil {
                    findPanel {
                        findFocused = false
                        proxy.scrollTo("transcript.top", anchor: .top)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if audio.playingID == recordingID, let item {
                    HStack {
                        Button {
                            audio.togglePlayback(item)
                        } label: { Label(audio.isPlaying ? "Pause" : "Play", systemImage: audio.isPlaying ? "pause.fill" : "play.fill") }
                            .accessibilityIdentifier("transcript.playback")
                        Button {
                            do {
                                let marker = try audio.bookmarkPlaybackPosition()
                                bookmarkFeedback = "Bookmarked \(audioTime(marker.seconds))."
                            } catch { audio.errorMessage = error.localizedDescription }
                        } label: { Image(systemName: bookmarkFeedback == nil ? "bookmark" : "bookmark.fill") }
                            .accessibilityLabel("Bookmark playback position")
                            .accessibilityValue(bookmarkFeedback ?? "")
                            .accessibilityIdentifier("transcript.bookmark")
                        Spacer()
                        Text("\(audioTime(audio.playbackTime)) / \(audioTime(audio.playbackDuration))")
                            .font(.caption).monospacedDigit()
                    }.padding().background(CedarStyle.cream)
                        .onAppear { if selectedMatch != nil { jumpRequest += 1 } }
                }
            }
            .task(id: findRequest) { await find() }
            .onChange(of: jumpRequest) { _, _ in if let selectedMatch { proxy.scrollTo(selectedMatch, anchor: .center) } }
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
    }

    private var transcriptionOptions: some View {
        Group {
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
                    .disabled(controller.isBusy || notes.activeRecordingID != nil || audio.recordingID != nil)
                    .accessibilityIdentifier("transcript.start")
                }
            }
        }
    }

    private func findPanel(start: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Find in transcript", text: $findText)
                    .textFieldStyle(.roundedBorder).focused($findFocused)
                    .submitLabel(.search).onSubmit { findFocused = false }
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("transcript.find")
                if !findText.isEmpty {
                    Button("Clear") { findText = ""; findFocused = false }.accessibilityIdentifier("transcript.clearFind")
                }
            }
            Text(findRequest.query.isEmpty ? "Find a word or phrase within transcript segments." :
                 (!findReady ? "Finding…" : (findResult.ids.isEmpty ? "No matching segments" : "\(findResult.ids.count) matching segments · \(matchPosition + 1) of \(findResult.ids.count)")))
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("transcript.findStatus")
            HStack {
                Button { moveMatch(-1) } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Previous matching segment").accessibilityIdentifier("transcript.previousMatch")
                    .accessibilityValue(findResult.ids.isEmpty ? "No matches" : "\(matchPosition + 1) of \(findResult.ids.count)")
                    .disabled(!findReady || findResult.ids.isEmpty)
                Button { moveMatch(1) } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Next matching segment").accessibilityIdentifier("transcript.nextMatch")
                    .accessibilityValue(findResult.ids.isEmpty ? "No matches" : "\(matchPosition + 1) of \(findResult.ids.count)")
                    .disabled(!findReady || findResult.ids.isEmpty)
                Button("Play match") {
                    findFocused = false
                    guard let id = selectedMatch, let segment = transcript?.segments.first(where: { $0.id == id }) else { return }
                    jumpRequest += 1
                    play(segment)
                }.accessibilityIdentifier("transcript.playMatch")
                    .disabled(!findReady || findResult.ids.isEmpty || audio.recordingID != nil || controller.isBusy || notes.activeRecordingID != nil)
                Spacer(minLength: 0)
                Button("Start", action: start).accessibilityLabel("Back to transcript start")
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal).padding(.vertical, 8).background(CedarStyle.cream)
    }

    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(audioTime(Double(segment.startMS) / 1000)) { play(segment) }
                .buttonStyle(.bordered)
                .disabled(audio.recordingID != nil || controller.isBusy || notes.activeRecordingID != nil)
                .accessibilityLabel("Play from \(audioTime(Double(segment.startMS) / 1000))")
            Text(findReady ? (findResult.highlighted[segment.id] ?? AttributedString(segment.text)) : AttributedString(segment.text))
                .textSelection(.enabled).accessibilityIdentifier("transcript.segment.\(segment.id)")
        }
        .padding(.vertical, 8)
        .listRowBackground(findReady && selectedMatch == segment.id ? CedarStyle.forest.opacity(0.12) : Color.clear)
    }

    private func moveMatch(_ offset: Int) {
        guard findReady, !findResult.ids.isEmpty else { return }
        findFocused = false
        selectedMatch = findResult.ids[(matchPosition + offset + findResult.ids.count) % findResult.ids.count]
        jumpRequest += 1
    }

    private func play(_ segment: TranscriptSegment) {
        guard audio.recordingID == nil, !controller.isBusy, notes.activeRecordingID == nil, let item else { return }
        audio.errorMessage = nil
        if audio.playingID != recordingID || !audio.isPlaying { audio.togglePlayback(item) }
        if audio.playingID == recordingID { audio.seek(to: Double(segment.startMS) / 1000) }
    }

    private func find() async {
        let request = findRequest
        guard !request.query.isEmpty, let segments = transcript?.segments else {
            findResult = TranscriptFindResult(); selectedMatch = nil; completedFind = request; isFinding = false
            return
        }
        isFinding = true
        do {
            try await Task.sleep(for: .milliseconds(150))
            let worker = Task.detached(priority: .userInitiated) { try TranscriptFind.scan(segments, query: request.query) }
            let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard findRequest == request else { return }
            findResult = result
            selectedMatch = result.ids.first
            if selectedMatch != nil { jumpRequest += 1 }
            completedFind = request
            isFinding = false
        } catch {
            if !Task.isCancelled { findResult = TranscriptFindResult(); selectedMatch = nil; completedFind = request; isFinding = false }
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
