import SwiftUI
#if DEBUG && targetEnvironment(simulator)
import AVFoundation
#endif

@main
struct CedarApp: App {
    @StateObject private var store: RecordingStore
    @StateObject private var audio: AudioController
    @StateObject private var transcription: TranscriptionController
    @StateObject private var notes = NotesController()

    init() {
        let store = RecordingStore()
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--notes-fixture"), store.recordings.isEmpty,
           store.root.deletingLastPathComponent().lastPathComponent == "CedarUITests" {
            do {
                let item = try store.create()
                do {
                    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
                    let file = try AVAudioFile(forWriting: store.audioURL(for: item.id), settings: format.settings)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
                    buffer.frameLength = 16_000
                    buffer.floatChannelData![0].initialize(repeating: 0, count: 16_000)
                    try file.write(from: buffer)
                }
                try store.finish(id: item.id, duration: 1, status: .saved)
                let transcript = try store.saveTranscript(Transcript(recordingID: item.id, localeID: "en-US", provider: "UI test",
                    segments: [TranscriptSegment(startMS: 0, endMS: 900, text: "Maya will test Cedar on Friday.")]))
                try store.saveNotes(LocalNotes(recordingID: item.id, transcriptRevision: transcript.revision,
                    transcriptFingerprint: LocalNotes.fingerprint(transcript), modelID: NotesModel.qwen06.rawValue,
                    createdAt: Date(), processingSeconds: 1, text: "Original notes"))
            } catch { assertionFailure("Could not prepare isolated notes test: \(error)") }
        }
        #endif
        _store = StateObject(wrappedValue: store)
        _audio = StateObject(wrappedValue: AudioController(store: store))
        _transcription = StateObject(wrappedValue: TranscriptionController(store: store))
    }

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .environmentObject(store)
                .environmentObject(audio)
                .environmentObject(transcription)
                .environmentObject(notes)
        }
    }
}
