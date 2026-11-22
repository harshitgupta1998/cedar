import Foundation

@MainActor
final class ModelDownload: NSObject, URLSessionDownloadDelegate {
    nonisolated private let destination: URL
    private let configuration: URLSessionConfiguration
    private let progress: (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)

    init(destination: URL, configuration: URLSessionConfiguration = .default, progress: @escaping (Double) -> Void) {
        self.configuration = configuration
        self.destination = destination
        self.progress = progress
    }

    func run(url: URL) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                task = session.downloadTask(with: url)
                task?.resume()
            }
        } onCancel: { Task { @MainActor in self.task?.cancel() } }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        task = nil
        session.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        Task { @MainActor in if self.continuation != nil { self.progress(fraction) } }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let result: Result<Void, Error>
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            // URLSession removes its temporary file after this delegate callback returns.
            try FileManager.default.moveItem(at: location, to: destination)
            result = .success(())
        } catch { result = .failure(error) }
        Task { @MainActor in self.finish(result) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { Task { @MainActor in self.finish(.failure(error)) } }
    }
}
