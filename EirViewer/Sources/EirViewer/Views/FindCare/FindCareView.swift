import SwiftUI

enum FindCareMode: String, CaseIterable {
    case map = "Map"
    case list = "List"
}

struct FindCareView: View {
    @EnvironmentObject var clinicStore: ClinicStore

    @State private var viewMode: FindCareMode = .map

    var body: some View {
        HSplitView {
            // Left: filter bar + content
            VStack(spacing: 0) {
                FindCareFilterBar(viewMode: $viewMode)

                Divider()

                switch viewMode {
                case .map:
                    ClinicMapView()
                case .list:
                    ClinicListView()
                }
            }
            .frame(minWidth: 400, idealWidth: 500)

            // Right: detail panel
            if let clinic = clinicStore.selectedClinic {
                ClinicDetailView(clinic: clinic)
                    .frame(minWidth: 320, idealWidth: 380)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textSecondary.opacity(0.5))
                    Text("Select a clinic to view details")
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.background)
            }
        }
        .onAppear {
            clinicStore.loadClinics()
        }
    }
}

// MARK: - Filter Bar

struct FindCareFilterBar: View {
    @EnvironmentObject var clinicStore: ClinicStore
    @Binding var viewMode: FindCareMode

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppColors.textSecondary)
                    TextField("Search clinics...", text: $clinicStore.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(AppColors.divider)
                .cornerRadius(8)

                // Map/List toggle
                Picker("", selection: $viewMode) {
                    ForEach(FindCareMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            // Clinic type labels
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ClinicType.allCases) { type in
                        let count = clinicStore.typeCounts[type] ?? 0
                        if count > 0 {
                            TypeChip(
                                type: type,
                                count: count,
                                isActive: clinicStore.selectedType == type
                            ) {
                                if clinicStore.selectedType == type {
                                    clinicStore.selectedType = nil
                                } else {
                                    clinicStore.selectedType = type
                                }
                            }
                        }
                    }
                }
            }

            // Service filter chips + result count
            HStack(spacing: 8) {
                FilterChip(label: "E-services", isActive: $clinicStore.filterMVK)
                FilterChip(label: "Video/Chat", isActive: $clinicStore.filterVideoChat)
                FilterChip(label: "Flu", isActive: $clinicStore.filterFlu)
                FilterChip(label: "COVID", isActive: $clinicStore.filterCovid)

                Spacer()

                Text("\(clinicStore.filteredClinics.count) clinics")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(12)
        .background(AppColors.card)
    }
}

// MARK: - Type Chip

struct TypeChip: View {
    let type: ClinicType
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(type.rawValue)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(isActive ? .white.opacity(0.8) : type.color.opacity(0.7))
            }
            .foregroundColor(isActive ? .white : type.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? type.color : type.color.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    @Binding var isActive: Bool

    var body: some View {
        Button {
            isActive.toggle()
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? .white : AppColors.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? AppColors.primary : AppColors.divider)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
