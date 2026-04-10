import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let onFollowUpTap: ((String) -> Void)?
    @EnvironmentObject var chatVM: ChatViewModel

    var isUser: Bool { message.role == .user }
    var isEmpty: Bool { message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                if !isUser {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.primaryStrong)
                        .frame(width: 28, height: 28)
                        .background(AppColors.card)
                        .clipShape(Circle())
                } else {
                    Spacer(minLength: 42)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if !isUser && isEmpty && chatVM.isStreaming {
                        ThinkingIndicator()
                    } else if let voiceNote = message.voiceNote {
                        VoiceNoteBubbleContent(
                            voiceNote: voiceNote,
                            transcript: message.content,
                            isUser: isUser
                        )
                    } else {
                        let parts = parseJournalEntryTags(message.content)
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            switch part {
                            case .text(let text):
                                MarkdownText(text)
                                    .textSelection(.enabled)
                            case .journalRef(let entryID):
                                JournalEntryLink(entryID: entryID)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bubbleBackground)
                .foregroundColor(AppColors.text)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(bubbleStroke, lineWidth: isUser ? 0 : 1)
                }

                if isUser {
                    Image(systemName: "person.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColors.primaryStrong)
                        .clipShape(Circle())
                } else {
                    Spacer(minLength: 42)
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser,
               let followUps = message.followUpQuestions,
               !followUps.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Color.clear
                        .frame(width: 28, height: 1)

                    FollowUpQuestionChips(
                        questions: followUps,
                        onTap: { question in
                            onFollowUpTap?(question)
                        }
                    )

                    Spacer(minLength: 42)
                }
            }
        }
    }

    private var bubbleBackground: Color {
        isUser ? AppColors.primaryStrong.opacity(0.14) : AppColors.card
    }

    private var bubbleStroke: Color {
        isUser ? .clear : AppColors.border.opacity(0.35)
    }
}

private struct FollowUpQuestionChips: View {
    let questions: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)

            VStack(spacing: 10) {
                ForEach(questions, id: \.self) { question in
                    Button {
                        onTap(question)
                    } label: {
                        HStack {
                            Text(question)
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
        }
    }
}

private struct VoiceNoteBubbleContent: View {
    let voiceNote: VoiceNoteAttachment
    let transcript: String
    let isUser: Bool

    @StateObject private var player = VoiceNotePlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    player.togglePlayback(for: voiceNote.localFileURL)
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(isUser ? AppColors.primaryStrong : AppColors.aiStrong)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                WaveformCapsule(
                    values: voiceNote.waveform,
                    accent: isUser ? AppColors.primaryStrong : AppColors.aiStrong,
                    isAnimated: voiceNote.status == .transcribing
                )
                .frame(height: 34)

                Text(voiceNote.duration.voiceNoteTimestamp)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(AppColors.textSecondary)
            }

            if let statusText {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
            }

            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                    .overlay(AppColors.border)

                MarkdownText(transcript)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onDisappear {
            player.stop()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: transcript)
        .animation(.easeInOut(duration: 0.25), value: voiceNote.status)
    }

    private var statusText: String? {
        switch voiceNote.status {
        case .transcribing:
            return "Transcribing..."
        case .failed:
            return voiceNote.errorMessage ?? "The voice note could not be transcribed."
        case .ready:
            return nil
        }
    }

    private var statusColor: Color {
        switch voiceNote.status {
        case .transcribing:
            return AppColors.aiStrong
        case .failed:
            return AppColors.danger
        case .ready:
            return AppColors.textSecondary
        }
    }
}

// MARK: - Markdown Text

private struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(source)
        }
    }
}

// MARK: - Thinking Indicator

private struct ThinkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(AppColors.textSecondary)
                    .frame(width: 7, height: 7)
                    .opacity(dotOpacity(for: i))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let offset = Double(index) * 0.3
        let value = sin((phase + offset) * .pi)
        return 0.3 + 0.7 * max(0, value)
    }
}

private extension TimeInterval {
    var voiceNoteTimestamp: String {
        let totalSeconds = max(0, Int(rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
