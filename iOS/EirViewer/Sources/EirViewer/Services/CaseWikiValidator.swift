import Foundation

enum CaseWikiValidator {
    static let schemaVersion = "patient-case-wiki-v1"

    static func validatedPages(
        _ pages: [CaseWikiPage],
        sourceCards: [CaseSourceCard],
        provider: LLMProviderConfig
    ) -> [CaseWikiPage] {
        let validEntryIDs = Set(sourceCards.map(\.entryID))
        let sourceByID = Dictionary(uniqueKeysWithValues: sourceCards.map { ($0.entryID, $0) })
        var seen = Set<String>()

        return pages.compactMap { page in
            let pageID = page.id.stableCaseID
            guard !seen.contains(pageID) else { return nil }
            seen.insert(pageID)

            var copy = page
            copy.id = pageID
            copy.outgoingLinks = page.outgoingLinks.map(\.stableCaseID).filter { !$0.isEmpty }
            copy.sourceRefs = page.sourceRefs.filter { validEntryIDs.contains($0.entryID) }
            copy.claims = page.claims.compactMap { claim in
                var cleanClaim = claim
                cleanClaim.sourceRefs = claim.sourceRefs.filter { validEntryIDs.contains($0.entryID) }
                if cleanClaim.sourceRefs.isEmpty, page.kind != .patientProfile {
                    return nil
                }
                return cleanClaim
            }

            if copy.sourceRefs.isEmpty, page.kind != .patientProfile {
                let claimRefs = copy.claims.flatMap(\.sourceRefs)
                copy.sourceRefs = claimRefs
            }

            copy.sourceRefs = copy.sourceRefs.map { ref in
                guard let card = sourceByID[ref.entryID] else { return ref }
                return CaseSourceRef(
                    entryID: ref.entryID,
                    date: ref.date ?? card.date,
                    label: ref.label.isEmpty ? (card.summary ?? card.type ?? "Source") : ref.label,
                    quote: ref.quote
                )
            }

            if copy.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.summary = CaseSourceCardBuilder.truncated(copy.bodyMarkdown, limit: 140)
            }

            if copy.generatedBy.schemaVersion.isEmpty {
                copy.generatedBy = CaseGenerationMetadata(
                    method: copy.generatedBy.method,
                    modelName: provider.model,
                    generatedAt: Date(),
                    schemaVersion: schemaVersion
                )
            }

            return copy
        }
    }

    static func index(
        pages: [CaseWikiPage],
        sourceCards: [CaseSourceCard]
    ) -> CaseWikiIndex {
        let cited = Set(pages.flatMap(\.sourceEntryIDs))
        let all = Set(sourceCards.map(\.entryID))
        let uncited = Array(all.subtracting(cited)).sorted()

        return CaseWikiIndex(
            entries: pages.map { page in
                CaseWikiIndexEntry(
                    id: page.id,
                    pageID: page.id,
                    title: page.title,
                    kind: page.kind,
                    summary: page.summary,
                    sourceCount: page.sourceEntryIDs.count
                )
            }
            .sorted { $0.title < $1.title },
            sourceCoverage: CaseSourceCoverage(
                totalSourceCount: all.count,
                coveredSourceCount: cited.count,
                uncitedEntryIDs: uncited
            ),
            updatedAt: Date()
        )
    }

    static func lint(
        pages: [CaseWikiPage],
        sourceCards: [CaseSourceCard],
        batchResults: [CaseIngestBatchResult]
    ) -> [CaseWikiLintFinding] {
        var findings: [CaseWikiLintFinding] = []
        let allEntryIDs = Set(sourceCards.map(\.entryID))
        let cited = Set(pages.flatMap(\.sourceEntryIDs))
        let uncited = Array(allEntryIDs.subtracting(cited)).sorted()

        if !uncited.isEmpty {
            findings.append(CaseWikiLintFinding(
                id: "source-coverage",
                title: "Some records are not represented yet",
                detail: "\(uncited.count) imported records are not cited by any case wiki page. They remain searchable in the raw journal.",
                severity: .info,
                sourceEntryIDs: Array(uncited.prefix(25)),
                pageIDs: []
            ))
        }

        for page in pages where page.kind != .patientProfile {
            if page.sourceRefs.isEmpty {
                findings.append(CaseWikiLintFinding(
                    id: "page-\(page.id)-no-sources",
                    title: "Page has no sources",
                    detail: "\(page.title) has no source links and should be reviewed before being used in a visit brief.",
                    severity: .warning,
                    sourceEntryIDs: [],
                    pageIDs: [page.id]
                ))
            }
        }

        let openFollowUps = batchResults
            .flatMap(\.followUps)
            .filter { $0.status.lowercased() != "closed" }

        if !openFollowUps.isEmpty {
            findings.append(CaseWikiLintFinding(
                id: "possible-open-followups",
                title: "Possible follow-ups to review",
                detail: "\(openFollowUps.count) follow-up, referral, or control signals were marked open or unclear by the compiler.",
                severity: .needsReview,
                sourceEntryIDs: Array(Set(openFollowUps.flatMap(\.sourceEntryIDs))).sorted(),
                pageIDs: pages.filter { $0.kind == .unresolvedIssue || $0.kind == .visitBrief }.map(\.id)
            ))
        }

        let warnings = batchResults.flatMap(\.warnings)
        if !warnings.isEmpty {
            findings.append(CaseWikiLintFinding(
                id: "compiler-warnings",
                title: "Compiler warnings",
                detail: warnings.prefix(3).map { $0.title }.joined(separator: ", "),
                severity: .warning,
                sourceEntryIDs: Array(Set(warnings.flatMap(\.sourceEntryIDs))).sorted(),
                pageIDs: []
            ))
        }

        return findings
    }
}
