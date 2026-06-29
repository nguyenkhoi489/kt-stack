import Foundation

public struct APIRequestSpec: Sendable {
    public var method: String
    public var url: URL
    public var headers: [(String, String)]
    public var body: Data?

    public init(method: String, url: URL, headers: [(String, String)], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct APIResponseResult: Sendable {
    public let statusCode: Int
    public let headers: [(String, String)]
    public let body: Data
    public let elapsedMs: Int
    public let contentType: String?

    public init(statusCode: Int, headers: [(String, String)], body: Data, elapsedMs: Int, contentType: String?) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.elapsedMs = elapsedMs
        self.contentType = contentType
    }
}

public struct APIRequestClient: Sendable {
    public struct RequestError: LocalizedError {
        public let message: String
        public init(message: String) {
            self.message = message
        }

        public var errorDescription: String? {
            message
        }
    }

    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: cfg)
    }

    public func send(_ spec: APIRequestSpec) async throws -> APIResponseResult {
        var request = URLRequest(url: spec.url)
        request.httpMethod = spec.method
        for (key, value) in spec.headers where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = spec.body

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            guard let http = response as? HTTPURLResponse else {
                throw RequestError(message: "The server returned a non-HTTP response.")
            }
            return APIResponseResult(
                statusCode: http.statusCode,
                headers: Self.headerPairs(http),
                body: data,
                elapsedMs: elapsed,
                contentType: http.value(forHTTPHeaderField: "Content-Type")
            )
        } catch let error as URLError {
            throw RequestError(message: Self.message(for: error))
        }
    }

    private static func headerPairs(_ http: HTTPURLResponse) -> [(String, String)] {
        http.allHeaderFields
            .compactMap { key, value in
                guard let name = key as? String else { return nil }
                return (name, String(describing: value))
            }
            .sorted { $0.0.lowercased() < $1.0.lowercased() }
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            "Request timed out. Increase the timeout or check the site is responding."
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
            "Could not reach the site. Check that the service is running."
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            "TLS handshake failed. Ensure the local CA is trusted for this site."
        default:
            error.localizedDescription
        }
    }
}
