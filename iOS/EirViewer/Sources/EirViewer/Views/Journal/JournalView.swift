import Charts
import SwiftUI

struct JournalView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var profileStore: ProfileStore

    @State private var showingAddPerson = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var qrExportURL: URL?

    var body: some View {
        Group {
            if documentVM.document == nil {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textSecondary.opacity(0.5))
                    Text("No records loaded")
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let summary = appleHealthSummary {
                            appleHealthOverview(summary)
                        }

                        ForEach(documentVM.groupedEntries, id: \.key) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    NavigationLink(value: entry.id) {
                                        EntryCardView(
                                            entry: entry,
                                            isSelected: false
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text(group.key)
                                    .font(.headline)
                                    .foregroundColor(AppColors.text)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding()
                }
                .navigationDestination(for: String.self) { entryID in
                    if let entry = documentVM.document?.entries.first(where: { $0.id == entryID }) {
                        EntryDetailView(entry: entry)
                    }
                }
            }
        }
        .navigationTitle(profileStore.selectedProfile?.displayName ?? "Journal")
        .searchable(text: $documentVM.searchText, prompt: "Search entries...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedProfileFileURL != nil {
                    Menu {
                        Button {
                            shareSelectedProfile()
                        } label: {
                            Label("Export File", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showSelectedProfileQRCode()
                        } label: {
                            Label("Show QR Code", systemImage: "qrcode")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(AppColors.primary)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Category filter
                    Menu("Category") {
                        Button("All Categories") {
                            documentVM.selectedCategory = nil
                        }
                        ForEach(documentVM.categories, id: \.self) { cat in
                            Button {
                                documentVM.selectedCategory = cat
                            } label: {
                                HStack {
                                    Text(cat)
                                    if documentVM.selectedCategory == cat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    // Provider filter
                    Menu("Provider") {
                        Button("All Providers") {
                            documentVM.selectedProvider = nil
                        }
                        ForEach(documentVM.providers, id: \.self) { prov in
                            Button {
                                documentVM.selectedProvider = prov
                            } label: {
                                HStack {
                                    Text(prov)
                                    if documentVM.selectedProvider == prov {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    if documentVM.selectedCategory != nil || documentVM.selectedProvider != nil {
                        Divider()
                        Button("Clear Filters", role: .destructive) {
                            documentVM.clearFilters()
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(
                            documentVM.selectedCategory != nil || documentVM.selectedProvider != nil
                                ? AppColors.primary
                                : AppColors.textSecondary
                        )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Person list
                    ForEach(profileStore.profiles) { profile in
                        Button {
                            profileStore.selectProfile(profile.id)
                        } label: {
                            HStack {
                                Text(profile.displayName)
                                if let count = profile.totalEntries {
                                    Text("(\(count))")
                                }
                                if profile.id == profileStore.selectedProfileID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        showingAddPerson = true
                    } label: {
                        Label("Add Person...", systemImage: "person.badge.plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                        if profileStore.profiles.count > 1 {
                            Text(profileStore.selectedProfile?.initials ?? "")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonSheet()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: shareItems)
        }
        .sheet(
            isPresented: Binding(
                get: { qrExportURL != nil },
                set: { if !$0 { qrExportURL = nil } }
            )
        ) {
            if let qrExportURL {
                FileTransferQRCodeView(fileURL: qrExportURL)
            }
        }
        .background(AppColors.background)
    }

    private var selectedProfileFileURL: URL? {
        profileStore.selectedProfile?.fileURL
    }

    private func shareSelectedProfile() {
        guard let fileURL = selectedProfileFileURL else { return }
        shareItems = [fileURL]
        showShareSheet = true
    }

    private func showSelectedProfileQRCode() {
        qrExportURL = selectedProfileFileURL
    }

    private var appleHealthSummary: AppleHealthSummary? {
        guard let document = documentVM.document else { return nil }
        return AppleHealthSummary(document: document)
    }

    private func appleHealthOverview(_ summary: AppleHealthSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Health Overview")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.text)
                    Text("Imported activity data is summarized here before the full journal timeline.")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Text("HealthKit")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.aiStrong)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.aiSoft)
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                summaryTile(title: "Tracked days", value: "\(summary.daysTracked)", tint: AppColors.primary)
                summaryTile(title: "Metrics", value: "\(summary.metricCount)", tint: AppColors.blue)
                summaryTile(title: "Entries", value: "\(summary.entryCount)", tint: AppColors.green)
            }

            if !summary.stepTrend.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent steps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.text)

                    Chart(summary.stepTrend) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Steps", point.value)
                        )
                        .foregroundStyle(AppColors.primary.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text(intValue.formatted(.number.notation(.compactName)))
                                        .font(.caption2)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                .foregroundStyle(AppColors.border)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.day().month(.abbreviated))
                                        .font(.caption2)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(summary.metricBreakdown, id: \.metric) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppColors.categoryColor(for: item.metric))
                                .frame(width: 8, height: 8)
                            Text(item.metric)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.text)
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppColors.backgroundMuted)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(18)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func summaryTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundColor(tint)
            Text(title)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.backgroundMuted)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AppleHealthSummary {
    struct BreakdownItem {
        let metric: String
        let count: Int
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Int
    }

    let entryCount: Int
    let daysTracked: Int
    let metricCount: Int
    let metricBreakdown: [BreakdownItem]
    let stepTrend: [TrendPoint]

    init?(document: EirDocument) {
        let entries = document.entries.filter { entry in
            entry.tags?.contains("apple-health") == true
                || entry.provider?.name == "Apple Health"
                || document.metadata.source == "Apple Health"
        }

        guard !entries.isEmpty else { return nil }

        entryCount = entries.count
        daysTracked = Set(entries.compactMap(\.date)).count

        let groupedMetrics = Dictionary(grouping: entries) { $0.type ?? $0.category ?? "Unknown" }
        metricBreakdown = groupedMetrics
            .map { BreakdownItem(metric: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.metric < rhs.metric : lhs.count > rhs.count
            }
        metricCount = groupedMetrics.count

        let stepEntries = entries
            .filter {
                ($0.type ?? "").localizedCaseInsensitiveContains("steg")
                    || ($0.category ?? "").localizedCaseInsensitiveContains("steg")
            }
            .sorted { ($0.date ?? "") < ($1.date ?? "") }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        stepTrend = stepEntries.suffix(14).compactMap { entry in
            guard
                let date = entry.date.flatMap(formatter.date(from:)),
                let rawValue = entry.content?.summary.flatMap(Self.firstNumericValue)
            else {
                return nil
            }

            return TrendPoint(date: date, value: Int(rawValue.rounded()))
        }
    }

    private static func firstNumericValue(in text: String) -> Double? {
        let pattern = #"[0-9]+(?:[.,][0-9]+)?"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text)
        else {
            return nil
        }

        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }
}
