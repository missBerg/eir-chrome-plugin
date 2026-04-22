import Foundation

struct CaseWikiIngestProgress {
    var progress: Double
    var status: String
}

enum CaseWikiIngestError: LocalizedError {
    case noProvider
    case noUsableModel
    case invalidLLMOutput(String)

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "No AI provider is configured."
        case .noUsableModel:
            return "No usable AI model is available for building the case wiki."
        case .invalidLLMOutput(let detail):
            return "The case wiki compiler returned data the app could not use: \(detail)"
        }
    }
}

struct CaseWikiIngestService {
    private let batchSize = 18

    @MainActor
    func buildWiki(
        profileID: UUID,
        document: EirDocument,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager,
        progress: @escaping @MainActor (CaseWikiIngestProgress) -> Void
    ) async throws -> PatientCaseWiki {
        let sourceCards = CaseSourceCardBuilder.build(from: document)
        let signature = CaseSourceCardBuilder.documentSignature(for: document)

        progress(CaseWikiIngestProgress(progress: 0.05, status: "Preparing source cards"))

        let config = settingsVM.activeProvider
        guard let config else { throw CaseWikiIngestError.noProvider }

        let requester = try await makeRequester(
            config: config,
            settingsVM: settingsVM,
            localModelManager: localModelManager
        )

        var batchResults: [CaseIngestBatchResult] = []
        let batches = sourceCards.chunked(into: batchSize)
        for (index, batch) in batches.enumerated() {
            let fraction = 0.1 + (0.45 * Double(index) / Double(max(batches.count, 1)))
            progress(CaseWikiIngestProgress(
                progress: fraction,
                status: "Reading records \(index + 1) of \(batches.count)"
            ))

            do {
                let result = try await extractBatch(batch, requester: requester)
                batchResults.append(result)
            } catch {
                batchResults.append(deterministicBatchFallback(for: batch, warning: error.localizedDescription))
            }
        }

        progress(CaseWikiIngestProgress(progress: 0.62, status: "Writing wiki pages"))

        let pages: [CaseWikiPage]
        do {
            pages = try await generatePages(
                document: document,
                sourceCards: sourceCards,
                batchResults: batchResults,
                requester: requester,
                provider: config
            )
        } catch {
            pages = deterministicPages(
                document: document,
                sourceCards: sourceCards,
                batchResults: batchResults,
                provider: config,
                warning: error.localizedDescription
            )
        }

        progress(CaseWikiIngestProgress(progress: 0.84, status: "Checking citations"))

        let validatedPages = CaseWikiValidator.validatedPages(
            pages,
            sourceCards: sourceCards,
            provider: config
        )
        let lintFindings = CaseWikiValidator.lint(
            pages: validatedPages,
            sourceCards: sourceCards,
            batchResults: batchResults
        )
        let index = CaseWikiValidator.index(
            pages: validatedPages,
            sourceCards: sourceCards
        )

        progress(CaseWikiIngestProgress(progress: 0.96, status: "Saving case wiki"))

        return PatientCaseWiki(
            profileID: profileID,
            documentSignature: signature,
            generatedAt: Date(),
            sourceCount: sourceCards.count,
            pages: validatedPages,
            index: index,
            log: [
                CaseWikiLogEntry(
                    id: UUID(),
                    date: Date(),
                    operation: .ingest,
                    summary: "Built patient case wiki from \(sourceCards.count) source records.",
                    affectedPageIDs: validatedPages.map(\.id),
                    sourceEntryIDs: sourceCards.map(\.entryID)
                )
            ],
            lintFindings: lintFindings
        )
    }

