import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    var userName: String?
    var agentName: String?

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 72) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(isUser ? (userName ?? "You") : (agentName ?? "Eir"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isUser ? AppColors.textSecondary : AppColors.primaryStrong)

                VStack(alignment: .leading, spacing: 8) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(bubbleBackground)
                .foregroundColor(AppColors.text)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isUser ? AppColors.border : Color.clear, lineWidth: 1)
                }

                Text(formattedTime)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            if !isUser { Spacer(minLength: 72) }
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
        return rulesRemoved.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
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
            if case .spacer = blocks.last { return }
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

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if let bullet = bulletText(from: trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                index += 1
                continue
            }

            if let numbered = numberedText(from: trimmed) {
                flushParagraph()
                blocks.append(.numbered(numbered.number, numbered.text))
                index += 1
                continue
            }

            if let quote = quoteText(from: trimmed) {
                flushParagraph()
                blocks.append(.quote(quote))
                index += 1
                continue
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        if case .spacer = blocks.last {
            blocks.removeLast()
        }
        return blocks
    }

    private static func heading(from line: String) -> MessageBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }

        let content = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return .heading(hashes.count, content)
    }

    private static func bulletText(from line: String) -> String? {
        let prefixes = ["- ", "* ", "• "]
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedText(from line: String) -> (number: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: "."),
              dotIndex > line.startIndex,
              let number = Int(line[..<dotIndex])
        else {
            return nil
        }

        let textStart = line.index(after: dotIndex)
        let text = line[textStart...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (number, text)
    }

    private static func quoteText(from line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func inlineMarkdown(_ text: String) -> AttributedString {
        let normalized = text.replacingOccurrences(
            of: #"(?<!\n)\n(?!\n)"#,
            with: "  \n",
            options: .regularExpression
        )
        return (try? AttributedString(
            markdown: normalized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private static func flattenMarkdownTables(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard trimmed.contains("|"),
                  index + 1 < lines.count
            else {
                output.append(line)
                index += 1
                continue
            }

            let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
            let isSeparator = separator.allSatisfy { "-:| ".contains($0) } && separator.contains("-")
            guard isSeparator else {
                output.append(line)
                index += 1
                continue
            }

            let headers = tableCells(from: trimmed)
            index += 2

            while index < lines.count {
                let row = lines[index].trimmingCharacters(in: .whitespaces)
                guard row.contains("|") else { break }

                let cells = tableCells(from: row)
                if cells.isEmpty {
                    index += 1
                    continue
                }

                let pairs = zip(headers, cells).map { header, value in
                    "\(header): \(value)"
                }
                output.append("• " + pairs.joined(separator: " · "))
                index += 1
            }
        }

        return output.joined(separator: "\n")
    }

    private static func tableCells(from line: String) -> [String] {
        line
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func stripStandaloneRules(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let cleaned = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return true }
            let matchesRule = trimmed.allSatisfy { "-_*".contains($0) }
            return !(matchesRule && trimmed.count >= 3)
        }
        return cleaned.joined(separator: "\n")
    }
}

private enum MessageBlock {
    case spacer
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    case numbered(Int, String)
    case quote(String)
    case code(String)
}
