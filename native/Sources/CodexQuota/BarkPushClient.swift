import Foundation
import QuotaCore

@MainActor protocol BarkPushTransport: AnyObject { func send(_ payload: Data) async -> BarkResponse }
private final class BarkRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class BarkPushClient: BarkPushTransport {
    private let delegate = BarkRedirectBlocker()
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration.copy() as! URLSessionConfiguration }
    func send(_ payload: Data) async -> BarkResponse {
        guard payload.count <= 3000 else { return .rejected }
        let config = configuration.copy() as! URLSessionConfiguration
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 10
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.day.app/push")!, timeoutInterval: 10)
        request.httpMethod = "POST"; request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, response.url == request.url, response.expectedContentLength <= 65536 else { return .rejected }
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < 65536 else { return .rejected }; body.append(byte)
            }
            return BarkResponse.classify(statusCode: http.statusCode, body: body)
        } catch { return .unknown }
    }
}