    @MainActor
    private func makeRequester(
        config: LLMProviderConfig,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async throws -> CaseWikiLLMRequester {
        if config.type.isLocal {
            try await localModelManager.ensurePreferredModelLoaded()
            return .local(localModelManager)
        }

        let credential = try await settingsVM.resolvedCredential(for: config)
        let service = LLMService(config: config, apiKey: credential)
        return .cloud(service, model: config.model)
    }

    private func extractBatch(
        _ cards: [CaseSourceCard],
        requester: CaseWikiLLMRequester
    ) async throws -> CaseIngestBatchResult {
        let prompt = """
        You compile Swedish/English electronic health record entries into structured case-wiki building blocks.
        Return only valid JSON with this exact shape:
        {
          "timelineEvents": [{"title":"","date":"","summary":"","kind":"visit|symptom|lab|referral|diagnosis|medication|vaccination|other","sourceEntryIDs":[""]}],
          "clinicalFacts": [{"text":"","claimType":"recordedFact|patientReported|clinicianAssessment|testResult|trend|unresolvedQuestion|possibleContradiction|hypothesis","confidence":"high|medium|low|unknown","sourceEntryIDs":[""]}],
          "careThreads": [{"title":"","summary":"","status":"active|closed|unclear","sourceEntryIDs":[""]}],
          "followUps": [{"title":"","detail":"","status":"open|closed|unclear","sourceEntryIDs":[""]}],
          "labObservations": [{"name":"","value":"","unit":"","date":"","interpretation":"","sourceEntryIDs":[""]}],
          "warnings": [{"title":"","detail":"","sourceEntryIDs":[""]}]
        }

        Rules:
        - Every item must cite at least one Journal Entry ID from the input.
        - Do not diagnose. Use "recorded", "reported", "suggests", "unclear", or "to discuss with care".
        - Preserve uncertainty and contradictions.
        - Prefer clinically useful facts over exhaustive summaries.
        - If a field is unknown, use an empty string, not invented content.
        """

        let user = """
        Source records:

        \(cards.map(\.compactMarkdown).joined(separator: "\n\n---\n\n"))
        """

        let raw = try await requester.complete(systemPrompt: prompt, userPrompt: user)
        return try CaseWikiJSONDecoder.decode(CaseIngestBatchResult.self, from: raw)
    }

    private func generatePages(
        document: EirDocument,
        sourceCards: [CaseSourceCard],
        batchResults: [CaseIngestBatchResult],
        requester: CaseWikiLLMRequester,
        provider: LLMProviderConfig
    ) async throws -> [CaseWikiPage] {
        let compact = CaseWikiCompiledContext(
            patientName: document.metadata.patient?.name,
            birthDate: document.metadata.patient?.birthDate,
            dateRange: document.metadata.exportInfo?.dateRange,
            sourceCount: sourceCards.count,
            categoryCounts: Dictionary(grouping: sourceCards, by: { $0.category ?? "Unknown" })
                .mapValues(\.count),
            batchResults: batchResults
        )

        let contextData = try JSONEncoder().encode(compact)
        let context = String(decoding: contextData, as: UTF8.self)

        let prompt = """
        You maintain a Patient Case Wiki. The raw health records are immutable; your job is to compile them into durable, source-cited wiki pages.
        Return only valid JSON:
        {
          "pages": [
            {
              "id": "overview",
              "title": "",
              "kind": "overview|patientProfile|timeline|symptomThread|diagnosisClaim|labTrend|referralThread|medicationThread|unresolvedIssue|hypothesis|visitBrief|sourceSummary",
              "summary": "",
              "bodyMarkdown": "",
              "claims": [{"text":"","claimType":"recordedFact|patientReported|clinicianAssessment|testResult|trend|unresolvedQuestion|possibleContradiction|hypothesis","confidence":"high|medium|low|unknown","sourceEntryIDs":[""],"qualifiers":[""]}],
              "sourceEntryIDs": [""],
              "outgoingLinks": [""]
            }
          ]
        }

        Required pages:
        - overview
        - patient-profile
        - timeline
        - unresolved-followups
        - visit-brief

        Rules:
        - Every page except patient-profile must cite sourceEntryIDs.
        - Every claim must cite sourceEntryIDs.
        - Never state a definitive diagnosis. Clearly separate recorded facts, clinician assessments, patient-reported symptoms, hypotheses, and unresolved questions.
        - A visit brief should help the user collaborate with a clinician: concise problem statement, important timeline, open follow-ups, questions to ask.
        - Do not cite clinical practice guidelines unless provided in the input.
        - Keep page bodies compact and useful on a phone.
        """

        let user = """
        Compiled case evidence JSON:
        \(context)
        """

        let raw = try await requester.complete(systemPrompt: prompt, userPrompt: user)
        let response = try CaseWikiJSONDecoder.decode(CaseWikiPageGenerationResponse.self, from: raw)
        let now = Date()
        let metadata = CaseGenerationMetadata(
            method: .llm,
            modelName: provider.model,
            generatedAt: now,
            schemaVersion: CaseWikiValidator.schemaVersion
        )

        return response.pages.map { spec in
            let refs = spec.sourceEntryIDs.map { id in
                let card = sourceCards.first { $0.entryID == id }
                return CaseSourceRef(
                    entryID: id,
                    date: card?.date,
                    label: card?.summary ?? card?.type ?? "Source"
                )
            }

            let claims = spec.claims.enumerated().map { offset, claim in
                CaseClaim(
                    id: "\(spec.id)-claim-\(offset)",
                    text: claim.text,
                    claimType: CaseClaimType(rawValue: claim.claimType) ?? .recordedFact,
                    confidence: CaseClaimConfidence(rawValue: claim.confidence) ?? .unknown,
                    sourceRefs: claim.sourceEntryIDs.map { id in
                        let card = sourceCards.first { $0.entryID == id }
                        return CaseSourceRef(
                            entryID: id,
                            date: card?.date,
                            label: card?.summary ?? card?.type ?? "Source"
                        )
                    },
                    qualifiers: claim.qualifiers
                )
            }

            return CaseWikiPage(
                id: spec.id.stableCaseID,
                title: spec.title,
                kind: CaseWikiPageKind(rawValue: spec.kind) ?? .sourceSummary,
                summary: spec.summary,
                bodyMarkdown: spec.bodyMarkdown,
                claims: claims,
                sourceRefs: refs,
                outgoingLinks: spec.outgoingLinks.map(\.stableCaseID),
                updatedAt: now,
                generatedBy: metadata
            )
        }
    }

    private func deterministicBatchFallback(
        for cards: [CaseSourceCard],
        warning: String
    ) -> CaseIngestBatchResult {
        let timeline = cards.map { card in
            CaseTimelineEventDraft(
                title: card.summary ?? card.type ?? card.category ?? "Journal entry",
                date: card.date ?? "",
                summary: card.detailsPreview ?? card.summary ?? "",
                kind: CaseTimelineKind.from(category: card.category, type: card.type).rawValue,
                sourceEntryIDs: [card.entryID]
            )
        }

        let followUps = cards.compactMap { card -> CaseFollowUpDraft? in
            let lower = card.fullText.lowercased()
            guard lower.contains("uppfölj") || lower.contains("återbesök") || lower.contains("kontroll") || lower.contains("remiss") else {
                return nil
            }
            return CaseFollowUpDraft(
                title: card.summary ?? "Possible follow-up",
                detail: card.detailsPreview ?? "",
                status: "unclear",
                sourceEntryIDs: [card.entryID]
            )
        }

        return CaseIngestBatchResult(
            timelineEvents: timeline,
            clinicalFacts: [],
            careThreads: [],
            followUps: followUps,
            labObservations: [],
            warnings: [
                CaseWarningDraft(
                    title: "AI batch fallback used",
                    detail: warning,
                    sourceEntryIDs: cards.map(\.entryID)
                )
            ]
        )
    }

    private func deterministicPages(
        document: EirDocument,
        sourceCards: [CaseSourceCard],
        batchResults: [CaseIngestBatchResult],
        provider: LLMProviderConfig,
        warning: String
    ) -> [CaseWikiPage] {
        let metadata = CaseGenerationMetadata(
            method: .hybrid,
            modelName: provider.model,
            generatedAt: Date(),
            schemaVersion: CaseWikiValidator.schemaVersion
        )
        let dateRange = document.metadata.exportInfo?.dateRange
        let timeline = batchResults.flatMap(\.timelineEvents).prefix(24)
        let followUps = batchResults.flatMap(\.followUps).prefix(12)
        let allRefs = sourceCards.prefix(40).map {
            CaseSourceRef(entryID: $0.entryID, date: $0.date, label: $0.summary ?? $0.type ?? "Source")
        }

        let overviewBody = """
        ## Summary
        This case wiki was built from \(sourceCards.count) imported records\(dateRange.map { " spanning \($0.start ?? "?") to \($0.end ?? "?")" } ?? "").

        ## Main Threads
        \(categoryBulletList(sourceCards))

        ## Compiler Note
        The AI page-writing pass could not be fully validated, so Eir created a structured fallback wiki. Reason: \(warning)
        """

        let timelineBody = """
        ## High-Signal Timeline
        \(timeline.map { "- \($0.date): \($0.title) — \($0.summary)" }.joined(separator: "\n"))
        """

        let followUpBody = followUps.isEmpty
            ? "## Open Follow-Ups\nNo clear unresolved follow-up signals were found in the first pass."
            : "## Open Follow-Ups\n" + followUps.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")

        let visitBody = """
        ## Opening
        I would like help reviewing the whole pattern in my records rather than starting from a single visit.

        ## What To Review
        \(followUps.prefix(6).map { "- \($0.title)" }.joined(separator: "\n"))

        ## Useful Questions
        - Are there any earlier referrals, tests, or follow-ups here that should be checked again?
        - Which findings are important, and which are less clinically relevant?
        - What would be the safest next step from here?
        """

        return [
            CaseWikiPage(
                id: "overview",
                title: "Case Overview",
                kind: .overview,
                summary: "Structured overview compiled from imported records.",
                bodyMarkdown: overviewBody,
                claims: [],
                sourceRefs: allRefs,
                outgoingLinks: ["timeline", "unresolved-followups", "visit-brief"],
                updatedAt: Date(),
                generatedBy: metadata
            ),
            CaseWikiPage(
                id: "timeline",
                title: "Timeline",
                kind: .timeline,
                summary: "High-signal events extracted from the imported record.",
                bodyMarkdown: timelineBody,
                claims: [],
                sourceRefs: timeline.flatMap(\.sourceEntryIDs).unique().map { id in
                    let card = sourceCards.first { $0.entryID == id }
                    return CaseSourceRef(entryID: id, date: card?.date, label: card?.summary ?? "Timeline source")
                },
                outgoingLinks: ["overview"],
                updatedAt: Date(),
                generatedBy: metadata
            ),
            CaseWikiPage(
                id: "unresolved-followups",
                title: "Unresolved Follow-Ups",
                kind: .unresolvedIssue,
                summary: "Possible follow-up items that may deserve review.",
                bodyMarkdown: followUpBody,
                claims: [],
                sourceRefs: followUps.flatMap(\.sourceEntryIDs).unique().map { id in
                    let card = sourceCards.first { $0.entryID == id }
                    return CaseSourceRef(entryID: id, date: card?.date, label: card?.summary ?? "Follow-up source")
                },
                outgoingLinks: ["visit-brief"],
                updatedAt: Date(),
                generatedBy: metadata
            ),
            CaseWikiPage(
                id: "visit-brief",
                title: "Visit Brief",
                kind: .visitBrief,
                summary: "A concise agenda for the next healthcare visit.",
                bodyMarkdown: visitBody,
                claims: [],
                sourceRefs: allRefs,
                outgoingLinks: ["overview", "unresolved-followups"],
                updatedAt: Date(),
                generatedBy: metadata
            )
        ]
    }

    private func categoryBulletList(_ cards: [CaseSourceCard]) -> String {
        let counts = Dictionary(grouping: cards, by: { $0.category ?? "Unknown" })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }

        return counts.map { "- \($0.key): \($0.value) records" }.joined(separator: "\n")
    }
}

