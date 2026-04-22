import Foundation

struct PatientCaseWiki: Codable {
    var profileID: UUID
    var documentSignature: String
    var generatedAt: Date
    var sourceCount: Int
    var pages: [CaseWikiPage]
    var index: CaseWikiIndex
    var log: [CaseWikiLogEntry]
    var lintFindings: [CaseWikiLintFinding]

    var overviewPage: CaseWikiPage? {
        page(id: "overview")
    }

    var visitBriefPage: CaseWikiPage? {
        page(kind: .visitBrief)
    }

    func page(id: String) -> CaseWikiPage? {
        pages.first { $0.id == id }
    }

    func page(kind: CaseWikiPageKind) -> CaseWikiPage? {
        pages.first { $0.kind == kind }
    }
}

struct CaseWikiPage: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var kind: CaseWikiPageKind
    var summary: String
    var bodyMarkdown: String
    var claims: [CaseClaim]
    var sourceRefs: [CaseSourceRef]
    var outgoingLinks: [String]
    var updatedAt: Date
    var generatedBy: CaseGenerationMetadata

    var sourceEntryIDs: [String] {
        Array(Set(sourceRefs.map(\.entryID))).sorted()
    }
}

enum CaseWikiPageKind: String, Codable, CaseIterable {
    case overview
    case patientProfile
    case timeline
    case symptomThread
    case diagnosisClaim
    case labTrend
    case referralThread
    case medicationThread
    case unresolvedIssue
    case hypothesis
    case visitBrief
    case sourceSummary

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .patientProfile: return "Patient Profile"
        case .timeline: return "Timeline"
        case .symptomThread: return "Symptom Thread"
        case .diagnosisClaim: return "Diagnosis Claim"
        case .labTrend: return "Lab Trend"
        case .referralThread: return "Referral Thread"
        case .medicationThread: return "Medication Thread"
        case .unresolvedIssue: return "Unresolved Issue"
        case .hypothesis: return "Hypothesis"
        case .visitBrief: return "Visit Brief"
        case .sourceSummary: return "Source Summary"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "sparkles.rectangle.stack"
        case .patientProfile: return "person.text.rectangle"
        case .timeline: return "timeline.selection"
        case .symptomThread: return "waveform.path.ecg"
        case .diagnosisClaim: return "cross.case"
        case .labTrend: return "chart.xyaxis.line"
        case .referralThread: return "arrow.triangle.branch"
        case .medicationThread: return "pills"
        case .unresolvedIssue: return "exclamationmark.magnifyingglass"
        case .hypothesis: return "lightbulb"
        case .visitBrief: return "doc.text.magnifyingglass"
        case .sourceSummary: return "doc.plaintext"
        }
    }
}

struct CaseClaim: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var claimType: CaseClaimType
    var confidence: CaseClaimConfidence
    var sourceRefs: [CaseSourceRef]
    var qualifiers: [String]
}

enum CaseClaimType: String, Codable, CaseIterable {
    case recordedFact
    case patientReported
    case clinicianAssessment
    case testResult
    case trend
    case unresolvedQuestion
    case possibleContradiction
    case hypothesis
}

enum CaseClaimConfidence: String, Codable, CaseIterable {
    case high
    case medium
    case low
    case unknown
}

struct CaseSourceRef: Codable, Identifiable, Hashable {
    var id: String
    var entryID: String
    var date: String?
    var label: String
    var quote: String?

    init(entryID: String, date: String?, label: String, quote: String? = nil) {
        self.id = "\(entryID)-\(label)".stableCaseID
        self.entryID = entryID
        self.date = date
        self.label = label
        self.quote = quote
    }
}

struct CaseGenerationMetadata: Codable, Hashable {
    var method: CaseGenerationMethod
    var modelName: String?
    var generatedAt: Date
    var schemaVersion: String
}

enum CaseGenerationMethod: String, Codable {
    case deterministic
    case llm
    case hybrid
}

struct CaseWikiIndex: Codable {
    var entries: [CaseWikiIndexEntry]
    var sourceCoverage: CaseSourceCoverage
    var updatedAt: Date
}

struct CaseWikiIndexEntry: Codable, Identifiable, Hashable {
    var id: String
    var pageID: String
    var title: String
    var kind: CaseWikiPageKind
    var summary: String
    var sourceCount: Int
}

struct CaseSourceCoverage: Codable, Hashable {
    var totalSourceCount: Int
    var coveredSourceCount: Int
    var uncitedEntryIDs: [String]

    var coverageRatio: Double {
        guard totalSourceCount > 0 else { return 0 }
        return Double(coveredSourceCount) / Double(totalSourceCount)
    }
}

struct CaseWikiLogEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var operation: CaseWikiOperation
    var summary: String
    var affectedPageIDs: [String]
    var sourceEntryIDs: [String]
}

enum CaseWikiOperation: String, Codable {
    case ingest
    case query
    case lint
    case regenerate
}

struct CaseWikiLintFinding: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var severity: CaseWikiLintSeverity
    var sourceEntryIDs: [String]
    var pageIDs: [String]
}

enum CaseWikiLintSeverity: String, Codable, CaseIterable {
    case info
    case warning
    case needsReview

    var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .needsReview: return "Needs Review"
        }
    }
}

struct CaseSourceCard: Codable, Identifiable, Hashable {
    var id: String
    var entryID: String
    var date: String?
    var time: String?
    var category: String?
    var type: String?
    var provider: String?
    var responsiblePerson: String?
    var summary: String?
    var detailsPreview: String?
    var fullText: String
    var tags: [String]

    var compactMarkdown: String {
        var lines: [String] = []
        lines.append("Source ID: \(id)")
        lines.append("Journal Entry ID: \(entryID)")
        if let date { lines.append("Date: \(date)") }
        if let time { lines.append("Time: \(time)") }
        if let category { lines.append("Category: \(category)") }
        if let type { lines.append("Type: \(type)") }
        if let provider { lines.append("Provider: \(provider)") }
        if let responsiblePerson { lines.append("Responsible: \(responsiblePerson)") }
        if let summary { lines.append("Summary: \(summary)") }
        if let detailsPreview { lines.append("Text: \(detailsPreview)") }
        if !tags.isEmpty { lines.append("Tags: \(tags.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }
}

extension String {
    var stableCaseID: String {
        let lowered = lowercased()
        let allowed = CharacterSet.alphanumerics
        var output = ""
        var previousWasDash = false

        for scalar in lowered.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? UUID().uuidString : trimmed
    }
}
