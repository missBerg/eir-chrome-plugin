import SwiftUI

struct CaseWikiOverviewView: View {
    let wiki: PatientCaseWiki?
    let isBuilding: Bool
    let progress: Double
    let statusMessage: String
    let errorMessage: String?
    let needsRebuild: Bool
    let onBuild: () -> Void
    let onOpenEntry: (String) -> Void

    @State private var selectedPage: CaseWikiPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if isBuilding {
                    progressSection
                }

                if let errorMessage {
                    errorSection(errorMessage)
                }

                if let wiki {
                    statsSection(wiki)

                    if needsRebuild {
                        staleSection
                    }

                    if !wiki.lintFindings.isEmpty {
                        lintSection(wiki.lintFindings)
                    }

                    if let visitBrief = wiki.visitBriefPage {
                        featuredPage(visitBrief, title: "For the next visit")
                    }

                    pagesSection(wiki.pages)
                } else if !isBuilding {
                    emptyState
                }
            }
            .padding()
        }
        .background(AppColors.background)
        .sheet(item: $selectedPage) { page in
            CaseWikiPageDetailView(page: page, onOpenEntry: onOpenEntry)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Patient Case Wiki", systemImage: "sparkles.rectangle.stack")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.primary)

            Text("Helhetsbild")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)

            Text("Eir compiles imported records into a living, source-cited case wiki so future chats and visit briefs can start from the whole pattern.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onBuild) {
                Label(wiki == nil ? "Build Case Wiki" : "Regenerate", systemImage: "wand.and.stars")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(isBuilding ? AppColors.backgroundMuted : AppColors.primary)
                    .foregroundStyle(isBuilding ? AppColors.textSecondary : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBuilding)
        }
        .padding(22)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView()
                    .tint(AppColors.primary)
                Text(statusMessage.isEmpty ? "Building case wiki" : statusMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.text)
            }
            ProgressView(value: progress)
                .tint(AppColors.primary)
        }
        .padding(16)
        .background(AppColors.primarySoft)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorSection(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.orange)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var staleSection: some View {
        Label("Records changed since this wiki was generated. Regenerate to include the latest import.", systemImage: "arrow.clockwise")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.aiStrong)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.aiSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(AppColors.textSecondary.opacity(0.6))
            Text("No case wiki yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.text)
            Text("Build one after importing records. Eir will create source-cited pages for timeline, unresolved follow-ups, and visit preparation.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func statsSection(_ wiki: PatientCaseWiki) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile("\(wiki.sourceCount)", "Sources", AppColors.primary)
            statTile("\(wiki.pages.count)", "Pages", AppColors.teal)
            statTile("\(Int(wiki.index.sourceCoverage.coverageRatio * 100))%", "Coverage", AppColors.green)
            statTile("\(wiki.lintFindings.count)", "Review", AppColors.orange)
        }
    }

    private func statTile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func lintSection(_ findings: [CaseWikiLintFinding]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs review")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColors.text)

            ForEach(findings.prefix(4)) { finding in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(finding.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.text)
                        Spacer()
                        Text(finding.severity.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(finding.severity == .needsReview ? AppColors.orange : AppColors.textSecondary)
                    }
                    Text(finding.detail)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(12)
                .background(AppColors.backgroundMuted)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func featuredPage(_ page: CaseWikiPage, title: String) -> some View {
        Button {
            selectedPage = page
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: page.kind.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.primary)
                Text(page.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.text)
                Text(page.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label("\(page.sourceEntryIDs.count) sources", systemImage: "link")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(AppColors.primarySoft)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pagesSection(_ pages: [CaseWikiPage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wiki pages")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColors.text)

            ForEach(pages.sorted { $0.title < $1.title }) { page in
                Button {
                    selectedPage = page
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.kind.symbolName)
                            .font(.headline)
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(page.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.text)
                            Text(page.summary)
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text("\(page.sourceEntryIDs.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(13)
                    .background(AppColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CaseWikiPageDetailView: View {
    let page: CaseWikiPage
    let onOpenEntry: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(page.kind.displayName, systemImage: page.kind.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.primary)

                    Text(page.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColors.text)

                    Text(page.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    Divider()

                    Text(.init(page.bodyMarkdown))
                        .font(.body)
                        .foregroundStyle(AppColors.text)
                        .textSelection(.enabled)

                    if !page.claims.isEmpty {
                        claimsSection
                    }

                    if !page.sourceRefs.isEmpty {
                        sourcesSection
                    }
                }
                .padding()
            }
            .background(AppColors.background)
            .navigationTitle("Case Wiki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claims")
                .font(.headline.weight(.bold))
            ForEach(page.claims) { claim in
                VStack(alignment: .leading, spacing: 6) {
                    Text(claim.text)
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Text(claim.claimType.rawValue)
                        Text(claim.confidence.rawValue)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                }
                .padding(12)
                .background(AppColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.headline.weight(.bold))
            ForEach(page.sourceRefs) { ref in
                Button {
                    dismiss()
                    onOpenEntry(ref.entryID)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(AppColors.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.text)
                                .lineLimit(2)
                            if let date = ref.date {
                                Text(date)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(12)
                    .background(AppColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