private enum CaseWikiLLMRequester {
    case cloud(LLMService, model: String)
    case local(LocalModelManager)

    @MainActor
    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        switch self {
        case .cloud(let service, _):
            return try await service.completeChat(messages: [
                (role: "system", content: systemPrompt),
                (role: "user", content: userPrompt)
            ])
        case .local(let manager):
            try await manager.ensurePreferredModelLoaded()
            return try await manager.service.completeDetachedResponse(
                userMessage: userPrompt,
                systemPrompt: systemPrompt
            )
        }
    }
}

private struct CaseWikiCompiledContext: Codable {
    let patientName: String?
    let birthDate: String?
    let dateRange: EirDateRange?
    let sourceCount: Int
    let categoryCounts: [String: Int]
    let batchResults: [CaseIngestBatchResult]
}

struct CaseIngestBatchResult: Codable {
    let timelineEvents: [CaseTimelineEventDraft]
    let clinicalFacts: [CaseClaimDraft]
    let careThreads: [CaseCareThreadDraft]
    let followUps: [CaseFollowUpDraft]
    let labObservations: [CaseLabObservationDraft]
    let warnings: [CaseWarningDraft]

    enum CodingKeys: String, CodingKey {
        case timelineEvents
        case clinicalFacts
        case careThreads
        case followUps
        case labObservations
        case warnings
    }

