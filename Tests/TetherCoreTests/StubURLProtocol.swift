import Foundation

/// Canned HTTP responses keyed by full URL; use a unique URL per test.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response { var status: Int; var body: Data; var headers: [String: String] = [:] }
    nonisolated(unsafe) private static var responses: [URL: Response] = [:]
    private static let lock = NSLock()

    static func stub(_ url: URL, _ response: Response) { lock.withLock { responses[url] = response } }
    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let r = request.url.flatMap { url in Self.lock.withLock { Self.responses[url] } } ?? Response(status: 404, body: Data())
        let http = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: nil, headerFields: r.headers)!
        if (300...399).contains(r.status), let location = r.headers["Location"].flatMap(URL.init(string:)) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: http)
            // If the task delegate declines the redirect, the 3xx itself is the final response.
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
