import SwiftUI

struct ClinicListView: View {
    @EnvironmentObject var clinicStore: ClinicStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(clinicStore.filteredClinics) { clinic in
                    ClinicCardView(
                        clinic: clinic,
                        isSelected: clinic.id == clinicStore.selectedClinicID
                    )
                    .onTapGesture {
                        clinicStore.selectedClinicID = clinic.id
                    }
                    .contentShape(Rectangle())
                }
            }
            .padding()
        }
        .background(AppColors.background)
    }
}