    init(
        timelineEvents: [CaseTimelineEventDraft],
        clinicalFacts: [CaseClaimDraft],
        careThreads: [CaseCareThreadDraft],
        followUps: [CaseFollowUpDraft],
        labObservations: [CaseLabObservationDraft],
        warnings: [CaseWarningDraft]
    ) {
        self.timelineEvents = timelineEvents
        self.clinicalFacts = clinicalFacts
        self.careThreads = careThreads
        self.followUps = followUps
        self.labObservations = labObservations
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timelineEvents = try container.decodeIfPresent([CaseTimelineEventDraft].self, forKey: .timelineEvents) ?? []
        clinicalFacts = try container.decodeIfPresent([CaseClaimDraft].self, forKey: .clinicalFacts) ?? []
        careThreads = try container.decodeIfPresent([CaseCareThreadDraft].self, forKey: .careThreads) ?? []
        followUps = try container.decodeIfPresent([CaseFollowUpDraft].self, forKey: .followUps) ?? []
        labObservations = try container.decodeIfPresent([CaseLabObservationDraft].self, forKey: .labObservations) ?? []
        warnings = try container.decodeIfPresent([CaseWarningDraft].self, forKey: .warnings) ?? []
    }
}

struct CaseTimelineEventDraft: Codable, Hashable {
    let title: String
    let date: String
    let summary: String
    let kind: String
    let sourceEntryIDs: [String]
}

