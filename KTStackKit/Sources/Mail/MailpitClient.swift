import Foundation

public struct MailpitClient: Sendable {
    public struct APIError: LocalizedError {
        public let status: Int
        public var errorDescription: String? {
            "Mailpit API returned HTTP \(status)."
        }
    }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = MailpitController.apiBaseURL) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        session = URLSession(configuration: cfg)
    }

    public func list(limit: Int = 200) async throws -> MailListResponse {
        try await get("/messages?limit=\(limit)")
    }

    public func detail(id: String) async throws -> MailDetail {
        try await get("/message/\(id)")
    }

    public func rawURL(id: String) -> URL {
        baseURL.appendingPathComponent("message/\(id)/raw")
    }

    public func delete(ids: [String]) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("messages"))
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["IDs": ids])
        _ = try await send(req)
    }

    // Mailpit deletes every message when IDs is empty, so this posts an empty array on purpose;
    // an "empty guard" in delete() would turn Clear All into a no-op.
    public func deleteAll() async throws {
        try await delete(ids: [])
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(URLRequest(url: url(path)))
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError(status: http.statusCode)
        }
        return data
    }

    private func url(_ path: String) -> URL {
        URL(string: baseURL.absoluteString + path) ?? baseURL
    }
}
