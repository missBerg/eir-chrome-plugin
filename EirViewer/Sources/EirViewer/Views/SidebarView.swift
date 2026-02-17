import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @Binding var selectedTab: NavTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let patient = documentVM.document?.metadata.patient {
                VStack(alignment: .leading, spacing: 4) {
                    Text(patient.name ?? "Unknown Patient")
                        .font(.headline)
                        .foregroundColor(.white)

                    if let dob = patient.birthDate {
                        Text("Born: \(dob)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    if let pnr = patient.personalNumber {
                        Text(pnr)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.text)
            }

            List(selection: $selectedTab) {
                ForEach(NavTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)

            Spacer()

            if let info = documentVM.document?.metadata.exportInfo {
                VStack(alignment: .leading, spacing: 4) {
                    if let total = info.totalEntries {
                        Label("\(total) entries", systemImage: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    if let range = info.dateRange {
                        Label(
                            "\(range.start ?? "?") – \(range.end ?? "?")",
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding()
            }

            Divider()

            Button {
                documentVM.openFilePicker()
            } label: {
                Label("Open Another File...", systemImage: "folder")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 200)
    }
}
