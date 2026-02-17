import Foundation
import MapKit
import SwiftUI
import CoreLocation

// MARK: - Clinic Type

enum ClinicType: String, CaseIterable, Identifiable {
    case vardcentral = "Vårdcentral"
    case tandvard = "Tandvård"
    case psykiatri = "Psykiatri"
    case barn = "Barn/BVC"
    case rehab = "Rehab/Fysio"
    case ogon = "Ögon"
    case hud = "Hud"
    case ortoped = "Ortoped"
    case kirurgi = "Kirurgi"
    case gynekolog = "Gynekolog"
    case akut = "Akut/Jour"
    case labb = "Labb/Röntgen"
    case vaccination = "Vaccination"
    case ungdom = "Ungdom"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .vardcentral: return AppColors.primary
        case .tandvard: return AppColors.teal
        case .psykiatri: return AppColors.purple
        case .barn: return AppColors.green
        case .rehab: return AppColors.orange
        case .ogon: return AppColors.blue
        case .hud: return Color(hex: "EC4899")
        case .ortoped: return Color(hex: "8B5CF6")
        case .kirurgi: return AppColors.red
        case .gynekolog: return Color(hex: "EC4899")
        case .akut: return AppColors.red
        case .labb: return AppColors.blue
        case .vaccination: return AppColors.green
        case .ungdom: return AppColors.orange
        }
    }

    /// Keywords to match in clinic name (case-insensitive)
    var keywords: [String] {
        switch self {
        case .vardcentral: return ["vårdcentral", "hälsocentral", "husläkar"]
        case .tandvard: return ["tandvård", "folktandvård", "tandläkar", "tandhygien"]
        case .psykiatri: return ["psykiatri", "psykolog", "psykoterapi"]
        case .barn: return ["barnmorske", "bvc", "barnavårdscentral", "barnmedicin", "barnklinik"]
        case .rehab: return ["rehabilitering", "fysioterapi", "sjukgymnast", "arbetsterapi"]
        case .ogon: return ["ögon"]
        case .hud: return ["hud", "dermatolog"]
        case .ortoped: return ["ortoped"]
        case .kirurgi: return ["kirurg"]
        case .gynekolog: return ["gynekolog", "kvinnoklinik"]
        case .akut: return ["akutmottagning", "jourmottagning", "närakut"]
        case .labb: return ["lab ", "labb", "röntgen", "mammografi"]
        case .vaccination: return ["vaccination"]
        case .ungdom: return ["ungdomsmottagning"]
        }
    }

    static func categorize(_ name: String) -> ClinicType? {
        let lowered = name.lowercased()
        for type in allCases {
            for keyword in type.keywords {
                if lowered.contains(keyword) {
                    return type
                }
            }
        }
        return nil
    }
}

// MARK: - Clinic Store

@MainActor
final class ClinicStore: ObservableObject {
    @Published var allClinics: [Clinic] = []
    @Published var searchText: String = ""
    @Published var filterMVK: Bool = false
    @Published var filterVideoChat: Bool = false
    @Published var filterFlu: Bool = false
    @Published var filterCovid: Bool = false
    @Published var selectedType: ClinicType? = nil
    @Published var mapRegion: MKCoordinateRegion = .sweden
    @Published var selectedClinicID: String?
    @Published var isLoaded: Bool = false

    /// Maximum latitude span to show pins (~15 km)
    private let zoomThreshold: Double = 0.15
    /// Hard cap on map annotations to keep rendering fast
    private let maxVisiblePins: Int = 150

    var isZoomedIn: Bool {
        mapRegion.span.latitudeDelta < zoomThreshold
    }

    /// Counts per clinic type for badge display
    var typeCounts: [ClinicType: Int] {
        var counts: [ClinicType: Int] = [:]
        for type in ClinicType.allCases {
            counts[type] = 0
        }
        for clinic in allClinics {
            if let type = ClinicType.categorize(clinic.name) {
                counts[type, default: 0] += 1
            }
        }
        return counts
    }

    var filteredClinics: [Clinic] {
        allClinics.filter { clinic in
            let matchesSearch = searchText.isEmpty
                || clinic.name.localizedCaseInsensitiveContains(searchText)
                || (clinic.address?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesMVK = !filterMVK || clinic.hasMvkServices
            let matchesVideo = !filterVideoChat || clinic.videoOrChat
            let matchesFlu = !filterFlu || clinic.vaccinatesForFlu
            let matchesCovid = !filterCovid || clinic.vaccinatesForCovid19
            let matchesType: Bool
            if let selected = selectedType {
                matchesType = ClinicType.categorize(clinic.name) == selected
            } else {
                matchesType = true
            }
            return matchesSearch && matchesMVK && matchesVideo && matchesFlu && matchesCovid && matchesType
        }
    }

    var visibleClinics: [Clinic] {
        guard isZoomedIn else { return [] }
        let minLat = mapRegion.center.latitude - mapRegion.span.latitudeDelta / 2
        let maxLat = mapRegion.center.latitude + mapRegion.span.latitudeDelta / 2
        let minLng = mapRegion.center.longitude - mapRegion.span.longitudeDelta / 2
        let maxLng = mapRegion.center.longitude + mapRegion.span.longitudeDelta / 2
        let centerLoc = CLLocation(latitude: mapRegion.center.latitude, longitude: mapRegion.center.longitude)
        let inRegion = filteredClinics.filter { clinic in
            guard let coord = clinic.coordinate else { return false }
            return coord.latitude >= minLat && coord.latitude <= maxLat
                && coord.longitude >= minLng && coord.longitude <= maxLng
        }
        if inRegion.count <= maxVisiblePins { return inRegion }
        return Array(inRegion.sorted { a, b in
            let distA = a.distance(from: centerLoc) ?? .greatestFiniteMagnitude
            let distB = b.distance(from: centerLoc) ?? .greatestFiniteMagnitude
            return distA < distB
        }.prefix(maxVisiblePins))
    }

    var selectedClinic: Clinic? {
        guard let id = selectedClinicID else { return nil }
        return allClinics.first { $0.id == id }
    }

    func loadClinics() {
        guard !isLoaded else { return }
        guard let url = Bundle.module.url(forResource: "healthcare-clinics", withExtension: "json") else {
            print("Could not find healthcare-clinics.json in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            allClinics = try JSONDecoder().decode([Clinic].self, from: data)
            isLoaded = true
        } catch {
            print("Failed to load clinics: \(error)")
        }
    }

    func centerOnClinic(_ clinic: Clinic) {
        guard let coord = clinic.coordinate else { return }
        selectedClinicID = clinic.id
        mapRegion = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }
}

// MARK: - Clinic distance helper

extension Clinic {
    func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let coord = coordinate else { return nil }
        return location.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
    }
}

extension MKCoordinateRegion {
    static let sweden = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 62.0, longitude: 16.0),
        span: MKCoordinateSpan(latitudeDelta: 15.0, longitudeDelta: 12.0)
    )
}
