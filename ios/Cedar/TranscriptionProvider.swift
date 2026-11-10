import AVFoundation
import CoreMedia
import Speech

@MainActor
protocol TranscriptionProvider {
    func capability(for localeID: String) async -> SpeechCapability
    func downloadModel(for capability: SpeechCapability) async throws
    func transcribe(url: URL, capability: SpeechCapability,
                    progress: @escaping @MainActor (TimeInterval) -> Void) async throws -> [TranscriptSegment]
    func cancel()
}

@MainActor
final class AppleTranscriptionProvider: TranscriptionProvider {
    private var legacyRecognizer: SFSpeechRecognizer?
    private var legacyID: UUID?
    private var downloadProgress: Progress?
    private var legacyTask: SFSpeechRecognitionTask?
    private var legacyContinuation: CheckedContinuation<[TranscriptSegment], Error>?
    private var legacyTimeout: Task<Void, Never>?
    private var cancelModern: (() -> Void)?

    static var languages: [String] {
        let current = Locale.preferredLanguages.first ?? "en-US"
        return Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") } + [current]).sorted {
            (Locale.current.localizedString(forIdentifier: $0) ?? $0) < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
        }
    }

    func capability(for localeID: String) async -> SpeechCapability {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let locale = Locale(identifier: localeID)
            if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                let module = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
                let state = await AssetInventory.status(forModules: [module])
                if state != .unsupported { return modernCapability(engine: .speechAnalyzer, locale: supported, status: state) }
            }
            if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
                let module = DictationTranscriber(locale: supported, preset: .timeIndexedLongDictation)
                let state = await AssetInventory.status(forModules: [module])
                if state != .unsupported { return modernCapability(engine: .dictationAnalyzer, locale: supported, status: state) }
            }
        }
        #endif
        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.supportsOnDeviceRecognition {
            return SpeechCapability(engine: .legacy, localeID: recognizer.locale.identifier, readiness: .ready,
                                    message: "On-device recognition is available for clips up to 55 seconds.", maxDuration: 55)
        }
        return SpeechCapability(engine: .unavailable, localeID: localeID, readiness: .unavailable,
                                message: "On-device transcription is not available for this language on this iPhone. Try another language. Your audio stays available for playback.", maxDuration: nil)
    }

    func downloadModel(for capability: SpeechCapability) async throws {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let modules = try modernModules(for: capability)
            _ = try await AssetInventory.reserve(locale: Locale(identifier: capability.localeID))
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                downloadProgress = request.progress
                defer { downloadProgress = nil }
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: modules) == .installed else { throw TranscriptionError.downloadRequired }
            return
        }
        #endif
        throw TranscriptionError.unavailable("This iOS version cannot install a speech model through Cedar.")
    }

    func transcribe(url: URL, capability: SpeechCapability,
                    progress: @escaping @MainActor (TimeInterval) -> Void) async throws -> [TranscriptSegment] {
        guard capability.readiness == .ready else { throw TranscriptionError.downloadRequired }
        try Task.checkCancellation()
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard authorization == .authorized else { throw TranscriptionError.permissionDenied }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            switch capability.engine {
            case .speechAnalyzer:
                let module = SpeechTranscriber(locale: Locale(identifier: capability.localeID), transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
                return try await analyze(module: module, url: url, progress: progress) { result in
                    Self.segment(text: String(result.text.characters), range: result.range)
                }
            case .dictationAnalyzer:
                let module = DictationTranscriber(locale: Locale(identifier: capability.localeID), preset: .timeIndexedLongDictation)
                return try await analyze(module: module, url: url, progress: progress) { result in
                    Self.segment(text: String(result.text.characters), range: result.range)
                }
            default: break
            }
        }
        #endif
        guard capability.engine == .legacy else { throw TranscriptionError.unavailable(capability.message) }
        return try await recognizeLegacy(url: url, capability: capability, progress: progress)
    }

    func cancel() {
        cancelModern?()
        downloadProgress?.cancel()
        finishLegacy(.failure(CancellationError()))
    }

    private func recognizeLegacy(url: URL, capability: SpeechCapability,
                                 progress: @escaping @MainActor (TimeInterval) -> Void) async throws -> [TranscriptSegment] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: capability.localeID)),
              recognizer.supportsOnDeviceRecognition else { throw TranscriptionError.unavailable("This language cannot be recognized on this device. Audio has not been uploaded.") }
        guard let duration = RecordingStore.readableDuration(at: url), duration <= 55 else {
            throw TranscriptionError.unavailable("This iPhone’s fallback recognizer supports clips up to 55 seconds. Choose a shorter recording.")
        }
        guard recognizer.isAvailable else { throw TranscriptionError.unavailable("On-device speech recognition is temporarily unavailable. Try again later.") }
        let token = UUID()
        legacyRecognizer = recognizer
        legacyID = token
        let request = SFSpeechURLRecognitionRequest(url: url)
        // Both the capability guard above and this flag are required to fail closed.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                legacyContinuation = continuation
                legacyTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let final = result?.isFinal ?? false
                    var segments: [TranscriptSegment] = []
                    if let best = result?.bestTranscription, !best.formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let first = best.segments.first?.timestamp ?? 0
                        let last = best.segments.last.map { $0.timestamp + $0.duration } ?? duration
                        let start = first.isFinite ? max(0, first) : 0
                        let end = last.isFinite ? max(start, last) : duration
                        segments = [TranscriptSegment(startMS: Int(start * 1000), endMS: Int(end * 1000), text: best.formattedString)]
                    }
                    let errorMessage = error?.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self, self.legacyContinuation != nil, self.legacyID == token else { return }
                        if let last = segments.last { progress(Double(last.endMS) / 1000) }
                        if final { self.finishLegacy(.success(segments)) }
                        else if let errorMessage { self.finishLegacy(.failure(TranscriptionError.unavailable("On-device recognition failed: \(errorMessage)"))) }
                    }
                }
                legacyTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled else { return }
                    self?.finishLegacy(.failure(TranscriptionError.timedOut), expectedID: token)
                }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.finishLegacy(.failure(CancellationError()), expectedID: token) } })
    }

    private func finishLegacy(_ result: Result<[TranscriptSegment], Error>, expectedID: UUID? = nil) {
        guard expectedID == nil || expectedID == legacyID, let continuation = legacyContinuation else { return }
        legacyContinuation = nil
        legacyID = nil
        legacyTask?.cancel()
        legacyTask = nil
        legacyRecognizer = nil
        legacyTimeout?.cancel()
        legacyTimeout = nil
        continuation.resume(with: result)
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func modernCapability(engine: SpeechCapability.Engine, locale: Locale, status: AssetInventory.Status) -> SpeechCapability {
        SpeechCapability(engine: engine, localeID: locale.identifier,
                         readiness: status == .installed ? .ready : .downloadRequired,
                         message: status == .installed ? "Ready for on-device transcription." : "Download the language model to transcribe on this iPhone.", maxDuration: nil)
    }

    @available(iOS 26.0, *)
    private func modernModules(for capability: SpeechCapability) throws -> [any SpeechModule] {
        switch capability.engine {
        case .speechAnalyzer:
            return [SpeechTranscriber(locale: Locale(identifier: capability.localeID), transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])]
        case .dictationAnalyzer:
            return [DictationTranscriber(locale: Locale(identifier: capability.localeID), preset: .timeIndexedLongDictation)]
        default: throw TranscriptionError.unavailable(capability.message)
        }
    }

    @available(iOS 26.0, *)
    nonisolated private static func segment(text: String, range: CMTimeRange) -> TranscriptSegment {
        let start = range.start.seconds.isFinite ? max(0, range.start.seconds) : 0
        let end = range.end.seconds.isFinite ? max(start, range.end.seconds) : start
        return TranscriptSegment(startMS: Int(start * 1000), endMS: Int(end * 1000), text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @available(iOS 26.0, *)
    private func analyze<Module: SpeechModule>(module: Module, url: URL,
                                             progress: @escaping @MainActor (TimeInterval) -> Void,
                                             segment: @escaping @Sendable (Module.Result) -> TranscriptSegment) async throws -> [TranscriptSegment] where Module.Result: Sendable {
        let analyzer = SpeechAnalyzer(modules: [module])
        cancelModern = { Task { await analyzer.cancelAndFinishNow() } }
        defer { cancelModern = nil }
        let collector = Task { @MainActor in
            var segments: [TranscriptSegment] = []
            for try await result in module.results {
                try Task.checkCancellation()
                guard result.isFinal else { continue }
                let item = segment(result)
                if !item.text.isEmpty {
                    segments.append(item)
                    progress(Double(item.endMS) / 1000)
                }
            }
            return segments
        }
        return try await withTaskCancellationHandler(operation: {
            do {
                let file = try AVAudioFile(forReading: url)
                if let last = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else { await analyzer.cancelAndFinishNow() }
                let result = try await collector.value
                try Task.checkCancellation()
                return result
            } catch {
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        }, onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        })
    }
    #endif
}
