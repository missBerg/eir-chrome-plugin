import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct JournalView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var profileStore: ProfileStore

    @State private var showingAddPerson = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var qrExportURL: URL?

    var body: some View {
        Group {
            if documentVM.document == nil {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textSecondary.opacity(0.5))
                    Text("No records loaded")
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(documentVM.groupedEntries, id: \.key) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    NavigationLink(value: entry.id) {
                                        EntryCardView(
                                            entry: entry,
                                            isSelected: false
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text(group.key)
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                }
                .navigationDestination(for: String.self) { entryID in
                    if let entry = documentVM.document?.entries.first(where: { $0.id == entryID }) {
                        EntryDetailView(entry: entry)
                    }
                }
            }
        }
        .navigationTitle(profileStore.selectedProfile?.displayName ?? "Journal")
        .searchable(text: $documentVM.searchText, prompt: "Search entries...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedProfileFileURL != nil {
                    Menu {
                        Button {
                            shareSelectedProfile()
                        } label: {
                            Label("Export File", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showSelectedProfileQRCode()
                        } label: {
                            Label("Show QR Code", systemImage: "qrcode")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(AppColors.primary)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Category filter
                    Menu("Category") {
                        Button("All Categories") {
                            documentVM.selectedCategory = nil
                        }
                        ForEach(documentVM.categories, id: \.self) { cat in
                            Button {
                                documentVM.selectedCategory = cat
                            } label: {
                                HStack {
                                    Text(cat)
                                    if documentVM.selectedCategory == cat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    // Provider filter
                    Menu("Provider") {
                        Button("All Providers") {
                            documentVM.selectedProvider = nil
                        }
                        ForEach(documentVM.providers, id: \.self) { prov in
                            Button {
                                documentVM.selectedProvider = prov
                            } label: {
                                HStack {
                                    Text(prov)
                                    if documentVM.selectedProvider == prov {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    if documentVM.selectedCategory != nil || documentVM.selectedProvider != nil {
                        Divider()
                        Button("Clear Filters", role: .destructive) {
                            documentVM.clearFilters()
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(
                            documentVM.selectedCategory != nil || documentVM.selectedProvider != nil
                                ? AppColors.primary
                                : AppColors.textSecondary
                        )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Person list
                    ForEach(profileStore.profiles) { profile in
                        Button {
                            profileStore.selectProfile(profile.id)
                        } label: {
                            HStack {
                                Text(profile.displayName)
                                if let count = profile.totalEntries {
                                    Text("(\(count))")
                                }
                                if profile.id == profileStore.selectedProfileID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        showingAddPerson = true
                    } label: {
                        Label("Add Person...", systemImage: "person.badge.plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                        if profileStore.profiles.count > 1 {
                            Text(profileStore.selectedProfile?.initials ?? "")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonSheet()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: shareItems)
        }
        .sheet(
            isPresented: Binding(
                get: { qrExportURL != nil },
                set: { if !$0 { qrExportURL = nil } }
            )
        ) {
            if let qrExportURL {
                FileTransferQRCodeView(fileURL: qrExportURL)
            }
        }
        .background(AppColors.background)
    }

    private var selectedProfileFileURL: URL? {
        profileStore.selectedProfile?.fileURL
    }

    private func shareSelectedProfile() {
        guard let fileURL = selectedProfileFileURL else { return }
        shareItems = [fileURL]
        showShareSheet = true
    }

    private func showSelectedProfileQRCode() {
        qrExportURL = selectedProfileFileURL
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct FileTransferQRCodeView: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss
    @StateObject private var transferServer = LocalTransferServer()
    @State private var copiedLink = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if transferServer.transferComplete {
                    completionState
                } else if transferServer.isRunning, let url = transferServer.transferURL {
                    qrState(url: url)
                } else if let error = transferServer.errorMessage {
                    errorState(message: error)
                } else {
                    ProgressView("Startar export...")
                        .tint(AppColors.primary)
                }
            }
            .padding(24)
            .navigationTitle("QR-export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stang") { dismiss() }
                }
            }
        }
        .onAppear {
            transferServer.start(fileURL: fileURL)
        }
        .onDisappear {
            transferServer.stop()
        }
    }

    private func qrState(url: String) -> some View {
        VStack(spacing: 16) {
            if let qrImage = generateQRCode(from: url) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .background(Color.white)
                    .cornerRadius(16)
            }

            Text("Skanna QR-koden for att ladda ner exportfilen.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Bada enheterna maste vara pa samma Wi-Fi.")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)

            Text(fileURL.lastPathComponent)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Button(copiedLink ? "Lank kopierad" : "Kopiera lank") {
                UIPasteboard.general.string = url
                copiedLink = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var completionState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(AppColors.green)

            Text("Nedladdning slutford")
                .font(.title3)
                .fontWeight(.bold)

            Text("Exportfilen hamtades fran den har enheten.")
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.orange)

            Text("Kunde inte starta QR-export")
                .font(.headline)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.textSecondary)

            Button("Forsok igen") {
                copiedLink = false
                transferServer.start(fileURL: fileURL)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primary)
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
