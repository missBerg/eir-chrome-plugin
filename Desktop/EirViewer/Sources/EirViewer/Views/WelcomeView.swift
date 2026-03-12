import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var profileStore: ProfileStore
    @State private var isDragging = false
    @State private var showingAddPerson = false
    @State private var pendingFileURL: URL?

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            AppColors.pageGlow.ignoresSafeArea()
            AppColors.auraSubtle
                .opacity(0.55)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    hero
                    importCard
                    trustCard

                    if let error = documentVM.errorMessage ?? profileStore.errorMessage {
                        Text(error)
                            .foregroundColor(AppColors.danger)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Text("Supports EIR format v1.0 (.eir, .yaml)")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 34)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(isPresented: $showingAddPerson) {
            AddPersonSheet(initialURL: pendingFileURL)
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppColors.aura)
                    .frame(width: 116, height: 116)
                    .shadow(color: AppColors.shadowStrong, radius: 20, y: 12)

                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    .frame(width: 124, height: 124)

                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(spacing: 10) {
                Text("Eir")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.text)

                Text("A calmer desktop for importing, reading, and understanding your Swedish health records.")
                    .font(.title3)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }
        }
        .padding(.top, 10)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open a record source")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppColors.text)
                    Text("Start with your own export, or use the bundled sample profile to review the full app without external credentials.")
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                reviewBadge
            }

            HStack(alignment: .top, spacing: 18) {
                importDropZone
                VStack(spacing: 14) {
                    actionCard(
                        title: "Open EIR or YAML file",
                        subtitle: "Use a local export from 1177 or another EIR-compatible source.",
                        systemImage: "folder.badge.plus",
                        tint: AppColors.primary
                    ) {
                        documentVM.openFilePicker { url in
                            pendingFileURL = url
                            showingAddPerson = true
                        }
                    }

                    actionCard(
                        title: "Try sample data",
                        subtitle: "Loads a complete demo journal so every screen can be reviewed immediately.",
                        systemImage: "sparkles.rectangle.stack.fill",
                        tint: AppColors.aiStrong
                    ) {
                        loadSampleData()
                    }
                }
                .frame(maxWidth: 320)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColors.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(color: AppColors.shadow, radius: 20, y: 12)
    }

    private var importDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isDragging ? AppColors.primaryStrong : AppColors.border,
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isDragging ? AppColors.primarySoft : AppColors.backgroundMuted)
                )

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppColors.primarySoft)
                        .frame(width: 64, height: 64)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(AppColors.primaryStrong)
                }

                VStack(spacing: 6) {
                    Text("Drop your file here")
                        .font(.headline)
                        .foregroundColor(AppColors.text)
                    Text("Drag in an `.eir`, `.yaml`, or `.yml` export to create a profile.")
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .frame(minHeight: 260)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
    }

    private var trustCard: some View {
        HStack(spacing: 18) {
            trustPill(
                icon: "server.rack",
                title: "Stockholm hosted trial",
                body: "Berget AI Trial is available in chat without bringing your own key."
            )
            trustPill(
                icon: "lock.shield",
                title: "Zero Eir retention",
                body: "Hosted AI requests are routed through Eir in Stockholm with zero Eir-side retention."
            )
            trustPill(
                icon: "iphone.gen3.radiowaves.left.and.right",
                title: "Mac to iPhone transfer",
                body: "Share an EIR file locally over Bonjour by showing a QR code to the iPhone app."
            )
        }
    }

    private var reviewBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
            Text("Review-ready demo")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundColor(AppColors.primaryStrong)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.primarySoft)
        .clipShape(Capsule())
    }

    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(AppColors.text)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.backgroundMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func trustPill(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(AppColors.aiStrong)
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.text)
            Text(body)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func loadSampleData() {
        guard let bundleURL = Bundle.main.url(forResource: "sample-data", withExtension: "yaml") else {
            profileStore.errorMessage = "Sample data not found in app bundle"
            return
        }

        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EirViewer/profiles")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let destURL = docs.appendingPathComponent("sample-data.yaml")

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destURL)
            if let profile = profileStore.addProfile(displayName: "Anna Lindgren", fileURL: destURL) {
                profileStore.selectProfile(profile.id)
            }
        } catch {
            profileStore.errorMessage = "Failed to copy sample data: \(error.localizedDescription)"
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                return
            }

            let ext = url.pathExtension.lowercased()
            guard ext == "eir" || ext == "yaml" || ext == "yml" else { return }

            Task { @MainActor in
                pendingFileURL = url
                showingAddPerson = true
            }
        }

        return true
    }
}