struct CaseClaimDraft: Codable, Hashable {
    let text: String
    let claimType: String
    let confidence: String
    let sourceEntryIDs: [String]
    var qualifiers: [String] = []

    enum CodingKeys: String, CodingKey {
        case text
        case claimType
        case confidence
        case sourceEntryIDs
        case qualifiers
    }

    init(text: String, claimType: String, confidence: String, sourceEntryIDs: [String], qualifiers: [String] = []) {
        self.text = text
        self.claimType = claimType
        self.confidence = confidence
        self.sourceEntryIDs = sourceEntryIDs
        self.qualifiers = qualifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        claimType = try container.decodeIfPresent(String.self, forKey: .claimType) ?? CaseClaimType.recordedFact.rawValue
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence) ?? CaseClaimConfidence.unknown.rawValue
        sourceEntryIDs = try container.decodeIfPresent([String].self, forKey: .sourceEntryIDs) ?? []
        qualifiers = try container.decodeIfPresent([String].self, forKey: .qualifiers) ?? []
    }
}

struct CaseCareThreadDraft: Codable, Hashable {
    let title: String
    let summary: String
    let status: String
    let sourceEntryIDs: [String]
}

struct CaseFollowUpDraft: Codable, Hashable {
    let title: String
    let detail: String
    let status: String
    let sourceEntryIDs: [String]
}

struct CaseLabObservationDraft: Codable, Hashable {
    let name: String
    let value: String
    let unit: String
    let date: String
    let interpretation: String
    let sourceEntryIDs: [String]
}

struct CaseWarningDraft: Codable, Hashable {
    let title: String
    let detail: String
    let sourceEntryIDs: [String]
}

private enum CaseTimelineKind: String {
    case visit
    case symptom
    case lab
    case referral
    case diagnosis
    case medication
    case vaccination
    case other

