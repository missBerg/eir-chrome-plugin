import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 64))
                .foregroundColor(AppColors.primary)

            Text("Eir Viewer")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(AppColors.text)

            Text("View and explore your Swedish medical records")
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDragging ? AppColors.primary : AppColors.border,
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDragging ? AppColors.primarySoft : AppColors.card)
                    )
                    .frame(width: 400, height: 180)

                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundColor(isDragging ? AppColors.primary : AppColors.textSecondary)

                    Text("Drop your .eir or .yaml file here")
                        .font(.headline)
                        .foregroundColor(AppColors.text)

                    Text("or")
                        .foregroundColor(AppColors.textSecondary)

                    Button("Choose File...") {
                        documentVM.openFilePicker()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primary)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }

            if let error = documentVM.errorMessage {
                Text(error)
                    .foregroundColor(AppColors.red)
                    .font(.callout)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Text("Supports EIR format v1.0 (.eir, .yaml)")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(AppColors.background)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            let ext = url.pathExtension.lowercased()
            guard ext == "eir" || ext == "yaml" || ext == "yml" else { return }

            Task { @MainActor in
                documentVM.loadFile(url: url)
            }
        }
        return true
    }
}
