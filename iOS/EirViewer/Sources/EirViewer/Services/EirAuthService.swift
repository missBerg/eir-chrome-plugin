import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class EirAuthService: NSObject, ObservableObject {
    static let shared = EirAuthService()

    @Published private(set) var user: User?
    @Published private(set) var isSigningIn: Bool = false
    @Published private(set) var lastError: String?

    private var currentNonce: String?
    private var appleContinuation: CheckedContinuation<Void, Error>?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    private override init() {
        super.init()
        configureFirebaseIfNeeded()
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Firebase bootstrap

    private func configureFirebaseIfNeeded() {
        guard FirebaseApp.app() == nil else { return }
        #if DEBUG
        let plistName = "GoogleService-Info-dev"
        #else
        let plistName = "GoogleService-Info-prod"
        #endif
        guard
            let path = Bundle.main.path(forResource: plistName, ofType: "plist"),
            let options = FirebaseOptions(contentsOfFile: path)
        else {
            assertionFailure("Missing \(plistName).plist in bundle")
            return
        }
        FirebaseApp.configure(options: options)
    }

    // MARK: - Public API

    var isSignedIn: Bool { user != nil }

    /// Returns a fresh Firebase ID token (handles refresh internally).
    /// Send as `Authorization: Bearer <token>` to the Eir backend.
    func currentIDToken(forceRefresh: Bool = false) async throws -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDTokenResult(forcingRefresh: forceRefresh).token
    }

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Google sign-in

    func signInWithGoogle(presenting: UIViewController) async throws {
        guard let firebaseApp = FirebaseApp.app(), let clientID = firebaseApp.options.clientID else {
            throw EirAuthError.missingFirebaseConfig
        }
        isSigningIn = true
        defer { isSigningIn = false }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        guard let idToken = result.user.idToken?.tokenString else {
            throw EirAuthError.googleMissingIDToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        _ = try await Auth.auth().signIn(with: credential)
    }

    // MARK: - Apple sign-in

    /// Configure an `ASAuthorizationAppleIDRequest` (called by the SignInWithAppleButton).
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Handle the result from SignInWithAppleButton.
    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let authorization = try result.get()
            try await completeAppleSignIn(authorization: authorization)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func completeAppleSignIn(authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw EirAuthError.appleInvalidCredential
        }
        guard let nonce = currentNonce else {
            throw EirAuthError.appleMissingNonce
        }
        guard
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            throw EirAuthError.appleMissingIDToken
        }
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        _ = try await Auth.auth().signIn(with: firebaseCredential)
        currentNonce = nil
    }

    // MARK: - Nonce helpers (Apple-required)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

enum EirAuthError: LocalizedError {
    case missingFirebaseConfig
    case googleMissingIDToken
    case appleInvalidCredential
    case appleMissingNonce
    case appleMissingIDToken

    var errorDescription: String? {
        switch self {
        case .missingFirebaseConfig: return "Firebase is not configured."
        case .googleMissingIDToken: return "Google sign-in did not return an ID token."
        case .appleInvalidCredential: return "Unexpected Apple credential type."
        case .appleMissingNonce: return "Missing nonce for Apple sign-in."
        case .appleMissingIDToken: return "Apple did not return an identity token."
        }
    }
}
