import SwiftUI
import MapKit

struct ClinicMapView: View {
    @EnvironmentObject var clinicStore: ClinicStore

    @State private var cameraPosition: MapCameraPosition = .region(.sweden)

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                ForEach(clinicStore.visibleClinics) { clinic in
                    if let coord = clinic.coordinate {
                        Annotation(clinic.name, coordinate: coord) {
                            ClinicPin(
                                isSelected: clinic.id == clinicStore.selectedClinicID,
                                color: ClinicType.categorize(clinic.name)?.color ?? AppColors.primary
                            )
                            .onTapGesture {
                                clinicStore.selectedClinicID = clinic.id
                            }
                        }
                    }
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                clinicStore.mapRegion = context.region
            }

            // Overlays
            VStack {
                Spacer()

                if !clinicStore.isZoomedIn {
                    Text("Zoom in to see clinics")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                } else {
                    let count = clinicStore.visibleClinics.count
                    if count > 0 {
                        Text("\(count) clinics in view")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 12)
                    }
                }
            }
        }
    }
}

// MARK: - Clinic Pin

private struct ClinicPin: View {
    let isSelected: Bool
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: isSelected ? 16 : 10, height: isSelected ? 16 : 10)
            .overlay(
                Circle()
                    .stroke(.white, lineWidth: isSelected ? 2.5 : 1.5)
            )
            .shadow(color: color.opacity(0.3), radius: isSelected ? 4 : 2)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
