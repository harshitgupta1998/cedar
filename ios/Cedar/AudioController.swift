import AVFoundation
import Combine
import UIKit

@MainActor
final class AudioController: NSObject, ObservableObject {
    @Published private(set) var recordingID: UUID?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var isPreparing = false
    @Published private(set) var playingID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var microphoneDenied = false
    @Published var notice: String?

    private let store: RecordingStore
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    init(store: RecordingStore, notifications: NotificationCenter = .default) {
        self.store = store
        super.init()
        notifications.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      value == AVAudioSession.InterruptionType.began.rawValue else { return }
                self?.interrupt(reason: "Recording was interrupted. The audio captured so far has been kept.")
            }.store(in: &subscriptions)
        notifications.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.interrupt(reason: "The audio service restarted. Cedar kept the recording files; check playback before continuing.")
            }.store(in: &subscriptions)
        notifications.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self?.interrupt(reason: "An audio device disconnected. The audio captured so far has been kept.")
            }.store(in: &subscriptions)
    }

    func startRecording() async {
        guard recordingID == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            microphoneDenied = true
            return
        }
        stopPlayback()
        notice = nil
        var pending: Recording?
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let item = try store.create()
            pending = item
            let url = store.audioURL(for: item.id)
            // Linear PCM in a CAF container avoids an end-of-file AAC encoding dependency.
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else { throw AudioError.cannotRecord }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                 ofItemAtPath: url.path)
            guard recorder.record() else { throw AudioError.cannotRecord }
            self.recorder = recorder
            recordingID = item.id
            elapsed = 0
            level = 0
            startTimer()
        } catch {
            if let item = pending {
                do { try store.finish(id: item.id, duration: 0, status: .needsRecovery) }
                catch { notice = "The unfinished recording files remain on this iPhone. Reopen Cedar to retry recovery." }
            }
            deactivateSession()
            errorMessage = "Couldn’t start recording. \(error.localizedDescription)"
        }
    }

    func stopRecording(status: Recording.Status = .saved) {
        guard let id = recordingID else { return }
        let duration = recorder?.currentTime ?? elapsed
        // Detach before stop so the delegate cannot finalize the same recording twice.
        recordingID = nil
        let active = recorder
        recorder = nil
        active?.stop()
        timer?.invalidate()
        timer = nil
        level = 0
        do {
            try store.finish(id: id, duration: duration, status: status)
            if store.recordings.first(where: { $0.id == id })?.status == .needsRecovery {
                notice = "Cedar kept the audio files, but couldn’t read them yet. Please keep this recording while we check recovery."
            } else if status == .saved {
                notice = "Saved on this iPhone."
            }
        } catch {
            errorMessage = "The audio file is still on this iPhone, but its details couldn’t be saved. Reopen Cedar to retry recovery."
        }
        deactivateSession()
    }

    private func interrupt(reason: String) {
        if recordingID != nil {
            stopRecording(status: .interrupted)
            notice = reason
        }
        if playingID != nil {
            pausePlayback()
            notice = "Playback paused because the audio session changed. Tap Play to continue."
        }
    }

    func togglePlayback(_ item: Recording) {
        guard recordingID == nil, !isPreparing else { return }
        if playingID == item.id && isPlaying {
            pausePlayback()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            if playingID != item.id || player == nil {
                stopPlayback(deactivate: false)
                player = try AVAudioPlayer(contentsOf: store.audioURL(for: item.id))
                player?.delegate = self
                playingID = item.id
                playbackTime = 0
                playbackDuration = player?.duration ?? 0
            }
            guard let player, player.play() else { throw AudioError.cannotPlay }
            isPlaying = true
            startTimer()
        } catch {
            stopPlayback()
            errorMessage = "Couldn’t play this recording. Its files have been kept. \(error.localizedDescription)"
        }
    }

    func pausePlayback() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
        deactivateSession()
    }

    func stopPlayback(deactivate: Bool = true) {
        player?.stop()
        player = nil
        playingID = nil
        isPlaying = false
        playbackTime = 0
        playbackDuration = 0
        if recordingID == nil {
            timer?.invalidate()
            timer = nil
            if deactivate { deactivateSession() }
        }
    }

    func seek(to value: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, value), player.duration)
        playbackTime = player.currentTime
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateProgress() }
        }
    }

    private func updateProgress() {
        if let recorder {
            elapsed = recorder.currentTime
            recorder.updateMeters()
            level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 60) / 60))
        }
        if let player { playbackTime = player.currentTime }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private enum AudioError: LocalizedError {
        case cannotRecord, cannotPlay
        var errorDescription: String? {
            switch self {
            case .cannotRecord: return "The microphone or local audio file is unavailable. Check your audio device and free storage."
            case .cannotPlay: return "This audio file is not currently playable."
            }
        }
    }
}

extension AudioController: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.recorder?.url == url, self.recordingID != nil else { return }
            self.stopRecording(status: flag ? .interrupted : .needsRecovery)
            self.notice = "Recording stopped unexpectedly. The audio files have been kept; check playback before continuing."
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.recorder?.url == url else { return }
            self.stopRecording(status: .interrupted)
            self.errorMessage = "An audio error stopped recording. The audio captured so far has been kept where possible."
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let url = player.url
        Task { @MainActor [weak self] in
            guard let self, self.player?.url == url else { return }
            self.stopPlayback()
            if !flag { self.errorMessage = "Playback stopped unexpectedly. Your recording has not been removed." }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let url = player.url
        Task { @MainActor [weak self] in
            guard let self, self.player?.url == url else { return }
            self.stopPlayback()
            self.errorMessage = "Cedar couldn’t decode this audio. Your recording has not been removed."
        }
    }
}

func audioTime(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.isFinite ? duration : 0))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
