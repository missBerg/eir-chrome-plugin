import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    @EnvironmentObject var chatVM: ChatViewModel

    var isUser: Bool { message.role == .user }
    var isEmpty: Bool { message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isUser ? "You" : "Eir")
                .font(.caption.weight(.semibold))
                .foregroundColor(isUser ? AppColors.textSecondary : AppColors.primaryStrong)

            HStack {
                if isUser { Spacer(minLength: 28) }

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
                .background(isUser ? AppColors.backgroundMuted : AppColors.card)
                .foregroundColor(AppColors.text)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isUser ? AppColors.border : Color.clear, lineWidth: 1)
                }

                if !isUser { Spacer(minLength: 28) }
            }

            Text(formattedTime)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
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
