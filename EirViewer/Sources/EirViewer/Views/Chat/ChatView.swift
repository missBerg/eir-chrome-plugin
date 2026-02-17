import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.text)

                Spacer()

                if let provider = settingsVM.activeProvider {
                    Text("\(provider.type.rawValue) · \(provider.model)")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.divider)
                        .cornerRadius(4)
                }

                Button {
                    chatVM.clearChat()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear chat")
                .disabled(chatVM.messages.isEmpty)
            }
            .padding()
            .background(AppColors.card)

            Divider()

            // Messages
            if chatVM.messages.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textSecondary.opacity(0.5))
                    Text("Ask questions about your medical records")
                        .foregroundColor(AppColors.textSecondary)
                    if documentVM.document != nil {
                        Text("Your records are loaded as context for the AI")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary.opacity(0.7))
                    }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatVM.messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatVM.messages.count) { _, _ in
                        if let last = chatVM.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Error
            if let error = chatVM.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(AppColors.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppColors.red)
                    Spacer()
                    Button("Dismiss") { chatVM.errorMessage = nil }
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(AppColors.red.opacity(0.05))
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Type a message...", text: $chatVM.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            chatVM.sendMessage(
                                document: documentVM.document,
                                settingsVM: settingsVM
                            )
                        }
                    }

                if chatVM.isStreaming {
                    Button {
                        chatVM.stopStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(AppColors.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        chatVM.sendMessage(
                            document: documentVM.document,
                            settingsVM: settingsVM
                        )
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(
                                chatVM.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? AppColors.textSecondary
                                    : AppColors.primary
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(chatVM.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
            .background(AppColors.card)
        }
        .background(AppColors.background)
    }
}