    static func from(category: String?, type: String?) -> CaseTimelineKind {
        let text = [category, type].compactMap { $0 }.joined(separator: " ").lowercased()
        if text.contains("remiss") { return .referral }
        if text.contains("prov") || text.contains("lab") { return .lab }
        if text.contains("diagnos") { return .diagnosis }
        if text.contains("läkemed") || text.contains("recept") { return .medication }
        if text.contains("vaccin") { return .vaccination }
        if text.contains("besök") || text.contains("kontakt") { return .visit }
        return .other
    }
}

private struct CaseWikiPageGenerationResponse: Codable {
    let pages: [CaseWikiPageSpec]
}

private struct CaseWikiPageSpec: Codable {
    let id: String
    let title: String
    let kind: String
    let summary: String
    let bodyMarkdown: String
    let claims: [CaseWikiClaimSpec]
    let sourceEntryIDs: [String]
    let outgoingLinks: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case summary
        case bodyMarkdown
        case claims
        case sourceEntryIDs
        case outgoingLinks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? CaseWikiPageKind.sourceSummary.rawValue
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        bodyMarkdown = try container.decodeIfPresent(String.self, forKey: .bodyMarkdown) ?? summary
        claims = try container.decodeIfPresent([CaseWikiClaimSpec].self, forKey: .claims) ?? []
        sourceEntryIDs = try container.decodeIfPresent([String].self, forKey: .sourceEntryIDs) ?? []
        outgoingLinks = try container.decodeIfPresent([String].self, forKey: .outgoingLinks) ?? []
    }
}

private struct CaseWikiClaimSpec: Codable {
    let text: String
    let claimType: String
    let confidence: String
    let sourceEntryIDs: [String]
    let qualifiers: [String]

    enum CodingKeys: String, CodingKey {
        case text
        case claimType
        case confidence
        case sourceEntryIDs
        case qualifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        claimType = try container.decodeIfPresent(String.self, forKey: .claimType) ?? CaseClaimType.recordedFact.rawValue
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence) ?? CaseClaimConfidence.unknown.rawValue
        sourceEntryIDs = try container.decodeIfPresent([String].self, forKey: .sourceEntryIDs) ?? []
        qualifiers = try container.decodeIfPresent([String].self, forKey: .qualifiers) ?? []
    }
}

private enum CaseWikiJSONDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let candidates = jsonCandidates(from: raw)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(type, from: data) {
                return decoded
            }
        }
        throw CaseWikiIngestError.invalidLLMOutput(String(raw.prefix(240)))
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        var candidates: [String] = []
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        candidates.append(trimmed)

        if let fenced = extractFencedJSON(from: trimmed) {
            candidates.append(fenced)
        }

        if let object = extractBalanced(from: trimmed, open: "{", close: "}") {
            candidates.append(object)
        }

        return candidates
    }

    private static func extractFencedJSON(from raw: String) -> String? {
        guard let start = raw.range(of: "```") else { return nil }
        let afterStart = raw[start.upperBound...]
        guard let end = afterStart.range(of: "```") else { return nil }
        var body = String(afterStart[..<end.lowerBound])
        if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("json") {
            body = body.replacingOccurrences(of: #"^\s*json"#, with: "", options: .regularExpression)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractBalanced(from raw: String, open: Character, close: Character) -> String? {
        guard let start = raw.firstIndex(of: open) else { return nil }
        var depth = 0
        var inString = false
        var escaping = false
        var index = start

        while index < raw.endIndex {
            let char = raw[index]
            if escaping {
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == open {
                    depth += 1
                } else if char == close {
                    depth -= 1
                    if depth == 0 {
                        return String(raw[start...index])
                    }
                }
            }
            index = raw.index(after: index)
        }

        return nil
    }
}

private extension Array where Element == String {
    func unique() -> [String] {
        Array(Set(self)).sorted()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        var start = 0
        while start < count {
            let end = Swift.min(start + size, count)
            chunks.append(Array(self[start..<end]))
            start = end
        }
        return chunks
    }
}
