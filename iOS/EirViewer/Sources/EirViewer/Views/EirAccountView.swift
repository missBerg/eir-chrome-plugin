import AuthenticationServices
import FirebaseAuth
import SwiftUI
import UIKit

struct EirAccountView: View {
    @StateObject private var auth = EirAuthService.shared

    var body: some View {
        VStack(spacing: 24) {
            if let user = auth.user {
                signedInContent(user: user)
            } else {
                signedOutContent
            }
        }
        .padding()
    }

    @ViewBuilder
    private var signedOutContent: some View {
        VStack(spacing: 12) {
            Text("Sign in to Eir")
                .font(.title2).bold()
            Text("Connect your Eir account to send health questions to the cloud assistant.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }

        SignInWithAppleButton(
            onRequest: { request in auth.configureAppleRequest(request) },
            onCompletion: { result in
                Task { await auth.handleAppleAuthorization(result) }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        Button {
            Task { await signInGoogle() }
        } label: {
            HStack {
                Image(systemName: "globe")
                Text("Continue with Google")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn)

        if let error = auth.lastError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func signedInContent(user: User) -> some View {
        VStack(spacing: 8) {
            Text("Signed in as")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(user.email ?? user.uid)
                .font(.headline)
        }

        Button(role: .destructive) {
            auth.signOut()
        } label: {
            Text("Sign out")
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.bordered)
    }

    @MainActor
    private func signInGoogle() async {
        guard let presenter = topViewController() else { return }
        do {
            try await auth.signInWithGoogle(presenting: presenter)
        } catch {
            // Surfaced via auth.lastError via SwiftUI republish; nothing more to do here.
            print("[EirAccountView] Google sign-in failed: \(error)")
        }
    }

    private func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

