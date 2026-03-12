import SwiftUI
import UniformTypeIdentifiers
import HealthKit

struct WelcomeView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var extractor: HealthDataExtractor
    @State private var showFilePicker = false
    @State private var showQRScanner = false
    @State private var showHealthKitImport = false
    @State private var show1177Browser = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(AppColors.aura)
                            .frame(width: 108, height: 108)
                            .shadow(color: AppColors.shadowStrong, radius: 18, y: 10)

                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            .frame(width: 116, height: 116)

                        Image("EirRune")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                    }

                    VStack(spacing: 10) {
                        Text("Eir")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(AppColors.text)

                        Text("A calmer way to collect, read, and understand your health records.")
                            .font(.title3)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Bring your records into one place")
                        .font(.headline)
                        .foregroundColor(AppColors.text)

                    actionButton(
                        title: "Hämta journal från 1177",
                        subtitle: "Secure import from Swedish healthcare records",
                        systemImage: "cross.case.fill",
                        tint: AppColors.primaryStrong
                    ) {
                        show1177Browser = true
                    }

                    actionButton(
                        title: "Import from Apple Health",
                        subtitle: "Activity, vitals, and workouts with structured summaries",
                        systemImage: "heart.fill",
                        tint: AppColors.ai,
                        isVisible: HKHealthStore.isHealthDataAvailable()
                    ) {
                        showHealthKitImport = true
                    }

                    actionButton(
                        title: "Choose EIR or YAML File",
                        subtitle: "Open an existing export from Files",
                        systemImage: "folder.fill",
                        tint: AppColors.info
                    ) {
                        showFilePicker = true
                    }

                    actionButton(
                        title: "Scan from Mac",
                        subtitle: "Move records directly from your desktop",
                        systemImage: "qrcode.viewfinder",
                        tint: AppColors.primary
                    ) {
                        showQRScanner = true
                    }
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppColors.backgroundElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .shadow(color: AppColors.shadow, radius: 18, y: 10)
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button {
                        loadSampleData()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                            Text("Try Sample Data")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundColor(AppColors.primaryStrong)
                    }

                    if let error = profileStore.errorMessage {
                        Text(error)
                            .foregroundColor(AppColors.danger)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                Text("Supports EIR format v1.0 (.eir, .yaml)")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 16)
            }
            .padding(.bottom, 24)
        }
        .background {
            ZStack {
                AppColors.background.ignoresSafeArea()
                AppColors.pageGlow
                    .ignoresSafeArea()
                AppColors.auraSubtle
                    .opacity(0.45)
                    .ignoresSafeArea()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "eir") ?? .yaml,
                .yaml,
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let profile = profileStore.addProfile(displayName: "", fileURL: url) {
                    profileStore.selectProfile(profile.id)
                }
            case .failure(let error):
                profileStore.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView()
        }
        .sheet(isPresented: $showHealthKitImport) {
            HealthKitImportView()
                .environmentObject(profileStore)
        }
        .sheet(isPresented: $show1177Browser) {
            NavigationStack {
                HealthDataBrowserView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Stäng") { show1177Browser = false }
                        }
                    }
            }
            .environmentObject(profileStore)
            .environmentObject(extractor)
        }
        // Auto-dismiss sheets when a profile is loaded
        .onReceive(NotificationCenter.default.publisher(for: .profileDidLoad)) { _ in
            showQRScanner = false
            showHealthKitImport = false
            show1177Browser = false
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isVisible: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        if isVisible {
            Button(action: action) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint.opacity(0.12))
                            .frame(width: 46, height: 46)

                        Image(systemName: systemImage)
                            .font(.system(size: 20, weight: .semibold))
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
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.backgroundMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func loadSampleData() {
        // Copy bundled sample to Documents so it persists
        guard let bundleURL = Bundle.main.url(forResource: "sample-data", withExtension: "yaml") else {
            profileStore.errorMessage = "Sample data not found in app bundle"
            return
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destURL = docs.appendingPathComponent("sample-data.yaml")

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destURL)
        } catch {
            profileStore.errorMessage = "Failed to copy sample data: \(error.localizedDescription)"
            return
        }

        if let profile = profileStore.addProfile(displayName: "", fileURL: destURL) {
            profileStore.selectProfile(profile.id)
        }
    }
}
