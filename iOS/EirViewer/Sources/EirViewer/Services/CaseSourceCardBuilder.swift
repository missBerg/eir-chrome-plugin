import CryptoKit
import Foundation

enum CaseSourceCardBuilder {
    static func build(from document: EirDocument) -> [CaseSourceCard] {
        document.entries
            .sorted { lhs, rhs in
                let left = [lhs.date ?? "", lhs.time ?? ""].joined(separator: " ")
                let right = [rhs.date ?? "", rhs.time ?? ""].joined(separator: " ")
                return left < right
            }
            .map { entry in
                let textParts = [
                    entry.content?.summary,
                    entry.content?.details,
                    entry.content?.notes?.joined(separator: "\n")
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

                let fullText = textParts.joined(separator: "\n\n")
                return CaseSourceCard(
                    id: "source-\(entry.id.stableCaseID)",
                    entryID: entry.id,
                    date: entry.date,
                    time: entry.time,
                    category: entry.category,
                    type: entry.type,
                    provider: entry.provider?.name,
                    responsiblePerson: entry.responsiblePerson?.name,
                    summary: entry.content?.summary,
                    detailsPreview: truncated(fullText, limit: 900),
                    fullText: fullText,
                    tags: entry.tags ?? []
                )
            }
    }

    static func documentSignature(for document: EirDocument) -> String {
        let recordSeparator = "\u{1e}"
        let fieldSeparator = "\u{1f}"
        let signatureRows = document.entries.map { entry -> String in
            var fields: [String] = []
            fields.append(entry.id)
            fields.append(entry.date ?? "")
            fields.append(entry.time ?? "")
            fields.append(entry.category ?? "")
            fields.append(entry.type ?? "")
            fields.append(entry.content?.summary ?? "")
            fields.append(entry.content?.details ?? "")
            fields.append(entry.content?.notes?.joined(separator: "|") ?? "")
            return fields.joined(separator: fieldSeparator)
        }
        let signatureSource = signatureRows.joined(separator: recordSeparator)

        let digest = SHA256.hash(data: Data(signatureSource.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func truncated(_ text: String, limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: limit)
        return cleaned[..<end].trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
