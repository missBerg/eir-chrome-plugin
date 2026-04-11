import Foundation
import HealthKit
import Yams

struct HealthKitToEirConverter {

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Convert to EirDocument

    static func convert(
        dailyStats: [(HealthDataCategory, [HealthKitService.DailyStat])],
        individualSamples: [(HealthDataCategory, [HKSample])],
        patientName: String?
    ) -> EirDocument {
        var entries: [EirEntry] = []
        var entryIndex = 0

        // Daily aggregated entries
        for (category, stats) in dailyStats {
            for stat in stats {
                let entry = makeAggregatedEntry(
                    category: category,
                    stat: stat,
                    index: &entryIndex
                )
                entries.append(entry)
            }
        }

        // Individual sample entries
        for (category, samples) in individualSamples {
            for sample in samples {
                if let entry = makeSampleEntry(
                    category: category,
                    sample: sample,
                    index: &entryIndex
                ) {
                    entries.append(entry)
                }
            }
        }

        // Sort entries by date descending
        entries.sort { ($0.date ?? "") > ($1.date ?? "") }

        let earliest = entries.last?.date
        let latest = entries.first?.date

        let metadata = EirMetadata(
            formatVersion: "1.0",
            createdAt: isoFormatter.string(from: Date()),
            source: "Apple Health",
            patient: EirPatient(
                name: patientName,
                birthDate: nil,
                personalNumber: nil
            ),
            exportInfo: EirExportInfo(
                totalEntries: entries.count,
                dateRange: EirDateRange(start: earliest, end: latest),
                healthcareProviders: ["Apple Health"]
            )
        )

        return EirDocument(metadata: metadata, entries: entries)
    }

    // MARK: - Aggregated Entry (daily summary)

    private static func makeAggregatedEntry(
        category: HealthDataCategory,
        stat: HealthKitService.DailyStat,
        index: inout Int
    ) -> EirEntry {
        index += 1
        let dateStr = dateFormatter.string(from: stat.date)
        let unit = category.unit

        let summary: String
        let details: String

        if let sum = stat.sum {
            let formatted = formatValue(sum)
            summary = "\(category.rawValue): \(formatted) \(unit)"
            details = "Daglig summa: \(formatted) \(unit)"
        } else {
            let minStr = stat.min.map { formatValue($0) } ?? "-"
            let avgStr = stat.avg.map { formatValue($0) } ?? "-"
            let maxStr = stat.max.map { formatValue($0) } ?? "-"
            summary = "\(category.rawValue): \(avgStr) \(unit) (medel)"
            details = "Min: \(minStr) \(unit)\nMedel: \(avgStr) \(unit)\nMax: \(maxStr) \(unit)"
        }

        return EirEntry(
            id: "hk-\(index)",
            date: dateStr,
            time: nil,
            category: category.eirCategory,
            type: category.rawValue,
            provider: EirProvider(name: "Apple Health", region: nil, location: nil),
            status: nil,
            responsiblePerson: nil,
            content: EirContent(summary: summary, details: details, notes: nil),
            attachments: nil,
            tags: ["apple-health", category.rawValue.lowercased()]
        )
    }

    // MARK: - Individual Sample Entry

