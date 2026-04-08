import Charts
import Combine
import SwiftUI

extension Notification.Name {
    static let openJournalImport = Notification.Name("openJournalImport")
}

private enum JournalMode: String, CaseIterable, Identifiable {
    case entries = "Journal"
    case digital = "Digital"
    case state = "State"
    case assessments = "Assessments"
    case importData = "Import"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .entries:
            return "doc.text"
        case .digital:
            return "sparkles.rectangle.stack"
        case .state:
            return "waveform.path.ecg"
        case .assessments:
            return "checklist"
        case .importData:
            return "square.and.arrow.down"
        }
    }
}

struct JournalView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var localModelManager: LocalModelManager

    @State private var mode: JournalMode = .entries
    @StateObject private var assessmentStore = AssessmentHistoryStore()
    @StateObject private var stateStore = StateCheckInStore()
    @State private var showingHealthKitImport = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var qrExportURL: URL?
    @StateObject private var digitalTracker = DigitalWellbeingTracker()

    var body: some View {
        Group {
            if mode == .entries {
                journalTimeline
                    .searchable(text: $documentVM.searchText, prompt: "Search entries...")
            } else if mode == .digital {
                digitalScreen
            } else if mode == .state {
                stateScreen
            } else if mode == .assessments {
                assessmentsScreen
            } else {
                importScreen
            }
        }
        .navigationTitle(profileStore.selectedProfile?.displayName ?? "Journal")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                journalModeMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                if mode == .entries, selectedProfileFileURL != nil {
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
                if mode == .entries {
                    Menu {
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
            }
        }
        .sheet(isPresented: $showingHealthKitImport) {
            HealthKitImportView()
                .environmentObject(profileStore)
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
        .onReceive(NotificationCenter.default.publisher(for: .openJournalImport)) { _ in
            mode = .importData
        }
        .task(id: profileStore.selectedProfileID) {
            assessmentStore.load(for: profileStore.selectedProfileID)
            stateStore.load(for: profileStore.selectedProfileID)
        }
        .background(AppColors.background)
    }

    private var journalTimeline: some View {
        Group {
            if hasEntries {
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
            } else {
                emptyJournalState
            }
        }
    }

    private var importScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            importIntroCard
            HealthDataBrowserView(displayMode: .embedded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
    }

    private var assessmentsScreen: some View {
        AssessmentsView(store: assessmentStore)
            .environmentObject(profileStore)
            .environmentObject(settingsVM)
            .environmentObject(localModelManager)
    }

    private var digitalScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                digitalHero
                digitalSummarySection
                mindfulPauseStudio
            }
            .padding()
        }
    }

    private var stateScreen: some View {
        StateCheckInView(store: stateStore)
            .environmentObject(profileStore)
    }

    private var journalModeMenu: some View {
        Menu {
            ForEach(JournalMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Label(item.rawValue, systemImage: item.symbolName)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.symbolName)
                    .font(.caption.weight(.bold))
                Text(mode.rawValue)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(AppColors.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.backgroundMuted)
            .clipShape(Capsule())
        }
    }

    private var emptyJournalState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textSecondary.opacity(0.5))

            Text("No journal entries yet")
                .font(.title3.weight(.bold))
                .foregroundColor(AppColors.text)

            Text("Import from 1177 or Apple Health to start building this timeline.")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 10) {
                Button {
                    mode = .importData
                } label: {
                    Label("Go to Import", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.primary)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    mode = .digital
                } label: {
                    Label("Open Digital", systemImage: "sparkles.rectangle.stack")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.backgroundMuted)
                        .foregroundColor(AppColors.text)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            Text("Digital is now its own Journal space for screen-use logging and mindful pause sessions.")
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importIntroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import into this journal")
                .font(.headline.weight(.semibold))
                .foregroundColor(AppColors.text)

            Text("Use the 1177 browser below to download your records, or pull in Apple Health data for this selected profile.")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 10) {
                Button {
                    showingHealthKitImport = true
                } label: {
                    Label("Apple Health", systemImage: "heart.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppColors.pink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    mode = .entries
                } label: {
                    Label("Back to Journal", systemImage: "doc.text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppColors.backgroundMuted)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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

    private var selectedProfileFileURL: URL? {
        profileStore.selectedProfile?.fileURL
    }

    private var hasEntries: Bool {
        !(documentVM.document?.entries.isEmpty ?? true)
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

    private var digitalHero: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Doing nothing")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.text)

                if digitalTracker.isTrackingNothing {
                    Text("Live")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.teal)
                }
            }

            Spacer()

            Text("\(digitalTracker.nothingPoints) pts")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.aiStrong)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.aiSoft)
                .clipShape(Capsule())
        }
    }

    private var digitalSummarySection: some View {
        HStack(spacing: 20) {
            minimalMetric(
                title: "Points",
                value: "\(digitalTracker.nothingPoints)"
            )
            Divider()
            minimalMetric(
                title: "Sessions",
                value: "\(digitalTracker.sessionCount)"
            )
            Divider()
            minimalMetric(
                title: "Quiet",
                value: "\(Int(digitalTracker.doingNothingMinutes.rounded()))m"
            )
        }
        .foregroundColor(AppColors.border)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    AppColors.aiSoft.opacity(0.7),
                    AppColors.card
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func minimalMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.text)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mindfulPauseStudio: some View {
        VStack(alignment: .leading, spacing: 20) {
            doingNothingStage

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(digitalTracker.isTrackingNothing ? "Next point" : "Rate")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text(digitalTracker.nextPointCountdownLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.text)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColors.backgroundMuted)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.aiStrong, AppColors.teal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, proxy.size.width * digitalTracker.progressToNextPoint))
                    }
                }
                .frame(height: 6)
            }

            HStack(spacing: 12) {
                compactMetric(
                    title: "Pending",
                    value: "\(digitalTracker.currentSessionPendingPoints)"
                )
                compactMetric(
                    title: "Rate",
                    value: "1 / 5m"
                )
            }

            Button {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                    digitalTracker.toggleDoingNothingSession()
                }
            } label: {
                Label(
                    digitalTracker.isTrackingNothing
                        ? "End session"
                        : "Start session",
                    systemImage: digitalTracker.isTrackingNothing ? "pause.fill" : "play.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundColor(.white)
                .background(digitalTracker.isTrackingNothing ? AppColors.text : AppColors.teal)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    AppColors.card,
                    AppColors.aiSoft.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.text)
            Text(title)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColors.backgroundMuted)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var doingNothingStage: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !digitalTracker.isTrackingNothing)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breath = digitalTracker.isTrackingNothing ? (sin(time * 0.85 - (.pi / 2)) + 1) / 2 : 0

            ZStack {
                if digitalTracker.isTrackingNothing {
                    Circle()
                        .stroke(AppColors.aiStrong.opacity(0.10), lineWidth: 26)
                        .frame(width: 210, height: 210)
                        .blur(radius: 10)
                        .scaleEffect(0.94 + CGFloat(breath) * 0.08)
                }

                Circle()
                    .stroke(digitalTracker.isTrackingNothing ? AppColors.teal.opacity(0.24) : AppColors.border, lineWidth: 1)
                    .frame(width: 220, height: 220)
                    .scaleEffect(digitalTracker.isTrackingNothing ? 0.98 + CGFloat(breath) * 0.08 : 1)
                    .opacity(digitalTracker.isTrackingNothing ? 0.9 - breath * 0.18 : 1)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.card,
                                AppColors.card,
                                digitalTracker.isTrackingNothing ? AppColors.aiSoft : AppColors.aiSoft.opacity(0.55)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 100
                        )
                    )
                    .frame(width: 168, height: 168)
                    .scaleEffect(0.98 + CGFloat(breath) * 0.05)
                    .shadow(
                        color: digitalTracker.isTrackingNothing ? AppColors.aiStrong.opacity(0.08) : AppColors.blue.opacity(0.04),
                        radius: 18,
                        y: 6
                    )

                VStack(spacing: 6) {
                    Text(digitalTracker.isTrackingNothing ? digitalTracker.elapsedLabel : "00:00")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColors.text)
                    Text(digitalTracker.isTrackingNothing ? "Breathe." : "Ready.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 340)
        }
    }
}

