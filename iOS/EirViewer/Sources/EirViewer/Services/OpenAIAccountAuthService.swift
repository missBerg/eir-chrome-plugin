import Foundation

struct OpenAIDeviceCode: Codable, Equatable {
    let verificationURL: String
    let userCode: String
    let deviceAuthID: String
    let interval: UInt64
    let createdAt: Date

    var expiresAt: Date {
        createdAt.addingTimeInterval(15 * 60)
    }
}

struct OpenAIAccountSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let accountID: String?
    let email: String?
    let planType: String?
    let accessTokenExpiresAt: Date?
    let updatedAt: Date
    let idToken: String?
    let exchangedAPIKey: String?
}

enum OpenAIAccountAuthError: LocalizedError {
    case invalidResponse
    case missingAuthorizationCode
    case timedOut
    case missingCredential
    case missingAccountID
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The OpenAI account response was not in a readable format."
        case .missingAuthorizationCode:
            return "The OpenAI device flow completed without an authorization code."
        case .timedOut:
            return "OpenAI sign-in timed out. Try again."
        case .missingCredential:
            return "OpenAI account sign-in did not return a usable credential."
        case .missingAccountID:
            return "OpenAI account sign-in did not include a ChatGPT account ID."
        case .requestFailed(let message):
            return message
        }
    }
}