    private static func makeSampleEntry(
        category: HealthDataCategory,
        sample: HKSample,
        index: inout Int
    ) -> EirEntry? {
        index += 1
        let dateStr = dateFormatter.string(from: sample.startDate)
        let timeStr = timeFormatter.string(from: sample.startDate)

        let summary: String
        let details: String
        var notes: [String]? = nil
        var tags = ["apple-health", category.rawValue.lowercased()]
        var provider = EirProvider(name: "Apple Health", region: nil, location: nil)
        var responsiblePerson: EirResponsiblePerson? = nil

        switch category {
        case .bloodPressure:
            guard let correlation = sample as? HKCorrelation else { return nil }
            let systolicType = HKQuantityType(.bloodPressureSystolic)
            let diastolicType = HKQuantityType(.bloodPressureDiastolic)
            let systolic = (correlation.objects(for: systolicType).first as? HKQuantitySample)?
                .quantity.doubleValue(for: .millimeterOfMercury())
            let diastolic = (correlation.objects(for: diastolicType).first as? HKQuantitySample)?
                .quantity.doubleValue(for: .millimeterOfMercury())

            let sysStr = systolic.map { formatValue($0, decimals: 0) } ?? "-"
            let diaStr = diastolic.map { formatValue($0, decimals: 0) } ?? "-"
            summary = "Blodtryck: \(sysStr)/\(diaStr) mmHg"
            details = "Systoliskt: \(sysStr) mmHg\nDiastoliskt: \(diaStr) mmHg"

        case .workouts:
            guard let workout = sample as? HKWorkout else { return nil }
            let typeStr = workoutTypeName(workout.workoutActivityType)
            let durationMin = Int(workout.duration / 60)
            let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            let calStr = calories.map { ", \(formatValue($0, decimals: 0)) kcal" } ?? ""
            summary = "\(typeStr): \(durationMin) min\(calStr)"
            details = "Typ: \(typeStr)\nTid: \(durationMin) minuter\(calories.map { "\nKalorier: \(formatValue($0, decimals: 0)) kcal" } ?? "")"

        case .clinicalNotes:
            guard let record = sample as? HKClinicalRecord else { return nil }
            let extracted: ClinicalNoteFHIRExtraction
            if let data = record.fhirResource?.data {
                extracted = ClinicalNoteFHIRExtractor.extract(
                    from: data,
                    fallbackTitle: record.displayName,
                    fallbackResourceType: record.fhirResource?.resourceType.rawValue,
                    fallbackIdentifier: record.fhirResource?.identifier
                )
            } else {
                var fallbackMetadataLines = ["Importerad från Apple Health"]
                if let resourceType = record.fhirResource?.resourceType.rawValue, !resourceType.isEmpty {
                    fallbackMetadataLines.append("FHIR-resurs: \(resourceType)")
                }
                if let identifier = record.fhirResource?.identifier, !identifier.isEmpty {
                    fallbackMetadataLines.append("FHIR-ID: \(identifier)")
                }
                extracted = ClinicalNoteFHIRExtraction(
                    summary: record.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Klinisk anteckning"
                        : record.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    noteBlocks: [],
                    metadataLines: fallbackMetadataLines,
                    tags: ["clinical-note"]
                )
            }
            summary = extracted.summary
            details = extracted.metadataLines.isEmpty
                ? "Klinisk anteckning från Apple Health."
                : extracted.metadataLines.joined(separator: "\n")
            notes = extracted.noteBlocks.isEmpty ? nil : extracted.noteBlocks
            tags += extracted.tags

            // Extract provider and author from FHIR JSON
            if let data = record.fhirResource?.data,
               let fhirObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let authors = fhirObj["author"] as? [[String: Any]],
                   let authorName = authors.first.flatMap({ $0["display"] as? String }) {
                    // Extract role from context extension
                    let role = (fhirObj["context"] as? [String: Any])
                        .flatMap { $0["extension"] as? [[String: Any]] }?
                        .compactMap { ($0["valueCodeableConcept"] as? [String: Any])?["text"] as? String }
                        .first
                    responsiblePerson = EirResponsiblePerson(name: authorName, role: role)
                }
                // Use encounter display as provider name if available
                if let context = fhirObj["context"] as? [String: Any],
                   let encounters = context["encounter"] as? [[String: Any]],
                   let encounterDisplay = encounters.first?["display"] as? String {
                    provider = EirProvider(name: encounterDisplay, region: nil, location: nil)
                }
            }

        default:
            guard let quantitySample = sample as? HKQuantitySample,
                  let unit = category.hkUnit else { return nil }
            let value = quantitySample.quantity.doubleValue(for: unit)
            let formatted = formatValue(value)
            summary = "\(category.rawValue): \(formatted) \(category.unit)"
            details = "Värde: \(formatted) \(category.unit)"
        }

        return EirEntry(
            id: "hk-\(index)",
            date: dateStr,
            time: timeStr,
            category: category.eirCategory,
            type: category.rawValue,
            provider: provider,
            status: nil,
            responsiblePerson: responsiblePerson,
            content: EirContent(summary: summary, details: details, notes: notes),
            attachments: nil,
            tags: Array(Set(tags)).sorted()
        )
    }

    // MARK: - YAML Serialization

    static func serializeToYAML(_ document: EirDocument) throws -> String {
        let encoder = YAMLEncoder()
        return try encoder.encode(document)
    }

    static func saveToDocuments(_ yamlString: String, fileName: String) throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "HealthKitToEirConverter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not access Documents directory"]
            )
        }
        let fileURL = docs.appendingPathComponent(fileName)
        try yamlString.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Helpers

    private static func formatValue(_ value: Double, decimals: Int = 1) -> String {
        if decimals == 0 {
            return String(Int(value.rounded()))
        }
        // Show integer if whole number
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.\(decimals)f", value)
    }

    private static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Löpning"
        case .walking: return "Promenad"
        case .cycling: return "Cykling"
        case .swimming: return "Simning"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Styrketräning"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Vandring"
        case .dance: return "Dans"
        case .elliptical: return "Crosstrainer"
        case .rowing: return "Rodd"
        case .stairClimbing: return "Trappklättring"
        case .pilates: return "Pilates"
        case .soccer: return "Fotboll"
        case .tennis: return "Tennis"
        case .basketball: return "Basket"
        case .golf: return "Golf"
        case .skatingSports: return "Skridskoåkning"
        case .crossCountrySkiing: return "Längdskidåkning"
        case .downhillSkiing: return "Utförsåkning"
        default: return "Träning"
        }
    }
}