private enum DigitalUsageCategory: String, CaseIterable, Identifiable {
    case social
    case productivity
    case entertainment
    case learning
    case doingNothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .social: return "Social"
        case .productivity: return "Productivity"
        case .entertainment: return "Entertainment"
        case .learning: return "Learning"
        case .doingNothing: return "Doing Nothing"
        }
    }

    var color: Color {
        switch self {
        case .social: return AppColors.purple
        case .productivity: return AppColors.blue
        case .entertainment: return AppColors.orange
        case .learning: return AppColors.teal
        case .doingNothing: return AppColors.green
        }
    }
}

private final class DigitalWellbeingTracker: ObservableObject {
    @Published private(set) var usage: [DigitalUsageCategory: Double]
    @Published private(set) var sessionCount: Int
    @Published private(set) var nothingPoints: Int
    @Published private(set) var isTrackingNothing = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    private let usageKey = "journal.digital.usage.minutes"
    private let sessionCountKey = "journal.digital.nothing.session.count"
    private let nothingPointsKey = "journal.digital.nothing.points"
    private let nothingPointInterval: TimeInterval = 5 * 60
    private var activeStart: Date?
    private var timerCancellable: AnyCancellable?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.usage = [:]
        self.sessionCount = defaults.integer(forKey: sessionCountKey)
        self.nothingPoints = defaults.integer(forKey: nothingPointsKey)
        loadUsage()
    }

    deinit {
        timerCancellable?.cancel()
    }

    var doingNothingMinutes: Double {
        minutes(for: .doingNothing)
    }

    var currentSessionPendingPoints: Int {
        guard isTrackingNothing else { return 0 }
        return Int(elapsedSeconds / nothingPointInterval)
    }

    var progressToNextPoint: Double {
        guard isTrackingNothing else { return 0.02 }
        let remainder = elapsedSeconds.truncatingRemainder(dividingBy: nothingPointInterval)
        return max(0.02, remainder / nothingPointInterval)
    }

    var nextPointCountdownLabel: String {
        guard isTrackingNothing else { return "Start a session to earn points" }
        let remainder = elapsedSeconds.truncatingRemainder(dividingBy: nothingPointInterval)
        let remaining = remainder == 0 && elapsedSeconds >= nothingPointInterval
            ? nothingPointInterval
            : nothingPointInterval - remainder
        return "Next point in \(shortDurationLabel(seconds: remaining))"
    }

    var currentSessionRewardLabel: String {
        guard isTrackingNothing else { return "Earn 1 Nothing Point for every 5 full minutes of real downtime." }
        if currentSessionPendingPoints > 0 {
            return "This session has \(currentSessionPendingPoints) pending Nothing Point\(currentSessionPendingPoints == 1 ? "" : "s")."
        }
        return "Stay with the pause for 5 full minutes to earn your first Nothing Point."
    }

    var nothingPointsStatus: String {
        if nothingPoints == 0 {
            return "No points yet. Your first five-minute pause unlocks the first one."
        }
        if nothingPoints < 10 {
            return "You are building an early calm streak with \(nothingPoints) Nothing Point\(nothingPoints == 1 ? "" : "s")."
        }
        return "You have banked \(nothingPoints) Nothing Points by making space for quiet."
    }

    var elapsedLabel: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: elapsedSeconds) ?? "00:00:00"
    }

    func minutes(for category: DigitalUsageCategory) -> Double {
        usage[category, default: 0]
    }

    func toggleDoingNothingSession() {
        isTrackingNothing ? stopDoingNothingSession() : startDoingNothingSession()
    }

    private func startDoingNothingSession() {
        activeStart = Date()
        elapsedSeconds = 0
        isTrackingNothing = true

        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self, let activeStart else { return }
                elapsedSeconds = now.timeIntervalSince(activeStart)
            }
    }

    private func stopDoingNothingSession() {
        defer {
            timerCancellable?.cancel()
            timerCancellable = nil
            elapsedSeconds = 0
            activeStart = nil
            isTrackingNothing = false
        }

        guard let activeStart else { return }

        let duration = Date().timeIntervalSince(activeStart)
        let minutes = max(1, duration / 60)
        let awardedPoints = Int(duration / nothingPointInterval)
        usage[.doingNothing, default: 0] += minutes
        sessionCount += 1
        nothingPoints += awardedPoints
        persistUsage()
        defaults.set(sessionCount, forKey: sessionCountKey)
        defaults.set(nothingPoints, forKey: nothingPointsKey)
    }

    private func loadUsage() {
        guard let stored = defaults.dictionary(forKey: usageKey) as? [String: Double] else {
            usage = [.social: 40, .productivity: 50, .entertainment: 45, .learning: 20, .doingNothing: 10]
            persistUsage()
            return
        }

        var loaded: [DigitalUsageCategory: Double] = [:]
        for category in DigitalUsageCategory.allCases {
            loaded[category] = stored[category.rawValue, default: 0]
        }
        usage = loaded
    }

    private func persistUsage() {
        let encoded = Dictionary(uniqueKeysWithValues: usage.map { ($0.key.rawValue, $0.value) })
        defaults.set(encoded, forKey: usageKey)
    }

    private func shortDurationLabel(seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: max(1, seconds)) ?? "00:00"
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
