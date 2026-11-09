import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: RecordingStore
    @EnvironmentObject private var audio: AudioController
    @State private var showDeleted = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your library")
                        .font(.system(.largeTitle, design: .serif))
                        .accessibilityIdentifier("library.heading")
                    Text("A place to come back to.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
                .listRowBackground(Color.clear)
            }

            if let error = store.loadError {
                Section {
                    Text(error)
                    Button("Try loading again") { store.reload() }
                        .disabled(audio.recordingID != nil)
                }
            }

            if audio.recordingID != nil {
                Section {
                    VStack(spacing: 14) {
                        Label("Recording", systemImage: "record.circle.fill")
                            .foregroundStyle(.red)
                            .font(.headline)
                        Text(audioTime(audio.elapsed))
                            .font(.system(.largeTitle, design: .monospaced))
                            .monospacedDigit()
                            .accessibilityIdentifier("recorder.elapsed")
                        ProgressView(value: Double(audio.level))
                            .tint(CedarStyle.forest)
                            .accessibilityLabel("Microphone level")
                        Text("Audio is being saved on this iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }

            if let notice = audio.notice {
                Section {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text(notice).font(.subheadline)
                        Spacer(minLength: 0)
                        Button { audio.notice = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss message")
                    }
                }
            }

            let saved = store.recordings.filter { $0.id != audio.recordingID }
            if saved.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform")
                            .font(.system(size: 40, weight: .light))
                            .accessibilityHidden(true)
                        Text("Start with a conversation")
                            .font(.system(.title2, design: .serif))
                        Text("Tap Record below. When you stop, your audio will be waiting here.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("On this iPhone · \(saved.count)") {
                    ForEach(saved) { item in
                        NavigationLink {
                            RecordingDetailView(recordingID: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title).font(.headline).lineLimit(2)
                                Text("\(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(audioTime(item.duration))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if item.status != .saved {
                                    Text(item.status.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        .accessibilityIdentifier("recording.\(item.id.uuidString)")
                        .disabled(audio.recordingID != nil || audio.isPreparing)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CedarStyle.cream)
        .foregroundStyle(CedarStyle.forest)
        .navigationTitle("Cedar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(audio.recordingID != nil || audio.isPreparing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showDeleted = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Recently deleted")
                    .disabled(audio.recordingID != nil || audio.isPreparing)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    if audio.recordingID != nil {
                        audio.stopRecording()
                    } else {
                        Task { await audio.startRecording() }
                    }
                } label: {
                    HStack(spacing: 12) {
                        if audio.isPreparing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: audio.recordingID == nil ? "mic.fill" : "stop.fill")
                        }
                        Text(audio.isPreparing ? "Preparing…" : (audio.recordingID == nil ? "Record" : "Stop & save"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(.white)
                    .background(audio.recordingID == nil ? CedarStyle.forest : Color(red: 0.65, green: 0.17, blue: 0.17),
                                in: RoundedRectangle(cornerRadius: 18))
                }
                .disabled(audio.isPreparing)
                .accessibilityIdentifier(audio.recordingID == nil ? "recorder.start" : "recorder.stop")
                Text("Record only with permission from everyone involved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(CedarStyle.cream)
        }
        .sheet(isPresented: $showDeleted) { RecentlyDeletedView() }
        .alert("Cedar", isPresented: Binding(
            get: { audio.errorMessage != nil || audio.microphoneDenied },
            set: { if !$0 { audio.errorMessage = nil; audio.microphoneDenied = false } }
        )) {
            if audio.microphoneDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button("OK", role: .cancel) { audio.errorMessage = nil; audio.microphoneDenied = false }
        } message: {
            Text(audio.microphoneDenied
                 ? "Microphone access is off. Enable it in Settings to record. Your library is still available."
                 : (audio.errorMessage ?? ""))
        }
    }
}

struct RecordingDetailView: View {
    let recordingID: UUID
    @EnvironmentObject private var store: RecordingStore
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var showDelete = false
    @State private var title = ""
    @State private var actionError: String?

    private var item: Recording? { store.recordings.first { $0.id == recordingID } }
    private var selected: Bool { audio.playingID == recordingID }

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title)
                            .font(.system(.largeTitle, design: .serif))
                            .accessibilityIdentifier("recording.title")
                        Text(item.createdAt.formatted(date: .long, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(item.status.label, systemImage: "iphone")
                            .font(.footnote)
                    }

                    VStack(spacing: 24) {
                        Image(systemName: "waveform")
                            .font(.system(size: 64, weight: .ultraLight))
                            .accessibilityHidden(true)
                        Slider(value: Binding(
                            get: { selected ? audio.playbackTime : 0 },
                            set: { audio.seek(to: $0) }
                        ), in: 0...max(selected ? audio.playbackDuration : item.duration, 0.1))
                            .disabled(!selected)
                            .accessibilityLabel("Playback position")
                        HStack {
                            Text(audioTime(selected ? audio.playbackTime : 0))
                            Spacer()
                            Text(audioTime(selected ? audio.playbackDuration : item.duration))
                        }
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()

                        Button { audio.togglePlayback(item) } label: {
                            Label(selected && audio.isPlaying ? "Pause" : "Play recording",
                                  systemImage: selected && audio.isPlaying ? "pause.fill" : "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CedarStyle.forest)
                        .accessibilityIdentifier("playback.toggle")
                        Text(selected ? (audio.isPlaying ? "Playing" : "Paused") : "Ready to play")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("playback.status")
                    }
                    .padding(24)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24))

                    Text("Only on this iPhone. Nothing is uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
        .foregroundStyle(CedarStyle.forest)
        .background(CedarStyle.cream.ignoresSafeArea())
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        title = item?.title ?? ""
                        showRename = true
                    }
                    Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) { showDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Recording options")
            }
        }
        .alert("Rename recording", isPresented: $showRename) {
            TextField("Name", text: $title).accessibilityIdentifier("recording.renameField")
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                guard let item else { return }
                do { try store.rename(item, to: title) }
                catch { actionError = error.localizedDescription }
            }
        }
        .confirmationDialog("Move this recording to Recently Deleted?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Move recording", role: .destructive) {
                guard let item else { return }
                do {
                    if selected { audio.stopPlayback() }
                    try store.moveToRecentlyDeleted(item)
                    dismiss()
                } catch { actionError = error.localizedDescription }
            }
        } message: {
            Text("You can restore it later. The audio stays on this iPhone.")
        }
        .alert("Cedar", isPresented: Binding(get: { actionError != nil || audio.errorMessage != nil },
                                             set: { if !$0 { actionError = nil; audio.errorMessage = nil } })) {
            Button("OK", role: .cancel) { actionError = nil; audio.errorMessage = nil }
        } message: { Text(actionError ?? audio.errorMessage ?? "") }
    }
}

private struct RecentlyDeletedView: View {
    @EnvironmentObject private var store: RecordingStore
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Deleted recordings stay on this iPhone. Restore them whenever you need them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if store.deletedRecordings.isEmpty {
                    Text("No deleted recordings")
                } else {
                    ForEach(store.deletedRecordings) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.title).font(.headline)
                            Button("Restore") {
                                do { try store.restore(item) }
                                catch { errorMessage = error.localizedDescription }
                            }
                            .accessibilityLabel("Restore \(item.title)")
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CedarStyle.cream)
            .navigationTitle("Recently deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Couldn’t restore recording", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(CedarStyle.forest)
    }
}
