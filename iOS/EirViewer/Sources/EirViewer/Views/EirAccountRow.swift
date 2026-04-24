import FirebaseAuth
import SwiftUI

struct EirAccountRow: View {
    @StateObject private var auth = EirAuthService.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: auth.user == nil ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill.badge.checkmark")
                .font(.title2)
                .foregroundStyle(auth.user == nil ? .secondary : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.user == nil ? "Not signed in" : "Signed in")
                    .font(.body)
                if let user = auth.user {
                    Text(user.email ?? user.uid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Sign in to use Eir's cloud assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
