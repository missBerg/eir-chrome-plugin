import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var chatThreadStore: ChatThreadStore
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var agentMemoryStore: AgentMemoryStore
    @EnvironmentObject var localModelManager: LocalModelManager
    @EnvironmentObject var caseWikiVM: CaseWikiViewModel

    @State private var showOnboarding = false
    @State private var showConversations = false
    @State private var showDictation = false
    @State private var showDataSources = false
    @State private var showRecordSelection = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                dataSourceBanner

                if chatThreadStore.messages.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 18) {
                                ForEach(chatThreadStore.messages.filter { $0.role != .tool }) { message in
                                    ChatBubbleView(
                                        message: message,
                                        onFollowUpTap: { followUp in
                                            sendSuggestedPrompt(followUp)
                                        }
                                    )
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 24)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: chatThreadStore.messages.count) { _, _ in
                            if let last = chatThreadStore.messages.last(where: { $0.role != .tool }) {
                                withAnimation(.easeOut(duration: 0.22)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                if let error = chatVM.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppColors.red)
                        Spacer()
                        Button("Dismiss") {
                            chatVM.errorMessage = nil
                        }
                        .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.red.opacity(0.06))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .navigationTitle("Eir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showDataSources = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Choose Chat Data Sources")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showConversations = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }

                    Button {
                        if let profileID = profileStore.selectedProfileID {
                            chatVM.newConversation(
                                chatThreadStore: chatThreadStore,
                                profileID: profileID
                            )
                        }
                    } label: {
                        Image(systemName: "plus.bubble")
                    }
                }
            }
        }
        .sheet(isPresented: $showConversations) {
            ConversationListSheet()
        }
        .sheet(isPresented: $showDataSources) {
            ChatDataSourcesSheet(
                selectedProfile: profileStore.selectedProfile,
                document: documentVM.document,
                recordsEnabled: recordsEnabled,
                selectedRecordCount: selectedRecordCount,
                onToggleRecords: { enabled in
                    guard let profileID = profileStore.selectedProfileID else { return }
                    profileStore.setUseRecordsInChat(enabled, for: profileID)
                },
                onManageRecords: {
                    showDataSources = false
                    showRecordSelection = true
                }
            )
        }
        .sheet(isPresented: $showRecordSelection) {
            ChatRecordSelectionSheet()
                .environmentObject(documentVM)
                .environmentObject(profileStore)
        }
        .sheet(isPresented: $showDictation) {
            VoiceNoteComposerSheet(title: "Voice Note") { draft in
                Task {
                    await sendVoiceNote(draft)
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                agentMemoryStore: agentMemoryStore,
                profile: profileStore.selectedProfile
            )
        }
        .onAppear {
            if agentMemoryStore.isOnboardingNeeded {
                showOnboarding = true
            }
        }
        .alert(
            "Share Data with \(chatVM.pendingCloudConsent?.displayName ?? "Cloud Provider")?",
            isPresented: Binding(
                get: { chatVM.pendingCloudConsent != nil },
                set: { if !$0 { chatVM.consentDenied() } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                chatVM.consentDenied()
            }
            Button("I Agree") {
                chatVM.consentGrantedAndSend()
            }
        } message: {
            Text("Your medical records and conversation will be sent to \(chatVM.pendingCloudConsent?.displayName ?? "the selected provider") for AI processing. This data may include personal health information. The provider's privacy policy applies. On-device models keep all data on your phone.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(AppColors.primaryStrong)
                    .frame(width: 64, height: 64)
                    .background(AppColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text("How can Eir help?")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(AppColors.text)

                Text(emptyStateSubtitle)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            VStack(spacing: 10) {
                ForEach(suggestedPrompts, id: \.self) { prompt in
                    Button {
                        sendSuggestedPrompt(prompt)
                    } label: {
                        HStack {
                            Text(prompt)
                                .font(.subheadline)
                                .foregroundColor(AppColors.text)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(AppColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.background.opacity(0), AppColors.background.opacity(0.92), AppColors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 18)

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    showDictation = true
                } label: {
                    Image(systemName: "waveform")
                        .font(.headline)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(AppColors.card)
                        .clipShape(Circle())
                }
                .disabled(chatVM.isStreaming)

                TextField("Ask about your health, state, actions, or care", text: $chatVM.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppColors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isComposerFocused = false
                                UIApplication.shared.sendAction(
                                    #selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil
                                )
                            }
                        }
                    }

                if chatVM.isStreaming {
                    Button {
                        chatVM.stopStreaming()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(AppColors.red)
                            .clipShape(Circle())
                    }
                } else {
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(canSend ? AppColors.primaryStrong : AppColors.border)
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(AppColors.background)
        }
    }

    private var canSend: Bool {
        !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recordsEnabled: Bool {
        guard let profileID = profileStore.selectedProfileID else { return false }
        return profileStore.useRecordsInChat(for: profileID)
    }

    private var chatDocument: EirDocument? {
        guard recordsEnabled, let profileID = profileStore.selectedProfileID else { return nil }
        return profileStore.selectedRecordsDocument(for: profileID, document: documentVM.document)
    }

    private var chatCaseWiki: PatientCaseWiki? {
        guard recordsEnabled,
              let document = chatDocument,
              let wiki = caseWikiVM.wiki,
              CaseSourceCardBuilder.documentSignature(for: document) == wiki.documentSignature
        else {
            return nil
        }
        return wiki
    }

    private var dataSourceSubtitle: String {
        if recordsEnabled {
            let name = displayProfileName
            if let totalEntries = profileStore.selectedProfile?.totalEntries {
                return "\(name) • \(selectedRecordCount) of \(totalEntries) selected"
            }
            return "\(name) • available in State"
        }
        return "Only your messages and conversation context"
    }

    private var selectedRecordCount: Int {
        guard let profileID = profileStore.selectedProfileID else { return 0 }
        return profileStore.selectedRecordCount(for: profileID, document: documentVM.document)
    }

    private var displayProfileName: String {
        guard let name = profileStore.selectedProfile?.displayName, !name.isEmpty else {
            return "Selected profile"
        }
        return name.localizedCaseInsensitiveContains("sample") ? "Sample Data" : name
    }

    private var dataSourceBanner: some View {
        Button {
            showDataSources = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recordsEnabled ? "doc.text" : "text.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(recordsEnabled ? AppColors.primaryStrong : AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recordsEnabled ? "Using selected records" : "Using chat only")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.text)
                    Text(dataSourceSubtitle)
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.card)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.45), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }

    private var emptyStateSubtitle: String {
        if chatDocument != nil {
            return "Talk through symptoms, records, next steps, or questions to bring to care."
        }
        return "You can use Eir for reflection, health questions, next actions, and care preparation."
    }

    private var suggestedPrompts: [String] {
        switch interfaceLanguage {
        case .swedish:
            if chatDocument != nil {
                return [
                    "Vad är viktigaste händelserna i mina journaler?",
                    "Vad bör jag vara uppmärksam på just nu?",
                    "Hjälp mig förbereda frågor till vården"
                ]
            }
            return [
                "Hur kommer jag igång med Eir?",
                "Hjälp mig beskriva hur jag mår idag",
                "Vad är en bra sak jag kan göra just nu?"
            ]
        case .arabic:
            if chatDocument != nil {
                return [
                    "ما أهم الأحداث في سجلاتي الطبية؟",
                    "ما الذي ينبغي أن أنتبه له الآن؟",
                    "ساعدني في تحضير أسئلة للرعاية"
                ]
            }
            return [
                "كيف أبدأ باستخدام إير؟",
                "ساعدني في وصف كيف أشعر اليوم",
                "ما إجراء جيد يمكنني القيام به الآن؟"
            ]
        case .finnish:
            if chatDocument != nil {
                return [
                    "Mitkä ovat tärkeimmät tapahtumat potilastiedoissani?",
                    "Mihin minun pitäisi kiinnittää huomiota juuri nyt?",
                    "Auta minua valmistautumaan hoitoa koskeviin kysymyksiin"
                ]
            }
            return [
                "Miten pääsen alkuun Eirin kanssa?",
                "Auta minua kuvaamaan, miltä minusta tuntuu tänään",
                "Mikä olisi yksi hyvä teko juuri nyt?"
            ]
        case .polish:
            if chatDocument != nil {
                return [
                    "Jakie są najważniejsze wydarzenia w mojej dokumentacji medycznej?",
                    "Na co powinienem teraz zwrócić uwagę?",
                    "Pomóż mi przygotować pytania do opieki zdrowotnej"
                ]
            }
            return [
                "Jak zacząć korzystać z Eir?",
                "Pomóż mi opisać, jak się dziś czuję",
                "Jaki jeden dobry krok mogę zrobić teraz?"
            ]
        case .somali:
            if chatDocument != nil {
                return [
                    "Maxay yihiin dhacdooyinka ugu muhiimsan ee ku jira diiwaannadayda caafimaad?",
                    "Maxaan hadda fiiro gaar ah u yeeshaa?",
                    "Iga caawi inaan diyaariyo su'aalaha aan daryeelka u qaadanayo"
                ]
            }
            return [
                "Sideen ugu bilaabaa Eir?",
                "Iga caawi inaan sharaxo sida aan maanta dareemayo",
                "Maxay tahay hal tallaabo oo fiican oo aan hadda qaadi karo?"
            ]
        case .english:
            if chatDocument != nil {
                return [
                    "What stands out in my recent records?",
                    "What should I pay attention to right now?",
                    "Help me prepare questions for care"
                ]
            }
            return [
                "How should I get started with Eir?",
                "Help me describe how I feel today",
                "What is one good action I can take right now?"
            ]
        }
    }

    private var interfaceLanguage: SupportedChatLanguage {
        if let explicit = settingsVM.responseLanguagePreference.explicitLanguage {
            return explicit
        }
        return settingsVM.resolvedInterfaceLanguage
    }

    private func sendMessage() {
        guard let profileID = profileStore.selectedProfileID else { return }
        isComposerFocused = false
        let includeFollowUpQuestions = profileStore.showChatFollowUpSuggestions(for: profileID)
        chatVM.sendMessage(
            document: chatDocument,
            caseWiki: chatCaseWiki,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager,
            includeFollowUpQuestions: includeFollowUpQuestions
        )
    }

    private func sendSuggestedPrompt(_ prompt: String) {
        chatVM.inputText = prompt
        sendMessage()
    }

    private func sendVoiceNote(_ draft: RecordedVoiceNoteDraft) async {
        guard let profileID = profileStore.selectedProfileID else { return }
        let includeFollowUpQuestions = profileStore.showChatFollowUpSuggestions(for: profileID)
        await chatVM.sendVoiceNote(
            draft,
            document: chatDocument,
            caseWiki: chatCaseWiki,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager,
            includeFollowUpQuestions: includeFollowUpQuestions
        )
    }
}

private struct ChatDataSourcesSheet: View {
    let selectedProfile: PersonProfile?
    let document: EirDocument?
    let recordsEnabled: Bool
    let selectedRecordCount: Int
    let onToggleRecords: (Bool) -> Void
    let onManageRecords: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Used In Chat") {
                    LabeledContent("Conversation") {
                        Text("Always")
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Toggle("Selected profile records", isOn: Binding(
                        get: { recordsEnabled },
                        set: onToggleRecords
                    ))

                    if recordsEnabled, let totalEntries = document?.entries.count {
                        LabeledContent("Selected entries") {
                            Text("\(selectedRecordCount) of \(totalEntries)")
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Button("Choose records") {
                            onManageRecords()
                        }
                    }
                }

                Section("Current Source") {
                    if let selectedProfile {
                        LabeledContent("Profile") {
                            Text(displayName(for: selectedProfile))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        if let totalEntries = selectedProfile.totalEntries {
                            LabeledContent("Entries") {
                                Text("\(totalEntries)")
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        LabeledContent("File") {
                            Text(selectedProfile.fileName)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        }

                        Button("Open State Data") {
                            NotificationCenter.default.post(name: .navigateToState, object: nil)
                            dismiss()
                        }
                    } else {
                        Text("No profile is selected.")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Section {
                    Text(recordsEnabled
                         ? "Chat can use the selected profile records together with your messages."
                         : "Chat will answer from your messages and general guidance only.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .navigationTitle("Chat Data")
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

    private func displayName(for profile: PersonProfile) -> String {
        profile.displayName.localizedCaseInsensitiveContains("sample") ? "Sample Data" : profile.displayName
    }
}

private struct ChatRecordSelectionSheet: View {
    @EnvironmentObject private var documentVM: DocumentViewModel
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let profileID = profileStore.selectedProfileID,
                   let document = documentVM.document {
                    List {
                        Section {
                            LabeledContent("Selected") {
                                Text("\(selectedCount(for: profileID, document: document)) of \(filteredEntries(in: document).count)")
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            HStack {
                                Button("Select All") {
                                    profileStore.selectAllRecordsForChat(for: profileID)
                                }

                                Spacer()

                                Button("Deselect All") {
                                    profileStore.deselectAllRecordsForChat(for: profileID, document: document)
                                }
                                .foregroundStyle(AppColors.red)
                            }
                            .font(.subheadline.weight(.semibold))
                        }

                        Section("Records") {
                            ForEach(filteredEntries(in: document)) { entry in
                                Toggle(isOn: Binding(
                                    get: { profileStore.isRecordIncludedInChat(entry.id, for: profileID) },
                                    set: { included in
                                        profileStore.setRecordIncludedInChat(included, entryID: entry.id, for: profileID)
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.content?.summary ?? entry.type ?? entry.id)
                                            .foregroundColor(AppColors.text)
                                        Text(entry.displayDate)
                                            .font(.caption)
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search records...")
                } else {
                    ContentUnavailableView(
                        "No records available",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Select a profile with records to choose which entries chat can use.")
                    )
                }
            }
            .navigationTitle("Choose Records")
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

    private func selectedCount(for profileID: UUID, document: EirDocument) -> Int {
        filteredEntries(in: document).filter { profileStore.isRecordIncludedInChat($0.id, for: profileID) }.count
    }

    private func filteredEntries(in document: EirDocument) -> [EirEntry] {
        let entries = document.entries
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.content?.summary?.localizedCaseInsensitiveContains(searchText) == true ||
            entry.content?.details?.localizedCaseInsensitiveContains(searchText) == true ||
            entry.content?.notes?.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) == true ||
            entry.category?.localizedCaseInsensitiveContains(searchText) == true ||
            entry.provider?.name?.localizedCaseInsensitiveContains(searchText) == true ||
            entry.type?.localizedCaseInsensitiveContains(searchText) == true ||
            entry.id.localizedCaseInsensitiveContains(searchText)
        }
    }
}