actor OpenAIAccountAuthService {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let issuer = URL(string: "https://auth.openai.com")!
    static let platformAPIBaseURL = URL(string: "https://api.openai.com/v1")!

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func requestDeviceCode() async throws -> OpenAIDeviceCode {
        struct RequestBody: Encodable {
            let client_id: String
        }

        struct ResponseBody: Decodable {
            let device_auth_id: String
            let user_code: String
            let interval: FlexibleUInt64
        }

        let url = Self.issuer
            .appending(path: "api")
            .appending(path: "accounts")
            .appending(path: "deviceauth")
            .appending(path: "usercode")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(client_id: Self.clientID))

        let (data, response) = try await urlSession.data(for: request)
        let http = try Self.httpResponse(from: response)
        guard http.statusCode == 200 else {
            throw OpenAIAccountAuthError.requestFailed(Self.responseErrorMessage(data: data, statusCode: http.statusCode))
        }

        let payload = try JSONDecoder().decode(ResponseBody.self, from: data)
        return OpenAIDeviceCode(
            verificationURL: Self.issuer.appending(path: "codex").appending(path: "device").absoluteString,
            userCode: payload.user_code,
            deviceAuthID: payload.device_auth_id,
            interval: max(payload.interval.value, 2),
            createdAt: Date()
        )
    }

    func completeDeviceCodeLogin(deviceCode: OpenAIDeviceCode) async throws -> OpenAIAccountSession {
        let authCode = try await pollForAuthorizationCode(deviceCode: deviceCode)
        let tokenBundle = try await exchangeAuthorizationCode(
            authorizationCode: authCode.authorizationCode,
            codeVerifier: authCode.codeVerifier
        )
        return try await buildSession(
            idToken: tokenBundle.idToken,
            accessToken: tokenBundle.accessToken,
            refreshToken: tokenBundle.refreshToken
        )
    }

    func usableSession(from session: OpenAIAccountSession) async throws -> OpenAIAccountSession {
        let refreshed: OpenAIAccountSession
        if let expiry = session.accessTokenExpiresAt,
           expiry <= Date().addingTimeInterval(5 * 60) {
            refreshed = try await refresh(session: session)
        } else {
            refreshed = session
        }

        guard let accountID = refreshed.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountID.isEmpty else {
            throw OpenAIAccountAuthError.missingAccountID
        }

        return refreshed
    }

    func fetchAvailableModels(accessToken: String) async throws -> [String] {
        struct ModelsResponse: Decodable {
            struct Model: Decodable {
                let id: String
            }

            let data: [Model]
        }

        let url = Self.platformAPIBaseURL.appending(path: "models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        let http = try Self.httpResponse(from: response)
        guard 200..<300 ~= http.statusCode else {
            throw OpenAIAccountAuthError.requestFailed(Self.responseErrorMessage(data: data, statusCode: http.statusCode))
        }

        let payload = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let filtered = payload.data
            .map(\.id)
            .filter(Self.isLikelyChatModel(_:))
            .sorted(by: Self.sortModels)

        return filtered.isEmpty
            ? payload.data.map(\.id).sorted()
            : filtered
    }

    private func refresh(session: OpenAIAccountSession) async throws -> OpenAIAccountSession {
        struct RefreshRequest: Encodable {
            let client_id: String
            let grant_type: String
            let refresh_token: String
        }

        struct RefreshResponse: Decodable {
            let id_token: String?
            let access_token: String?
            let refresh_token: String?
        }

        let url = Self.issuer.appending(path: "oauth").appending(path: "token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RefreshRequest(
                client_id: Self.clientID,
                grant_type: "refresh_token",
                refresh_token: session.refreshToken
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        let http = try Self.httpResponse(from: response)
        guard 200..<300 ~= http.statusCode else {
            throw OpenAIAccountAuthError.requestFailed(Self.responseErrorMessage(data: data, statusCode: http.statusCode))
        }

        let payload = try JSONDecoder().decode(RefreshResponse.self, from: data)
        return try await buildSession(
            idToken: payload.id_token ?? session.idToken,
            accessToken: payload.access_token ?? session.accessToken,
            refreshToken: payload.refresh_token ?? session.refreshToken
        )
    }

    private func buildSession(
        idToken: String?,
        accessToken: String,
        refreshToken: String
    ) async throws -> OpenAIAccountSession {
        let idClaims = idToken.map(Self.jwtClaims(from:)) ?? [:]
        let idAuthClaims = (idClaims["https://api.openai.com/auth"] as? [String: Any]) ?? [:]
        let accessClaims = Self.jwtClaims(from: accessToken)
        let accessAuthClaims = (accessClaims["https://api.openai.com/auth"] as? [String: Any]) ?? [:]
        let accountID = (accessAuthClaims["chatgpt_account_id"] as? String)
            ?? (accessAuthClaims["account_id"] as? String)
            ?? (idAuthClaims["chatgpt_account_id"] as? String)
            ?? (idAuthClaims["account_id"] as? String)

        guard let accountID, !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIAccountAuthError.missingAccountID
        }

        return OpenAIAccountSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountID: accountID,
            email: (idClaims["email"] as? String) ?? (accessClaims["email"] as? String),
            planType: (accessAuthClaims["chatgpt_plan_type"] as? String) ?? (idAuthClaims["chatgpt_plan_type"] as? String),
            accessTokenExpiresAt: Self.jwtExpiry(from: accessToken),
            updatedAt: Date(),
            idToken: idToken,
            exchangedAPIKey: nil
        )
    }

    private func pollForAuthorizationCode(deviceCode: OpenAIDeviceCode) async throws -> AuthorizationCodeResponse {
        let url = Self.issuer
            .appending(path: "api")
            .appending(path: "accounts")
            .appending(path: "deviceauth")
            .appending(path: "token")

        while Date() < deviceCode.expiresAt {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(DeviceTokenPollRequest(
                device_auth_id: deviceCode.deviceAuthID,
                user_code: deviceCode.userCode
            ))

            let (data, response) = try await urlSession.data(for: request)
            let http = try Self.httpResponse(from: response)

            if 200..<300 ~= http.statusCode {
                let payload = try JSONDecoder().decode(AuthorizationCodeResponse.self, from: data)
                guard !payload.authorizationCode.isEmpty else {
                    throw OpenAIAccountAuthError.missingAuthorizationCode
                }
                return payload
            }

            if http.statusCode == 403 || http.statusCode == 404 {
                try await Task.sleep(nanoseconds: deviceCode.interval * 1_000_000_000)
                continue
            }

            throw OpenAIAccountAuthError.requestFailed(Self.responseErrorMessage(data: data, statusCode: http.statusCode))
        }

        throw OpenAIAccountAuthError.timedOut
    }

    private func exchangeAuthorizationCode(
        authorizationCode: String,
        codeVerifier: String
    ) async throws -> TokenBundle {
        let redirectURI = Self.issuer.appending(path: "deviceauth").appending(path: "callback").absoluteString
        let url = Self.issuer.appending(path: "oauth").appending(path: "token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncodedData([
            "grant_type": "authorization_code",
            "code": authorizationCode,
            "redirect_uri": redirectURI,
            "client_id": Self.clientID,
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await urlSession.data(for: request)
        let http = try Self.httpResponse(from: response)
        guard 200..<300 ~= http.statusCode else {
            throw OpenAIAccountAuthError.requestFailed(Self.responseErrorMessage(data: data, statusCode: http.statusCode))
        }

        return try JSONDecoder().decode(TokenBundle.self, from: data)
    }

    private static func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIAccountAuthError.invalidResponse
        }
        return http
    }

    private static func responseErrorMessage(data: Data, statusCode: Int) -> String {
        if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorDescription = decoded["error_description"] as? String, !errorDescription.isEmpty {
                return errorDescription
            }
            if let error = decoded["error"] as? String, !error.isEmpty {
                return error
            }
            if let errorObject = decoded["error"] as? [String: Any],
               let message = errorObject["message"] as? String,
               !message.isEmpty {
                return message
            }
        }

        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body, !body.isEmpty {
            return body
        }
        return "OpenAI sign-in failed with status \(statusCode)."
    }

    private static func formEncodedData(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func jwtExpiry(from token: String) -> Date? {
        guard let claims = decodedJWTPayload(from: token),
              let expiry = claims["exp"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: expiry)
    }

    private static func jwtClaims(from token: String) -> [String: Any] {
        decodedJWTPayload(from: token) ?? [:]
    }

    private static func decodedJWTPayload(from token: String) -> [String: Any]? {
        let segments = token.components(separatedBy: ".")
        guard segments.count >= 2 else { return nil }
        let payloadSegment = segments[1]
        let base64 = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64 + padding),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func isLikelyChatModel(_ id: String) -> Bool {
        let lowercased = id.lowercased()
        let excludedFragments = [
            "audio",
            "transcribe",
            "tts",
            "image",
            "embedding",
            "moderation",
            "whisper",
            "dall",
            "sora",
            "search",
            "realtime",
        ]
        if excludedFragments.contains(where: { lowercased.contains($0) }) {
            return false
        }

        return lowercased.hasPrefix("gpt")
            || lowercased.hasPrefix("o1")
            || lowercased.hasPrefix("o3")
            || lowercased.hasPrefix("o4")
            || lowercased.hasPrefix("chatgpt")
    }

    private static func sortModels(lhs: String, rhs: String) -> Bool {
        let lhsScore = modelSortScore(lhs)
        let rhsScore = modelSortScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private static func modelSortScore(_ id: String) -> Int {
        let lowercased = id.lowercased()
        if lowercased == "gpt-5.4" { return 1000 }
        if lowercased == "gpt-5.2" { return 990 }
        if lowercased == "gpt-5.1" { return 980 }
        if lowercased == "gpt-5" { return 970 }
        if lowercased == "gpt-4.1" { return 960 }
        if lowercased == "gpt-4o" { return 950 }
        if lowercased.hasPrefix("gpt-5") { return 900 }
        if lowercased.hasPrefix("o4") { return 850 }
        if lowercased.hasPrefix("o3") { return 840 }
        if lowercased.hasPrefix("o1") { return 830 }
        if lowercased.hasPrefix("gpt-4") { return 800 }
        if lowercased.hasPrefix("chatgpt") { return 780 }
        return 0
    }
}

private struct DeviceTokenPollRequest: Encodable {
    let device_auth_id: String
    let user_code: String
}

private struct AuthorizationCodeResponse: Decodable {
    let authorizationCode: String
    let codeChallenge: String
    let codeVerifier: String

    private enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeChallenge = "code_challenge"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenBundle: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct FlexibleUInt64: Decodable {
    let value: UInt64

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(UInt64.self) {
            value = intValue
            return
        }
        let stringValue = try container.decode(String.self)
        guard let parsed = UInt64(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected integer interval.")
        }
        value = parsed
    }
}
