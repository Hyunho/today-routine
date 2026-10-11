import Foundation

protocol FeedFetching: Sendable { func fetch(_ url: URL) async throws -> ParsedFeed }
struct FeedClient: FeedFetching, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration }
    func fetch(_ url: URL) async throws -> ParsedFeed {
        guard url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else {
            throw InboxError.invalid("HTTPS 피드 주소를 입력해 주세요.")
        }
        let download = FeedDownload()
        let data = try await download.load(url, configuration: configuration)
        return try await Task.detached(priority: .utility) { try FeedParser.parse(data, baseURL: url) }.value
    }
}
final class FeedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var cancelled = false
    private let limit = 5 * 1024 * 1024
    func load(_ url: URL, configuration: URLSessionConfiguration) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url, timeoutInterval: 20)
                request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
                let task = session.dataTask(with: request); self.task = task
                lock.unlock(); task.resume()
            }
        } onCancel: { self.cancel() }
    }
    private func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let continuation = self.continuation; self.continuation = nil
        let session = self.session; self.session = nil; self.task = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), response.url?.scheme?.lowercased() == "https" else {
            completionHandler(.cancel); finish(.failure(InboxError.invalid("피드를 가져오지 못했습니다. 주소와 서버 응답을 확인해 주세요."))); return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(InboxError.invalid("피드가 5 MiB를 초과합니다."))); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= limit else { finish(.failure(InboxError.invalid("피드가 5 MiB를 초과합니다."))); return }
        self.data.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) } else { finish(.success(data)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme?.lowercased() == "https", request.url?.user == nil, request.url?.password == nil else {
            completionHandler(nil); finish(.failure(InboxError.invalid("안전하지 않은 주소로 이동하는 피드입니다."))); return
        }
        completionHandler(request)
    }
}
