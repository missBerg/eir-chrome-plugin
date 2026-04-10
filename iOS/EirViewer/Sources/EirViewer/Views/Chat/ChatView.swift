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

    @State private var showOnboarding = false
    @State private var showConversations = false
    @State private var showDictation = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
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

    private var emptyStateSubtitle: String {
        if documentVM.document != nil {
            return "Talk through symptoms, records, next steps, or questions to bring to care."
        }
        return "You can use Eir for reflection, health questions, next actions, and care preparation."
    }

    private var suggestedPrompts: [String] {
        if documentVM.document != nil {
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

    private func sendMessage() {
        guard let profileID = profileStore.selectedProfileID else { return }
        isComposerFocused = false
        let includeFollowUpQuestions = profileStore.showChatFollowUpSuggestions(for: profileID)
        chatVM.sendMessage(
            document: documentVM.document,
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
            document: documentVM.document,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager,
            includeFollowUpQuestions: includeFollowUpQuestions
        )
    }
}
