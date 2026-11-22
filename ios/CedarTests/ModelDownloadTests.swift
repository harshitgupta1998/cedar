import Foundation
import XCTest
@testable import Cedar

private final class DownloadProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "cedar.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let code = request.url?.path == "/fail" ? 500 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "1048576"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.url?.path == "/wait" { return }
        client?.urlProtocol(self, didLoad: Data(repeating: 42, count: 1_048_576))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class ModelDownloadTests: XCTestCase {
    @MainActor
    func testDownloadWritesStagingAndReportsProgress() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DownloadProtocol.self]
        var progress: Double = 0
        let download = ModelDownload(destination: path, configuration: config) { progress = $0 }
        try await download.run(url: URL(string: "https://cedar.test/success")!)
        XCTAssertEqual(try Data(contentsOf: path), Data(repeating: 42, count: 1_048_576))
        XCTAssertGreaterThan(progress, 0)
    }

    @MainActor
    func testHTTPFailureDoesNotInstallStaging() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DownloadProtocol.self]
        let download = ModelDownload(destination: path, configuration: config) { _ in }
        do {
            try await download.run(url: URL(string: "https://cedar.test/fail")!)
            XCTFail("HTTP errors must fail")
        } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: path.path)) }
    }

    @MainActor
    func testCancellationFinishesWithoutLeavingStaging() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DownloadProtocol.self]
        let download = ModelDownload(destination: path, configuration: config) { _ in }
        let operation = Task { try await download.run(url: URL(string: "https://cedar.test/wait")!) }
        try await Task.sleep(for: .milliseconds(50))
        operation.cancel()
        do { try await operation.value; XCTFail("Cancelled download must fail") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: path.path)) }
    }
}
