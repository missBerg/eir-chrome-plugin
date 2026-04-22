import Charts
import Combine
import SwiftUI

extension Notification.Name {
    static let openJournalImport = Notification.Name("openJournalImport")
}

private enum JournalMode: String, CaseIterable, Identifiable {
    case overview = "State"
    case caseFile = "Helhetsbild"
    case entries = "History"
    case digital = "Digital"
    case state = "Check-in"
    case assessments = "Assessments"
    case importData = "Import"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }

    var symbolName: String {
        switch self {
        case .overview:
            return "waveform.path.ecg"
        case .caseFile:
            return "sparkles.rectangle.stack"
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

enum JournalNavigationTarget: Equatable {
    case importData
    case checkIn
    case assessments
    case digital
}

struct JournalView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var localModelManager: LocalModelManager
    @EnvironmentObject var translationStore: JournalTranslationStore
    @EnvironmentObject var caseWikiVM: CaseWikiViewModel
    @EnvironmentObject var assessmentStore: AssessmentHistoryStore
    @EnvironmentObject var stateStore: StateCheckInStore
    @EnvironmentObject var chatThreadStore: ChatThreadStore

    @Binding private var navigationTarget: JournalNavigationTarget?

    @State private var mode: JournalMode = .overview
    @State private var showingHealthKitImport = false
    @State private var showingTranslationSheet = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var qrExportURL: URL?
    @State private var selectedJournalEntryID: String?
    @State private var healthAnalysisResult: StateHealthAnalysis?
    @State private var healthAnalysisSignature: String?
    @State private var healthAnalysisError: String?
    @State private var isBuildingHealthAnalysis = false
    @State private var pendingHealthAnalysisConsent: LLMProviderType?
    @StateObject private var digitalTracker = DigitalWellbeingTracker()

    init(navigationTarget: Binding<JournalNavigationTarget?> = .constant(nil)) {
        self._navigationTarget = navigationTarget
    }

    var body: some View {
        journalRoot
    }

    private var journalRoot: some View {
        activeModeContent
            .navigationTitle(stateNavigationTitle)
            .toolbar { journalToolbar }
            .sheet(isPresented: $showingHealthKitImport) {
                HealthKitImportView()
                    .environmentObject(profileStore)
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: shareItems)
            }
            .navigationDestination(item: $selectedJournalEntryID) { entryID in
                if let entry = documentVM.document?.entries.first(where: { $0.id == entryID }) {
                    EntryDetailView(entry: entry)
                }
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
                openNavigationTarget(.importData)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToJournalEntry)) { notification in
                if let entryID = notification.object as? String {
                    openJournalEntry(entryID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToAssessments)) { _ in
                openNavigationTarget(.assessments)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToCheckIn)) { _ in
                openNavigationTarget(.checkIn)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToDigital)) { _ in
                openNavigationTarget(.digital)
            }
            .onAppear {
                if let navigationTarget {
                    openNavigationTarget(navigationTarget)
                }
            }
            .onChange(of: navigationTarget) {
                if let navigationTarget {
                    openNavigationTarget(navigationTarget)
                }
            }
            .onChange(of: documentVM.selectedEntryID) {
                openJournalEntry(documentVM.selectedEntryID)
            }
            .task(id: profileStore.selectedProfileID) {
                assessmentStore.load(for: profileStore.selectedProfileID)
                stateStore.load(for: profileStore.selectedProfileID)
                translationStore.load(for: profileStore.selectedProfileID)
            }
            .task(id: caseWikiSyncID) {
                caseWikiVM.loadAndSync(
                    profileID: profileStore.selectedProfileID,
                    document: documentVM.document
                )
                await caseWikiVM.autoBuildIfAllowed(
                    profileID: profileStore.selectedProfileID,
                    document: documentVM.document,
                    settingsVM: settingsVM,
                    localModelManager: localModelManager
                )
            }
            .task(id: healthAnalysisInputSignature) {
                healthAnalysisResult = nil
                healthAnalysisError = nil
                guard hasStateInputs else { return }
                guard let provider = settingsVM.activeProvider else { return }
                if provider.type.isLocal || ChatViewModel.hasCloudConsent(for: provider.type) {
                    await buildHealthAnalysis(requestConsentIfNeeded: false)
                }
            }
            .alert(
                "Share Data with \(caseWikiVM.pendingCloudConsent?.displayName ?? "Cloud Provider")?",
                isPresented: Binding(
                    get: { caseWikiVM.pendingCloudConsent != nil },
                    set: { if !$0 { caseWikiVM.denyConsent() } }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    caseWikiVM.denyConsent()
                }
                Button("I Agree") {
                    Task {
                        await caseWikiVM.grantConsentAndBuild(
                            profileID: profileStore.selectedProfileID,
                            document: documentVM.document,
                            settingsVM: settingsVM,
                            localModelManager: localModelManager
                        )
                    }
                }
            } message: {
                Text("Eir will send compact, source-linked summaries of your imported records to the selected AI provider to build your Patient Case Wiki. Raw records stay stored locally in Eir.")
            }
            .alert(
                "Share Data with \(pendingHealthAnalysisConsent?.displayName ?? "Cloud Provider")?",
                isPresented: Binding(
                    get: { pendingHealthAnalysisConsent != nil },
                    set: { if !$0 { pendingHealthAnalysisConsent = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    pendingHealthAnalysisConsent = nil
                }
                Button("I Agree") {
                    Task {
                        let provider = pendingHealthAnalysisConsent
                        pendingHealthAnalysisConsent = nil
                        if let provider {
                            ChatViewModel.grantCloudConsent(for: provider)
                        }
                        await buildHealthAnalysis(requestConsentIfNeeded: false)
                    }
                }
            } message: {
                Text("Eir will send a compact summary of your EHR, assessments, current chat, and check-ins to generate the Health Analysis score. On-device models keep this on your phone.")
            }
            .safeAreaInset(edge: .top) {
                if translationStore.isTranslating {
                    translationProgressBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            .background(AppColors.background)
    }

    private var activeModeContent: AnyView {
        switch mode {
        case .overview:
            return AnyView(stateOverviewScreen)
        case .caseFile:
            return AnyView(caseWikiScreen)
        case .entries:
            return AnyView(
                journalTimeline
                    .searchable(text: $documentVM.searchText, prompt: "Search entries...")
            )
        case .digital:
            return AnyView(digitalScreen)
        case .state:
            return AnyView(stateScreen)
        case .assessments:
            return AnyView(assessmentsScreen)
        case .importData:
            return AnyView(importScreen)
        }
    }

    @ToolbarContentBuilder
    private var journalToolbar: some ToolbarContent {
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
            if mode == .entries, hasEntries {
                Button {
                    showingTranslationSheet = true
                } label: {
                    Image(systemName: "globe")
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

    private var journalTimeline: some View {
        Group {
            if hasEntries {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !translationStore.availableLanguages(for: documentVM.filteredEntries).isEmpty {
                            translationDisplayControls
                        }

                        if let summary = appleHealthSummary {
                            appleHealthOverview(summary)
                        }

                        ForEach(documentVM.groupedEntries, id: \.key) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    Button {
                                        selectedJournalEntryID = entry.id
                                    } label: {
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
                .sheet(isPresented: $showingTranslationSheet) {
                    HistoryTranslationSheet(entries: documentVM.filteredEntries)
                        .environmentObject(settingsVM)
                        .environmentObject(localModelManager)
                        .environmentObject(translationStore)
                }
            } else {
                emptyJournalState
            }
        }
    }

    private var translationDisplayControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                translationDisplayChip(title: "Original", isSelected: translationStore.selectedLanguage == nil) {
                    translationStore.setSelectedLanguage(nil)
                }

                ForEach(translationStore.availableLanguages(for: documentVM.filteredEntries), id: \.self) { language in
                    translationDisplayChip(title: language.displayName, isSelected: translationStore.selectedLanguage == language) {
                        translationStore.setSelectedLanguage(language)
                    }
                }
            }
        }
    }

    private func translationDisplayChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : AppColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? AppColors.primary : AppColors.backgroundMuted)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var stateOverviewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stateOverviewHero

                if hasStateInputs {
                    stateHealthAnalysisSection
                    stateCurrentSection
                    stateSignalsSection
                    statePatternSection
                } else {
                    stateBootstrapSection
                }
            }
            .padding()
        }
    }

    private var translationProgressBanner: some View {
        Button {
            showingTranslationSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Translating history")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.text)

                    if translationStore.totalEntries > 0 {
                        Text("\(translationStore.currentEntryIndex) of \(translationStore.totalEntries)")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer()

                ProgressView(value: translationStore.progress)
                    .tint(AppColors.primary)
                    .frame(width: 72)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var importScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            importIntroCard
            HealthDataBrowserView()
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

    private var caseWikiScreen: some View {
        CaseWikiOverviewView(
            wiki: caseWikiVM.wiki,
            isBuilding: caseWikiVM.isBuilding,
            progress: caseWikiVM.progress,
            statusMessage: caseWikiVM.statusMessage,
            errorMessage: caseWikiVM.errorMessage,
            needsRebuild: caseWikiVM.needsRebuild,
            onBuild: {
                Task {
                    await buildCaseWiki()
                }
            },
            onOpenEntry: { entryID in
                NotificationCenter.default.post(name: .navigateToJournalEntry, object: entryID)
            }
        )
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
                    Label(item.localizedTitle, systemImage: item.symbolName)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.symbolName)
                    .font(.caption.weight(.bold))
                Text(mode.localizedTitle)
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

    private var caseWikiSyncID: String {
        let profilePart = profileStore.selectedProfileID?.uuidString ?? "none"
        let documentPart = documentVM.document.map { CaseSourceCardBuilder.documentSignature(for: $0) } ?? "none"
        let providerPart = settingsVM.activeProviderType.rawValue
        return "\(profilePart)-\(documentPart)-\(providerPart)"
    }

    private func buildCaseWiki() async {
        await caseWikiVM.build(
            profileID: profileStore.selectedProfileID,
            document: documentVM.document,
            settingsVM: settingsVM,
            localModelManager: localModelManager
        )
    }

    private func buildHealthAnalysis(requestConsentIfNeeded: Bool) async {
        guard hasStateInputs else {
            healthAnalysisError = "Add a check-in, assessment, chat, or health record before running analysis."
            return
        }
        guard let provider = settingsVM.activeProvider else {
            healthAnalysisError = "Choose an AI provider in Settings before running Health Analysis."
            return
        }
        if !provider.type.isLocal && !ChatViewModel.hasCloudConsent(for: provider.type) {
            if requestConsentIfNeeded {
                pendingHealthAnalysisConsent = provider.type
            }
            return
        }
        if isBuildingHealthAnalysis { return }

        isBuildingHealthAnalysis = true
        healthAnalysisError = nil
        let signature = healthAnalysisInputSignature

        do {
            let analysis = try await StateHealthAnalysisEngine.generate(
                document: documentVM.document,
                assessmentRecords: assessmentStore.records,
                stateRecords: stateStore.records,
                chatMessages: chatThreadStore.messages,
                settingsVM: settingsVM,
                localModelManager: localModelManager
            )
            healthAnalysisResult = analysis
            healthAnalysisSignature = signature
        } catch {
            healthAnalysisError = error.localizedDescription
        }

        isBuildingHealthAnalysis = false
    }

    private func openJournalEntry(_ entryID: String?) {
        guard let entryID,
              documentVM.document?.entries.contains(where: { $0.id == entryID }) == true
        else { return }

        mode = .entries
        selectedJournalEntryID = entryID

        if documentVM.selectedEntryID != nil {
            documentVM.selectedEntryID = nil
        }
    }

    private func openNavigationTarget(_ target: JournalNavigationTarget) {
        switch target {
        case .importData:
            mode = .importData
        case .checkIn:
            mode = .state
        case .assessments:
            mode = .assessments
        case .digital:
            mode = .digital
        }

        if navigationTarget == target {
            navigationTarget = nil
        }
    }

    private var emptyJournalState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textSecondary.opacity(0.5))

            Text("No history yet")
                .font(.title3.weight(.bold))
                .foregroundColor(AppColors.text)

            Text("State can still start with a check-in, assessment, or quiet session before you import records.")
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

            Text("Digital is one of the signal sources inside State, alongside check-ins, assessments, and imported health data.")
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
            Text("Import into State")
                .font(.headline.weight(.semibold))
                .foregroundColor(AppColors.text)

            Text("Bring in 1177 records or Apple Health data to enrich the state view with more signals and more history.")
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
                    mode = .overview
                } label: {
                    Label("Back to State", systemImage: "waveform.path.ecg")
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

    private var latestStateRecord: StateCheckInRecord? {
        stateStore.records.first
    }

    private var hasStateInputs: Bool {
        latestStateRecord != nil
            || !assessmentStore.records.isEmpty
            || hasEntries
            || appleHealthSummary != nil
            || chatThreadStore.messages.contains { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || digitalTracker.sessionCount > 0
            || digitalTracker.doingNothingMinutes > 0
    }

    private var stateSignalCount: Int {
        [
            latestStateRecord != nil,
            !assessmentStore.records.isEmpty,
            hasEntries,
            chatThreadStore.messages.contains { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            appleHealthSummary != nil,
            digitalTracker.sessionCount > 0 || digitalTracker.doingNothingMinutes > 0
        ]
        .filter { $0 }
        .count
    }

    private var healthAnalysis: StateHealthAnalysis {
        healthAnalysisResult ?? StateHealthAnalysisEngine.ready(
            document: documentVM.document,
            assessmentRecords: assessmentStore.records,
            stateRecords: stateStore.records,
            chatMessages: chatThreadStore.messages
        )
    }

    private var healthAnalysisInputSignature: String {
        StateHealthAnalysisEngine.signature(
            document: documentVM.document,
            assessmentRecords: assessmentStore.records,
            stateRecords: stateStore.records,
            chatMessages: chatThreadStore.messages,
            providerType: settingsVM.activeProviderType
        )
    }

    private var stateOverviewHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Understand your state.")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)

            Text("State brings together check-ins, assessments, imported records, Apple Health, and digital patterns so Eir can learn what improves your health.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                summaryTile(title: "Check-ins", value: "\(stateStore.records.count)", tint: AppColors.teal)
                summaryTile(title: "Assessments", value: "\(assessmentStore.records.count)", tint: AppColors.orange)
                summaryTile(title: "Signals", value: "\(stateSignalCount)", tint: AppColors.primary)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "F0FDFA"),
                    Color(hex: "EFF6FF"),
                    AppColors.card
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var stateHealthAnalysisSection: some View {
        let analysis = healthAnalysis

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                healthScoreDial(score: analysis.score)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Health Analysis")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColors.text)

                        if analysis.isLLMGenerated {
                            Image(systemName: "sparkles")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.primary)
                        }
                    }

                    Text(analysis.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(analysis.tint)

                    Text(analysis.summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isBuildingHealthAnalysis {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(AppColors.primary)
                    Text("LLM is scoring your state")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            if let healthAnalysisError {
                Text(healthAnalysisError)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColors.pink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(analysis.sources) { source in
                    healthSourceChip(source)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(analysis.reasons, id: \.self) { reason in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 20, height: 20)
                        Text(reason)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await buildHealthAnalysis(requestConsentIfNeeded: true)
                    }
                } label: {
                    Label(analysis.isLLMGenerated ? "Refresh Analysis" : "Run Analysis", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isBuildingHealthAnalysis ? AppColors.textSecondary : AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBuildingHealthAnalysis)

                stateShortcutButton(title: "Update Check-In", systemImage: "waveform.path.ecg", mode: .state, fill: AppColors.teal)
            }
        }
        .padding(20)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func healthScoreDial(score: Int?) -> some View {
        let progress = score.map { Double($0) / 100 } ?? 0

        return ZStack {
            Circle()
                .stroke(AppColors.backgroundMuted, lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    healthScoreTint(score: score ?? 0),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                Text("/100")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(width: 86, height: 86)
        .accessibilityLabel(score.map { "Health analysis score \($0) out of 100" } ?? "Health analysis score not generated yet")
    }

    private func healthSourceChip(_ source: StateHealthAnalysisSource) -> some View {
        HStack(spacing: 9) {
            Image(systemName: source.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(source.isActive ? AppColors.primary : AppColors.textSecondary)
                .frame(width: 24, height: 24)
                .background((source.isActive ? AppColors.primarySoft : AppColors.backgroundMuted).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.text)
                Text(source.detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.backgroundMuted.opacity(source.isActive ? 0.7 : 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func healthScoreTint(score: Int) -> Color {
        switch score {
        case ..<45:
            return AppColors.pink
        case ..<65:
            return AppColors.orange
        case ..<80:
            return AppColors.teal
        default:
            return AppColors.primary
        }
    }

    private var stateCurrentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.text)

            VStack(alignment: .leading, spacing: 14) {
                if let latestStateRecord {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest check-in")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.teal)
                        Text(latestStateRecord.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppColors.text)
                        Text("Top signals: \(latestStateRecord.topHighlights.joined(separator: ", "))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.textSecondary)
                        if !latestStateRecord.note.isEmpty {
                            Text(latestStateRecord.note)
                                .font(.subheadline)
                                .foregroundStyle(AppColors.text)
                                .lineLimit(3)
                        } else if !latestStateRecord.reflection.isEmpty {
                            Text(latestStateRecord.reflection)
                                .font(.subheadline)
                                .foregroundStyle(AppColors.text)
                                .lineLimit(3)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No state snapshot yet")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppColors.text)
                        Text("Start with one honest check-in. Eir can begin learning from a single snapshot.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    stateShortcutButton(title: "Check in", systemImage: "waveform.path.ecg", mode: .state, fill: AppColors.teal)
                    stateShortcutButton(title: "Assess", systemImage: "checklist", mode: .assessments, fill: AppColors.orange)
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
    }

    private var stateSignalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signals")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.text)

            VStack(spacing: 12) {
                stateSignalRow(
                    title: "EHR",
                    value: "\(documentVM.document?.entries.count ?? 0) entries",
                    summary: hasEntries ? "Imported records are available for context and trend spotting." : "No imported record history yet.",
                    systemImage: "doc.text",
                    targetMode: .entries
                )

                stateSignalRow(
                    title: "Helhetsbild",
                    value: caseWikiVM.wiki == nil ? "Not built" : "\(caseWikiVM.wiki?.pages.count ?? 0) pages",
                    summary: caseWikiVM.wiki == nil ? "Compile records into a source-cited patient case wiki." : "A maintained case wiki is ready for chat and visit preparation.",
                    systemImage: "sparkles.rectangle.stack",
                    targetMode: .caseFile
                )

                stateSignalRow(
                    title: "Assessments",
                    value: "\(assessmentStore.records.count) saved",
                    summary: assessmentStore.records.isEmpty ? "Structured self-checks can help bootstrap your state." : "Assessment results are ready to compare over time.",
                    systemImage: "checklist",
                    targetMode: .assessments
                )

                stateSignalRow(
                    title: "Chat",
                    value: "\(chatThreadStore.messages.filter { $0.role == .user }.count) notes",
                    summary: chatThreadStore.messages.contains { $0.role == .user } ? "Recent chat context is included in the health analysis." : "Talk with Eir to add conversational context.",
                    systemImage: "bubble.left.and.bubble.right",
                    targetMode: .overview
                )

                stateSignalRow(
                    title: "Digital",
                    value: "\(digitalTracker.nothingPoints) pts",
                    summary: digitalTracker.sessionCount == 0 ? "Quiet sessions can become one of your first reward signals." : "\(digitalTracker.sessionCount) quiet sessions logged so far.",
                    systemImage: "sparkles.rectangle.stack",
                    targetMode: .digital
                )

                stateSignalRow(
                    title: "Import",
                    value: appleHealthSummary == nil ? "Ready" : "Connected",
                    summary: appleHealthSummary == nil ? "Add Apple Health or 1177 data when you want richer passive signals." : "Apple Health is already feeding passive signals into State.",
                    systemImage: "square.and.arrow.down",
                    targetMode: .importData
                )
            }
        }
    }

    private var statePatternSection: some View {
        let insights = statePatternInsights

        return VStack(alignment: .leading, spacing: 12) {
            Text("Patterns")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.text)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(insights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(AppColors.primarySoft)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AppColors.primary)
                            }
                        Text(insight)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)
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
    }

    private var stateBootstrapSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build your state")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.text)

            Text("You can bootstrap Eir without any imported health data. Start with a check-in, try an assessment, or log a quiet session and let the loop begin.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                statePrimaryButton(title: "Start a check-in", systemImage: "waveform.path.ecg", mode: .state, fill: AppColors.teal)
                statePrimaryButton(title: "Try an assessment", systemImage: "checklist", mode: .assessments, fill: AppColors.orange)
                statePrimaryButton(title: "Open Digital", systemImage: "sparkles.rectangle.stack", mode: .digital, fill: AppColors.aiStrong)
                statePrimaryButton(title: "Import signals", systemImage: "square.and.arrow.down", mode: .importData, fill: AppColors.primary)
            }
        }
        .padding(22)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var statePatternInsights: [String] {
        var insights: [String] = []

        if stateStore.records.count >= 3 {
            insights.append("You have \(stateStore.records.count) state check-ins saved, which is enough to start noticing day-to-day changes.")
        } else if stateStore.records.count > 0 {
            insights.append("Your first state snapshots are in place. A few more check-ins will make patterns easier to spot.")
        }

        if !assessmentStore.records.isEmpty {
            insights.append("Assessments are giving you more structured signal than a freeform note alone, which strengthens the State layer.")
        }

        if appleHealthSummary != nil {
            insights.append("Apple Health is adding passive signals, so State is no longer relying only on self-report.")
        }

        if digitalTracker.sessionCount > 0 || digitalTracker.nothingPoints > 0 {
            insights.append("Quiet sessions are already feeding the reward loop with Nothing Points and calm-time history.")
        }

        if insights.isEmpty {
            insights.append("As you add check-ins, assessments, quiet sessions, and imported records, Eir will get better at linking state to what helps.")
        }

        return insights
    }

    private func stateSignalRow(
        title: String,
        value: String,
        summary: String,
        systemImage: String,
        targetMode: JournalMode
    ) -> some View {
        Button {
            mode = targetMode
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 40, height: 40)
                    .background(AppColors.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                    Text(value)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.primary)
                    Text(summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func stateShortcutButton(title: String, systemImage: String, mode: JournalMode, fill: Color) -> some View {
        Button {
            self.mode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statePrimaryButton(title: String, systemImage: String, mode: JournalMode, fill: Color) -> some View {
        Button {
            self.mode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectedProfileFileURL: URL? {
        profileStore.selectedProfile?.fileURL
    }

    private var stateNavigationTitle: String {
        guard let name = profileStore.selectedProfile?.displayName else { return "State" }
        return name.localizedCaseInsensitiveContains("sample") ? "Sample Data" : name
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

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
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

            if !summary.recentClinicalNotes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent clinical notes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.text)

                    VStack(spacing: 10) {
                        ForEach(summary.recentClinicalNotes) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(note.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(AppColors.text)
                                        .lineLimit(2)
                                    Spacer()
                                    if let date = note.date {
                                        Text(date)
                                            .font(.caption)
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                }

                                if let preview = note.preview, !preview.isEmpty {
                                    Text(preview)
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                        .lineLimit(3)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(AppColors.backgroundMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
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
    private static let placeholderUsage: [DigitalUsageCategory: Double] = [
        .social: 40,
        .productivity: 50,
        .entertainment: 45,
        .learning: 20,
        .doingNothing: 10
    ]

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
            usage = Dictionary(uniqueKeysWithValues: DigitalUsageCategory.allCases.map { ($0, 0) })
            return
        }

        var loaded: [DigitalUsageCategory: Double] = [:]
        for category in DigitalUsageCategory.allCases {
            loaded[category] = stored[category.rawValue, default: 0]
        }

        // Migrate away from the old placeholder seed data so users start from real quiet-time history.
        if loaded == Self.placeholderUsage && sessionCount == 0 && nothingPoints == 0 {
            usage = Dictionary(uniqueKeysWithValues: DigitalUsageCategory.allCases.map { ($0, 0) })
            persistUsage()
            return
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

private struct StateHealthAnalysis {
    let score: Int?
    let label: String
    let summary: String
    let reasons: [String]
    let sources: [StateHealthAnalysisSource]
    let isLLMGenerated: Bool

    var tint: Color {
        guard let score else { return AppColors.textSecondary }
        switch score {
        case ..<45:
            return AppColors.pink
        case ..<65:
            return AppColors.orange
        case ..<80:
            return AppColors.teal
        default:
            return AppColors.primary
        }
    }
}

private struct StateHealthAnalysisSource: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let isActive: Bool
}

private enum StateHealthAnalysisEngine {
    static func ready(
        document: EirDocument?,
        assessmentRecords: [AssessmentRecord],
        stateRecords: [StateCheckInRecord],
        chatMessages: [ChatMessage]
    ) -> StateHealthAnalysis {
        StateHealthAnalysis(
            score: nil,
            label: "Ready for LLM scoring",
            summary: "Run analysis to let the selected model score your current health signal from the available sources.",
            reasons: [
                "The score is generated by the LLM from a compact source summary, not by a fixed local formula.",
                "More recent check-ins and varied assessments make the analysis more useful."
            ],
            sources: sources(
                document: document,
                assessmentRecords: assessmentRecords,
                stateRecords: stateRecords,
                chatMessages: chatMessages
            ),
            isLLMGenerated: false
        )
    }

    @MainActor
    static func generate(
        document: EirDocument?,
        assessmentRecords: [AssessmentRecord],
        stateRecords: [StateCheckInRecord],
        chatMessages: [ChatMessage],
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async throws -> StateHealthAnalysis {
        let raw = try await complete(
            systemPrompt: systemPrompt,
            userPrompt: buildPrompt(
                document: document,
                assessmentRecords: assessmentRecords,
                stateRecords: stateRecords,
                chatMessages: chatMessages
            ),
            settingsVM: settingsVM,
            localModelManager: localModelManager
        )

        let decoded = try decode(raw)
        return StateHealthAnalysis(
            score: decoded.score,
            label: decoded.label.isEmpty ? label(for: decoded.score) : decoded.label,
            summary: decoded.summary.isEmpty ? "The LLM scored your current health signal from the sources shown below." : decoded.summary,
            reasons: decoded.reasons.isEmpty ? ["LLM analysis completed from the available State sources."] : Array(decoded.reasons.prefix(4)),
            sources: sources(
                document: document,
                assessmentRecords: assessmentRecords,
                stateRecords: stateRecords,
                chatMessages: chatMessages
            ),
            isLLMGenerated: true
        )
    }

    static func signature(
        document: EirDocument?,
        assessmentRecords: [AssessmentRecord],
        stateRecords: [StateCheckInRecord],
        chatMessages: [ChatMessage],
        providerType: LLMProviderType
    ) -> String {
        let entryHead = document?.entries.prefix(8).map(\.id).joined(separator: "|") ?? "none"
        let assessmentHead = assessmentRecords.prefix(8).map { "\($0.id.uuidString):\($0.completedAt.timeIntervalSince1970)" }.joined(separator: "|")
        let stateHead = stateRecords.prefix(8).map { "\($0.id.uuidString):\($0.createdAt.timeIntervalSince1970)" }.joined(separator: "|")
        let chatHead = chatMessages.suffix(8).map { "\($0.id.uuidString):\($0.timestamp.timeIntervalSince1970):\($0.content.count)" }.joined(separator: "|")
        return "\(providerType.rawValue)|\(document?.entries.count ?? 0)|\(entryHead)|\(assessmentRecords.count)|\(assessmentHead)|\(stateRecords.count)|\(stateHead)|\(chatHead)"
    }

    private static var systemPrompt: String {
        """
        You are Eir's Health Analysis model.
        Score the user's current health signal from 0 to 100 using only the supplied source summaries: EHR, assessments, chat, and check-ins.
        The score should reflect current overall wellbeing and health stability, not moral worth and not a diagnosis.
        Be calibrated: sparse or old data should lower confidence and avoid extreme scores.
        Explain the score with concise evidence-based reasons.
        Return only JSON with this exact shape:
        {
          "score": 0,
          "label": "short status label",
          "summary": "one sentence motivation",
          "reasons": ["reason one", "reason two", "reason three"]
        }
        """
    }

    @MainActor
    private static func complete(
        systemPrompt: String,
        userPrompt: String,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async throws -> String {
        guard let config = settingsVM.activeProvider else {
            throw LLMError.noProvider
        }

        if config.type.isLocal {
            try await localModelManager.ensurePreferredModelLoaded()
            return try await localModelManager.service.completeDetachedResponse(
                userMessage: userPrompt,
                systemPrompt: systemPrompt
            )
        }

        let credential = try await settingsVM.resolvedCredential(for: config)
        let service = LLMService(config: config, apiKey: credential)
        return try await service.completeChat(messages: [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ])
    }

    private static func buildPrompt(
        document: EirDocument?,
        assessmentRecords: [AssessmentRecord],
        stateRecords: [StateCheckInRecord],
        chatMessages: [ChatMessage]
    ) -> String {
        """
        Source coverage:
        \(sources(document: document, assessmentRecords: assessmentRecords, stateRecords: stateRecords, chatMessages: chatMessages).map { "- \($0.title): \($0.detail)" }.joined(separator: "\n"))

        EHR summary:
        \(ehrSummary(document))

        Assessment summary:
        \(assessmentSummary(assessmentRecords))

        Check-In summary:
        \(stateSummary(stateRecords))

        Chat summary:
        \(chatSummary(chatMessages))

        Generate the 0-100 Health Analysis score now. Mention uncertainty when the available sources are thin, old, or one-sided.
        """
    }

    private static func sources(
        document: EirDocument?,
        assessmentRecords: [AssessmentRecord],
        stateRecords: [StateCheckInRecord],
        chatMessages: [ChatMessage]
    ) -> [StateHealthAnalysisSource] {
        let userChatCount = chatMessages.filter { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return [
            StateHealthAnalysisSource(
                id: "ehr",
                title: "EHR",
                detail: document.map { "\($0.entries.count) entries" } ?? "Not connected",
                systemImage: "doc.text",
                isActive: !(document?.entries.isEmpty ?? true)
            ),
            StateHealthAnalysisSource(
                id: "assessments",
                title: "Assessments",
                detail: assessmentRecords.isEmpty ? "No saved results" : "\(assessmentRecords.count) saved",
                systemImage: "checklist",
                isActive: !assessmentRecords.isEmpty
            ),
            StateHealthAnalysisSource(
                id: "chat",
                title: "Chat",
                detail: userChatCount == 0 ? "No recent notes" : "\(userChatCount) user notes",
                systemImage: "bubble.left.and.bubble.right",
                isActive: userChatCount > 0
            ),
            StateHealthAnalysisSource(
                id: "check_in",
                title: "Check-In",
                detail: stateRecords.isEmpty ? "No snapshots" : "\(stateRecords.count) snapshots",
                systemImage: "waveform.path.ecg",
                isActive: !stateRecords.isEmpty
            )
        ]
    }

    private static func ehrSummary(_ document: EirDocument?) -> String {
        guard let document, !document.entries.isEmpty else { return "No EHR entries supplied." }

        let entries = document.entries
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return (lhs.time ?? "") > (rhs.time ?? "") }
                return (lhs.date ?? "") > (rhs.date ?? "")
            }
            .prefix(12)
            .map { entry in
                let text = [
                    entry.content?.summary,
                    entry.content?.details,
                    entry.content?.notes?.joined(separator: " ")
                ]
                .compactMap { $0 }
                .joined(separator: " ")
                return "- \(entry.date ?? "Unknown date") \(entry.category ?? entry.type ?? "Entry"): \(truncate(text, limit: 260))"
            }
            .joined(separator: "\n")

        return "Total entries: \(document.entries.count)\nRecent entries:\n\(entries)"
    }

    private static func assessmentSummary(_ records: [AssessmentRecord]) -> String {
        guard !records.isEmpty else { return "No assessment results supplied." }

        return records
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(8)
            .map { record in
                let overall = record.overall.map { "\($0.label): \($0.band.label), score \($0.formattedScore). \($0.band.resolvedDescription)" } ?? "No overall score."
                let dimensions = record.dimensions
                    .prefix(4)
                    .map { "\($0.label) \($0.band.label)" }
                    .joined(separator: ", ")
                return "- \(record.completedAt.formatted(date: .abbreviated, time: .shortened)) \(assessmentName(record.assessmentID)): \(overall) Dimensions: \(dimensions)"
            }
            .joined(separator: "\n")
    }

    private static func stateSummary(_ records: [StateCheckInRecord]) -> String {
        guard !records.isEmpty else { return "No check-ins supplied." }

        return records
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)
            .map { record in
                let level = stateLevel(scores: record.scores)
                let highlights = record.topHighlights.joined(separator: ", ")
                let note = record.note.isEmpty ? record.reflection : record.note
                return "- \(record.createdAt.formatted(date: .abbreviated, time: .shortened)): \(level)/10; highlights: \(highlights). Note: \(truncate(note, limit: 220))"
            }
            .joined(separator: "\n")
    }

    private static func chatSummary(_ messages: [ChatMessage]) -> String {
        let userMessages = messages
            .filter { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(8)

        guard !userMessages.isEmpty else { return "No current chat messages supplied." }

        return userMessages
            .map { "- \($0.timestamp.formatted(date: .abbreviated, time: .shortened)): \(truncate($0.content, limit: 220))" }
            .joined(separator: "\n")
    }

    private static func decode(_ raw: String) throws -> DecodedAnalysis {
        let candidate = extractJSONObject(from: raw)
        guard let data = candidate.data(using: .utf8) else {
            throw LLMError.invalidResponse
        }

        do {
            let payload = try JSONDecoder().decode(AnalysisPayload.self, from: data)
            return DecodedAnalysis(
                score: max(0, min(100, payload.score)),
                label: payload.label.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: payload.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                reasons: payload.reasons
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        } catch {
            throw LLMError.requestFailed("The Health Analysis response was not readable. Try again or switch models.")
        }
    }

    private static func extractJSONObject(from raw: String) -> String {
        let withoutCodeFences = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = withoutCodeFences.firstIndex(of: "{"),
           let end = withoutCodeFences.lastIndex(of: "}") {
            return String(withoutCodeFences[start...end])
        }
        return withoutCodeFences
    }

    private static func label(for score: Int) -> String {
        switch score {
        case ..<45:
            return "Needs attention"
        case ..<65:
            return "Mixed signal"
        case ..<80:
            return "Fairly steady"
        default:
            return "Strong signal"
        }
    }

    private static func stateLevel(scores: [String: Double]) -> Int {
        let contributions = StateDimensionDefinition.catalog.map { dimension in
            let score = scores[dimension.id] ?? 0.5
            return dimension.highIsPositive ? score : (1 - score)
        }
        let average = contributions.reduce(0, +) / Double(contributions.count)
        return Int(round(average * 10))
    }

    private static func assessmentName(_ id: String) -> String {
        id
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed.isEmpty ? "No text." : trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end]) + "..."
    }

    private struct AnalysisPayload: Decodable {
        let score: Int
        let label: String
        let summary: String
        let reasons: [String]
    }

    private struct DecodedAnalysis {
        let score: Int
        let label: String
        let summary: String
        let reasons: [String]
    }
}

private struct AppleHealthSummary {
    struct BreakdownItem {
        let metric: String
        let count: Int
    }

    struct ClinicalNoteItem: Identifiable {
        let id: String
        let title: String
        let preview: String?
        let date: String?
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
    let recentClinicalNotes: [ClinicalNoteItem]
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

        recentClinicalNotes = entries
            .filter(\.isClinicalNote)
            .sorted {
                if $0.date == $1.date {
                    return ($0.time ?? "") > ($1.time ?? "")
                }
                return ($0.date ?? "") > ($1.date ?? "")
            }
            .prefix(3)
            .map { entry in
                ClinicalNoteItem(
                    id: entry.id,
                    title: entry.content?.summary ?? entry.type ?? "Klinisk anteckning",
                    preview: entry.notePreviewText,
                    date: entry.date
                )
            }

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
