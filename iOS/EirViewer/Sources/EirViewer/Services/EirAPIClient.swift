import Foundation

/// Thin URLSession wrapper that signs every request to the Eir backend with
/// the current Firebase ID token. Token refresh is handled by EirAuthService.
struct EirAPIClient {
    static let shared = EirAPIClient()

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = AppRuntimeContext.eirBackendURL) {
        self.session = session
        self.baseURL = baseURL
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    enum APIError: LocalizedError {
        case notAuthenticated
        case http(status: Int, body: String)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not signed in to Eir."
            case .http(let status, let body): return "HTTP \(status): \(body)"
            case .decoding(let err): return "Decode error: \(err.localizedDescription)"
            }
        }
    }

    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        guard let token = try await EirAuthService.shared.currentIDToken() else {
            throw APIError.notAuthenticated
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, body: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.http(status: http.statusCode, body: bodyString)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
