import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var chatThreadStore: ChatThreadStore
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var agentMemoryStore: AgentMemoryStore
    @EnvironmentObject var localModelManager: LocalModelManager

    @State private var showOnboarding = false
    @State private var showConversations = false
    @State private var showDictation = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if chatThreadStore.messages.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(AppColors.auraSubtle)
                            .frame(width: 92, height: 92)
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(AppColors.aiStrong)
                    }

                    Text("Ask Eir about your records")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppColors.text)
                        .multilineTextAlignment(.center)
                    if documentVM.document != nil {
                        Text("Your journal is loaded as structured context, including imported Apple Health data.")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .contentShape(Rectangle())
                .onTapGesture {
                    isComposerFocused = false
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatThreadStore.messages.filter { $0.role != .tool }) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isComposerFocused = false
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chatThreadStore.messages.count) { _, _ in
                        if let last = chatThreadStore.messages.last(where: { $0.role != .tool }) {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // Error
            if let error = chatVM.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(AppColors.warning)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppColors.danger)
                    Spacer()
                    Button("Dismiss") { chatVM.errorMessage = nil }
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(AppColors.dangerSoft)
            }

            HStack(spacing: 8) {
                TextField("Type a message...", text: $chatVM.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isComposerFocused)
                    .padding(12)
                    .background(AppColors.backgroundMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    isComposerFocused = false
                    showDictation = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.aiStrong)
                        .frame(width: 42, height: 42)
                        .background(AppColors.aiSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                if chatVM.isStreaming {
                    Button {
                        chatVM.stopStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(AppColors.danger)
                    }
                } else {
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                chatVM.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? AppColors.textTertiary
                                    : AppColors.primaryStrong
                            )
                            .clipShape(Circle())
                    }
                    .disabled(chatVM.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(AppColors.backgroundElevated)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 1)
            }
        }
        .background(AppColors.background)
        .navigationTitle(chatThreadStore.selectedThread?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

            ToolbarItem(placement: .topBarLeading) {
                if let provider = settingsVM.activeProvider {
                    Text("\(provider.type.rawValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.aiStrong)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.aiSoft)
                        .clipShape(Capsule())
                }
            }
        }
        .sheet(isPresented: $showConversations) {
            ConversationListSheet()
        }
        .sheet(isPresented: $showDictation) {
            VoiceNoteComposerSheet(title: "Röstnotis") { draft in
                sendVoiceNote(draft)
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
        .sheet(isPresented: Binding(
            get: { chatVM.pendingCloudConsent != nil },
            set: { if !$0 { chatVM.consentDenied() } }
        )) {
            CloudConsentSheet(
                providerType: chatVM.pendingCloudConsent,
                onConsent: { chatVM.consentGrantedAndSend() },
                onDeny: { chatVM.consentDenied() }
            )
        }
    }

    private func sendMessage() {
        guard let profileID = profileStore.selectedProfileID else { return }
        isComposerFocused = false
        chatVM.sendMessage(
            document: documentVM.document,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager
        )
    }

    private func sendVoiceNote(_ draft: RecordedVoiceNoteDraft) {
        guard let profileID = profileStore.selectedProfileID else { return }
        isComposerFocused = false
        chatVM.sendVoiceNote(
            draft,
            document: documentVM.document,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager
        )
    }
}

// MARK: - Cloud Consent Sheet

private struct CloudConsentSheet: View {
    let providerType: LLMProviderType?
    let onConsent: () -> Void
    let onDeny: () -> Void

    @State private var hasScrolledToBottom = false

    private var providerName: String {
        switch providerType {
        case .bergetTrial:
            return "Berget AI via Eir"
        default:
            return providerType?.rawValue ?? "Cloud Provider"
        }
    }

    private var consentSummary: String {
        switch providerType {
        case .bergetTrial:
            return "By tapping above, you consent to sending your medical data through Eir servers in Stockholm with zero Eir-side retention. Berget AI performs the cloud inference."
        default:
            return "By tapping above, you consent to sending your medical data to \(providerName) for AI processing."
        }
    }

    private var privacyPolicyURL: URL? {
        switch providerType {
        case .bergetTrial: return URL(string: "https://scribe.eir.space/privacy-policy.html")
        case .openai: return URL(string: "https://openai.com/policies/privacy-policy")
        case .anthropic: return URL(string: "https://www.anthropic.com/privacy")
        case .groq: return URL(string: "https://groq.com/privacy-policy/")
        default: return nil
        }
    }

    private var whatDataItems: [String] {
        [
            "Your medical records (diagnoses, medications, lab results, visit notes, provider names, dates)",
            "Your conversation messages in this chat",
            "Your name and basic profile information if included in your records",
            "Any Apple Health data that has been imported into your records"
        ]
    }

    private var recipientItems: [String] {
        switch providerType {
        case .bergetTrial:
            return [
                "Your data is sent over HTTPS to Eir-managed servers in the Stockholm Region, Sweden",
                "Eir is configured for zero Eir-side retention on this hosted route",
                "Berget AI performs the cloud inference after Eir securely forwards the request"
            ]
        default:
            return [
                "Your data will be sent to \(providerName)'s servers for AI processing",
                "Data is transmitted over an encrypted (HTTPS) connection",
                "\(providerName)'s privacy policy governs how they handle your data"
            ]
        }
    }

    private var usageItems: [String] {
        switch providerType {
        case .bergetTrial:
            return [
                "To generate hosted AI responses with the Berget AI model openai/gpt-oss-120b",
                "When you accept, your free Eir-hosted trial is activated for cloud chat",
                "You can revoke consent at any time in Settings > Privacy & Data"
            ]
        default:
            return [
                "To generate AI responses to your questions about your health records",
                "This consent applies to all future messages sent to \(providerName)",
                "You can revoke consent at any time in Settings > Privacy & Data"
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.largeTitle)
                            .foregroundColor(AppColors.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Data Sharing Consent")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Review before sending data to \(providerName)")
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .padding(.bottom, 4)

                    // What data is sent
                    consentSection(
                        title: "What data will be sent",
                        icon: "doc.text",
                        items: whatDataItems
                    )

                    consentSection(
                        title: "Who receives your data",
                        icon: "building.2",
                        items: recipientItems
                    )

                    consentSection(
                        title: "How your data is used",
                        icon: "gearshape",
                        items: usageItems
                    )

                    // Privacy policy link
                    if let url = privacyPolicyURL {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "link")
                                Text("Read \(providerName)'s Privacy Policy")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.subheadline)
                            .foregroundColor(AppColors.primary)
                        }
                        .padding()
                        .background(AppColors.divider)
                        .cornerRadius(12)
                    }

                    // Alternative
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .foregroundColor(AppColors.green)
                        Text("Tip: On-device models keep all data on your phone. You can switch in Settings.")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding()
                    .background(AppColors.green.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Privacy Consent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Decline") { onDeny() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        onConsent()
                    } label: {
                        Text("I Understand & Consent")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primary)

                    Text(consentSummary)
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.large])
    }

    private func consentSection(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(AppColors.primary)
                Text(title)
                    .font(.headline)
            }

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(AppColors.textSecondary)
                    Text(item)
                        .font(.subheadline)
                        .foregroundColor(AppColors.text)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.divider)
        .cornerRadius(12)
    }
}
