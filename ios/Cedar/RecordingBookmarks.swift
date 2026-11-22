import Foundation
import SwiftUI

struct RecordingBookmark: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let positionMS: Int
    var title: String
    let createdAt: Date

    var seconds: TimeInterval { Double(positionMS) / 1000 }
}

struct RecordingBookmarks: Codable {
    let formatVersion: Int
    let recordingID: UUID
    var items: [RecordingBookmark]

    func validate(for id: UUID) throws {
        guard formatVersion == 1, recordingID == id, items.count <= 1000,
              Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ $0.positionMS >= 0 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 200 })
        else { throw BookmarkError.invalid }
    }
}

enum BookmarkError: LocalizedError {
    case invalid, unreadable, changed, invalidPosition
    var errorDescription: String? {
        switch self {
        case .invalid: return "Use a bookmark label of 1–200 characters. A recording can hold up to 1,000 bookmarks."
        case .unreadable: return "The saved bookmarks couldn’t be read. Their existing file has been kept."
        case .changed: return "This bookmark changed. Reload it before editing."
        case .invalidPosition: return "This position isn’t within the available recording."
        }
    }
}

struct RecordingBookmarksView: View {
    let recordingID: UUID
    @EnvironmentObject private var store: RecordingStore
    @EnvironmentObject private var audio: AudioController
    @EnvironmentObject private var transcription: TranscriptionController
    @EnvironmentObject private var notes: NotesController
    @State private var bookmarks: [RecordingBookmark] = []
    @State private var editing: RecordingBookmark?
    @State private var errorMessage: String?

    private var recording: Recording? { store.recordings.first { $0.id == recordingID } }
    private var playbackBusy: Bool { audio.recordingID != nil || transcription.isBusy || notes.activeRecordingID != nil }

    var body: some View {
        List {
            Section {
                Text("Mark a moment while recording or listening, then return to its exact audio offset.").font(.subheadline)
                Button("Bookmark current position") {
                    do { try audio.bookmarkPlaybackPosition(); load() }
                    catch { errorMessage = error.localizedDescription }
                }
                .disabled(audio.playingID != recordingID || playbackBusy)
                .accessibilityIdentifier("bookmarks.addPosition")
                if audio.playingID == recordingID {
                    Text("Position \(audioTime(audio.playbackTime))").font(.caption).monospacedDigit()
                    Button(audio.isPlaying ? "Pause audio" : "Resume audio") {
                        if let recording { audio.togglePlayback(recording) }
                    }.disabled(playbackBusy).accessibilityIdentifier("bookmarks.playback")
                } else {
                    Text("Start playback from recording details, or tap a saved bookmark below.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Bookmarks · \(bookmarks.count)") {
                if bookmarks.isEmpty { Text("No bookmarks yet.") }
                ForEach(bookmarks) { bookmark in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(bookmark.title).font(.headline)
                        Button { play(bookmark) } label: {
                            Label("Listen from \(audioTime(bookmark.seconds))", systemImage: "play.circle")
                        }
                        .disabled(playbackBusy || !available(bookmark))
                        .accessibilityIdentifier("bookmark.play.\(bookmark.id)")
                        if !available(bookmark) {
                            Text("This bookmark is outside the available audio, or audio needs recovery. The bookmark has been kept.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Rename bookmark") { editing = bookmark }
                            .accessibilityIdentifier("bookmark.rename.\(bookmark.id)")
                    }
                    .buttonStyle(.borderless).padding(.vertical, 5)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Remove bookmark", role: .destructive) {
                            do { try store.removeBookmark(bookmark, recordingID: recordingID); load() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
            if let message = errorMessage ?? audio.errorMessage {
                Section("Couldn’t finish") { Text(message); Button("Try loading again") { load() } }
            }
        }
        .navigationTitle("Bookmarks").navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(CedarStyle.cream).tint(CedarStyle.forest)
        .task { load() }
        .onChange(of: store.bookmarkUpdates) { _, _ in load() }
        .sheet(item: $editing) { bookmark in BookmarkLabelEditor(recordingID: recordingID, bookmark: bookmark) }
    }

    private func available(_ bookmark: RecordingBookmark) -> Bool {
        guard let recording, ![.recording, .needsRecovery].contains(recording.status) else { return false }
        return bookmark.seconds <= recording.duration + 0.001
    }

    private func play(_ bookmark: RecordingBookmark) {
        guard !playbackBusy, available(bookmark), let recording else { return }
        audio.errorMessage = nil
        if audio.playingID != recordingID || !audio.isPlaying { audio.togglePlayback(recording) }
        if audio.playingID == recordingID { audio.seek(to: bookmark.seconds) }
    }

    private func load() {
        do { bookmarks = try store.loadBookmarks(for: recordingID).items; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct BookmarkLabelEditor: View {
    let recordingID: UUID
    let bookmark: RecordingBookmark
    @EnvironmentObject private var store: RecordingStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Text("At \(audioTime(bookmark.seconds))").font(.caption)
                TextField("Bookmark label", text: $title, axis: .vertical).accessibilityIdentifier("bookmark.label")
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Rename bookmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try store.renameBookmark(bookmark, recordingID: recordingID, title: title); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("bookmark.saveLabel")
                }
            }
            .onAppear { title = bookmark.title }
        }.tint(CedarStyle.forest)
    }
}
