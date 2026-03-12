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
                                MessageText(text)
                                    .textSelection(.enabled)
                            case .journalRef(let entryID):
                                JournalEntryLink(entryID: entryID)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(bubbleBackground)
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
                .foregroundColor(AppColors.textTertiary)
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            AppColors.backgroundMuted
        } else {
            Color.clear
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

                MessageText(transcript)
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
            return "Transkriberar..."
        case .failed:
            return voiceNote.errorMessage ?? "Kunde inte transkribera röstnotisen."
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

// MARK: - Message Text

private struct MessageText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(from: source).enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func blockView(for block: MessageBlock) -> some View {
        switch block {
        case .spacer:
            Color.clear
                .frame(height: 4)
        case .heading(let level, let text):
            Text(Self.inlineMarkdown(text))
                .font(Self.headingFont(for: level))
                .fontWeight(.semibold)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(Self.inlineMarkdown(text))
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body.weight(.semibold))
                Text(Self.inlineMarkdown(text))
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .numbered(let number, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text(Self.inlineMarkdown(text))
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColors.border)
                    .frame(width: 3)
                Text(Self.inlineMarkdown(text))
                    .font(.body)
                    .italic()
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: text)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppColors.backgroundMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2
        case 2:
            return .title3
        default:
            return .headline
        }
    }

    private static func normalizedSource(from text: String) -> String {
        let normalizedLineEndings = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let htmlNormalized = normalizedLineEndings
            .replacingOccurrences(
                of: #"(?i)<br\s*/?>"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let tableFlattened = flattenMarkdownTables(in: htmlNormalized)
        let rulesRemoved = stripStandaloneRules(in: tableFlattened)
        let collapsedSpacing = rulesRemoved.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return collapsedSpacing
    }

    private static func blocks(from source: String) -> [MessageBlock] {
        let normalized = normalizedSource(from: source)
        let lines = normalized.components(separatedBy: .newlines)
        var blocks: [MessageBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            let combined = paragraph.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.paragraph(combined))
            }
            paragraph.removeAll()
        }

        func appendSpacerIfNeeded() {
            guard !blocks.isEmpty else { return }
            if case .spacer = blocks.last {
                return
            }
            blocks.append(.spacer)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                index += 1

                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }

                if !codeLines.isEmpty {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                }

                if index < lines.count {
                    index += 1
                }
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                appendSpacerIfNeeded()
                index += 1
                continue
            }

            if trimmed == "|" {
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let bullet = parseBullet(trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                index += 1
                continue
            }

            if let numbered = parseNumberedListItem(trimmed) {
                flushParagraph()
                blocks.append(.numbered(number: numbered.number, text: numbered.text))
                index += 1
                continue
            }

            if let quote = parseQuote(trimmed) {
                flushParagraph()
                blocks.append(.quote(quote))
                index += 1
                continue
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()

        while case .spacer = blocks.last {
            blocks.removeLast()
        }

        return blocks.isEmpty ? [.paragraph(normalized)] : blocks
    }

    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func flattenMarkdownTables(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0

        while index < lines.count {
            if index + 1 < lines.count,
               isMarkdownTableRow(lines[index]),
               isMarkdownTableSeparator(lines[index + 1]) {
                var tableRows = [parseMarkdownTableRow(lines[index])]
                index += 2

                while index < lines.count, isMarkdownTableRow(lines[index]) {
                    tableRows.append(parseMarkdownTableRow(lines[index]))
                    index += 1
                }

                let flattenedRows = tableRows.dropFirst().compactMap { row -> String? in
                    guard let first = row.first, !first.isEmpty else { return nil }
                    let remainder = row.dropFirst()
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if remainder.isEmpty {
                        return "- \(first)"
                    }

                    return "- **\(first)**: \(remainder)"
                }

                if flattenedRows.isEmpty {
                    output.append(contentsOf: tableRows.map { $0.joined(separator: " ") })
                } else {
                    output.append(contentsOf: flattenedRows)
                }
                continue
            }

            output.append(lines[index])
            index += 1
        }

        return output.joined(separator: "\n")
    }

    private static func stripStandaloneRules(in text: String) -> String {
        let rulePattern = #"^(?:\s*[-*_]\s*){3,}$"#
        let tableRulePattern = #"^\s*\|?(?:\s*[:\-]{3,}\s*\|)+\s*[:\-]{3,}\s*\|?\s*$"#

        return text
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return line }

                if trimmed.range(of: rulePattern, options: .regularExpression) != nil {
                    return ""
                }
                if trimmed.range(of: tableRulePattern, options: .regularExpression) != nil {
                    return ""
                }
                return line
            }
            .joined(separator: "\n")
    }

    private static func isMarkdownTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && parseMarkdownTableRow(trimmed).count >= 2
    }

    private static func isMarkdownTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.range(
            of: #"^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseMarkdownTableRow(_ line: String) -> [String] {
        line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }

        let remainder = line.dropFirst(level)
        guard remainder.first == " " else { return nil }

        let text = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func parseBullet(_ line: String) -> String? {
        guard line.count >= 3 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseNumberedListItem(_ line: String) -> (number: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }

        let numberPart = line[..<dotIndex]
        guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) else { return nil }

        let remainderStart = line.index(after: dotIndex)
        guard remainderStart < line.endIndex, line[remainderStart] == " " else { return nil }

        let textStart = line.index(after: remainderStart)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(numberPart), !text.isEmpty else { return nil }
        return (number, text)
    }

    private static func parseQuote(_ line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        let text = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private enum MessageBlock {
    case spacer
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: Int, text: String)
    case quote(String)
    case code(String)
}

// MARK: - Thinking Indicator

private struct ThinkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(AppColors.ai)
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
