import Foundation
import PDFKit

struct ClinicalNoteFHIRExtraction: Equatable {
    let summary: String
    let noteBlocks: [String]
    let metadataLines: [String]
    let tags: [String]
}

enum ClinicalNoteFHIRExtractor {
    static func extract(
        from data: Data,
        fallbackTitle: String,
        fallbackResourceType: String? = nil,
        fallbackIdentifier: String? = nil
    ) -> ClinicalNoteFHIRExtraction {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let trimmedTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return ClinicalNoteFHIRExtraction(
                summary: trimmedTitle.isEmpty ? "Klinisk anteckning" : trimmedTitle,
                noteBlocks: [],
                metadataLines: metadataLines(
                    resourceObject: nil,
                    fallbackResourceType: fallbackResourceType,
                    fallbackIdentifier: fallbackIdentifier
                ),
                tags: ["clinical-note"]
            )
        }

        let summary = clinicalSummary(from: object, fallbackTitle: fallbackTitle)
        let noteBlocks = clinicalNoteBlocks(from: object)
        let metadataLines = metadataLines(
            resourceObject: object,
            fallbackResourceType: fallbackResourceType,
            fallbackIdentifier: fallbackIdentifier
        )

        var tags = ["clinical-note"]
        if let resourceType = resourceType(from: object) {
            tags.append(resourceType.lowercased())
        } else if let fallbackResourceType, !fallbackResourceType.isEmpty {
            tags.append(fallbackResourceType.lowercased())
        }

        return ClinicalNoteFHIRExtraction(
            summary: summary,
            noteBlocks: deduplicatedNoteBlocks(noteBlocks),
            metadataLines: metadataLines,
            tags: tags
        )
    }

    private static func clinicalSummary(from resourceObject: [String: Any], fallbackTitle: String) -> String {
        let trimmedFallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get the note type (e.g., "Progress Notes", "Patient Instructions")
        let noteType: String = [
            stringValue(resourceObject["title"]),
            stringValue(resourceObject["description"]),
            nestedString(resourceObject, path: ["type", "text"]),
            nestedString(resourceObject, path: ["code", "text"]),
            trimmedFallback
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? "Klinisk anteckning"

        // Get the encounter type (e.g., "Office Visit", "Video Visit - MH/BH")
        let encounter = (resourceObject["context"] as? [String: Any])
            .flatMap { $0["encounter"] as? [[String: Any]] }?
            .first
            .flatMap { stringValue($0["display"]) }

        // Get the primary author
        let author = (resourceObject["author"] as? [[String: Any]])?
            .first
            .flatMap { stringValue($0["display"]) }

        // Build a richer summary: "Progress Notes — Office Visit (Jennifer M Rodriguez, MD)"
        var parts = [noteType]
        if let encounter, !encounter.isEmpty {
            parts.append(encounter)
        }
        if let author, !author.isEmpty {
            return parts.joined(separator: " — ") + " (\(author))"
        }
        return parts.joined(separator: " — ")
    }

    private static func metadataLines(
        resourceObject: [String: Any]?,
        fallbackResourceType: String?,
        fallbackIdentifier: String?
    ) -> [String] {
        guard let obj = resourceObject else {
            var lines = ["Importerad från Apple Health"]
            if let rt = fallbackResourceType, !rt.isEmpty { lines.append("FHIR-resurs: \(rt)") }
            if let id = fallbackIdentifier, !id.isEmpty { lines.append("FHIR-ID: \(id)") }
            return lines
        }

        var lines: [String] = []

        // Author(s)
        if let authors = obj["author"] as? [[String: Any]] {
            let names = authors.compactMap { stringValue($0["display"]) }
            if !names.isEmpty {
                lines.append("Författare: \(names.joined(separator: ", "))")
            }
        }

        // Authenticator (signing provider)
        if let auth = obj["authenticator"] as? [String: Any],
           let authName = stringValue(auth["display"]) {
            // Only add if different from author
            let authorNames = (obj["author"] as? [[String: Any]])?
                .compactMap { stringValue($0["display"]) } ?? []
            if !authorNames.contains(authName) {
                lines.append("Signerad av: \(authName)")
            }
        }

        // Encounter type
        if let context = obj["context"] as? [String: Any] {
            if let encounters = context["encounter"] as? [[String: Any]],
               let encounterDisplay = encounters.first.flatMap({ stringValue($0["display"]) }),
               !encounterDisplay.isEmpty {
                lines.append("Besökstyp: \(encounterDisplay)")
            }

            // Provider type / specialty from context extension
            if let extensions = context["extension"] as? [[String: Any]] {
                for ext in extensions {
                    if let concept = ext["valueCodeableConcept"] as? [String: Any],
                       let text = stringValue(concept["text"]),
                       !text.isEmpty {
                        lines.append("Yrkesroll: \(text)")
                    }
                }
            }

            // Visit date from context.period
            if let period = context["period"] as? [String: Any],
               let start = stringValue(period["start"]),
               !start.isEmpty {
                lines.append("Besöksdatum: \(formatFHIRDate(start))")
            }
        }

        // Document status
        if let docStatus = stringValue(obj["docStatus"]), !docStatus.isEmpty {
            lines.append("Dokumentstatus: \(docStatus)")
        } else if let status = stringValue(obj["status"]), !status.isEmpty {
            lines.append("Status: \(status)")
        }

        // Document date
        if let date = stringValue(obj["date"]) ?? stringValue(obj["created"]),
           !date.isEmpty {
            lines.append("Dokumentdatum: \(formatFHIRDate(date))")
        }

        lines.append("Importerad från Apple Health")

        return lines
    }

    private static func formatFHIRDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "sv_SE")
            return formatter.string(from: date)
        }
        return dateString
    }

    private static func clinicalNoteBlocks(from object: [String: Any]) -> [String] {
        var blocks: [String] = []

        if let topNarrative = narrativeText(from: object), !topNarrative.isEmpty {
            blocks.append(topNarrative)
        }

        if let description = stringValue(object["description"]),
           !description.isEmpty,
           !blocks.contains(description) {
            blocks.append(description)
        }

        if let notes = object["note"] as? [[String: Any]] {
            for note in notes {
                if let text = stringValue(note["text"]), !text.isEmpty {
                    blocks.append(text)
                }
            }
        }

        if let conclusion = stringValue(object["conclusion"]), !conclusion.isEmpty {
            blocks.append(conclusion)
        }

        if let sections = object["section"] as? [[String: Any]] {
            blocks.append(contentsOf: sectionBlocks(from: sections))
        }

        blocks.append(contentsOf: attachmentBlocks(from: object["content"]))
        blocks.append(contentsOf: attachmentBlocks(from: object["presentedForm"]))

        if let entryResources = bundleResourceObjects(from: object) {
            for resource in entryResources {
                blocks.append(contentsOf: clinicalNoteBlocks(from: resource))
            }
        }

        return blocks
    }

    private static func bundleResourceObjects(from object: [String: Any]) -> [[String: Any]]? {
        guard resourceType(from: object) == "Bundle",
              let entries = object["entry"] as? [[String: Any]] else {
            return nil
        }

        return entries.compactMap { $0["resource"] as? [String: Any] }
    }

    private static func sectionBlocks(from sections: [[String: Any]]) -> [String] {
        var blocks: [String] = []

        for section in sections {
            let title = stringValue(section["title"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = narrativeText(from: section)
            let body = [title, text]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            if !body.isEmpty {
                blocks.append(body)
            }

            if let nestedSections = section["section"] as? [[String: Any]] {
                blocks.append(contentsOf: sectionBlocks(from: nestedSections))
            }
        }

        return blocks
    }

    private static func attachmentBlocks(from value: Any?) -> [String] {
        guard let array = value as? [[String: Any]] else { return [] }

        return array.compactMap { item in
            let attachment = (item["attachment"] as? [String: Any]) ?? item
            return textualAttachmentBody(from: attachment)
        }
    }

    private static func textualAttachmentBody(from attachment: [String: Any]) -> String? {
        let contentType = stringValue(attachment["contentType"])?.lowercased() ?? ""
        guard let dataString = stringValue(attachment["data"]),
              let data = Data(base64Encoded: dataString) else {
            return nil
        }

        let body: String?
        if contentType.contains("html") || contentType.contains("xml") || contentType.contains("xhtml") {
            body = plainText(fromMarkupData: data)
        } else if contentType.contains("pdf") {
            body = extractTextFromPDF(data: data)
        } else if contentType.contains("text") || contentType.isEmpty {
            body = String(data: data, encoding: .utf8)
        } else {
            body = nil
        }

        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedBody, !trimmedBody.isEmpty else { return nil }

        if let title = stringValue(attachment["title"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           !trimmedBody.localizedCaseInsensitiveContains(title) {
            return "\(title)\n\n\(trimmedBody)"
        }

        return trimmedBody
    }

    private static func narrativeText(from object: [String: Any]) -> String? {
        guard let text = object["text"] as? [String: Any],
              let div = stringValue(text["div"]) else {
            return nil
        }
        return plainText(fromMarkupString: div)
    }

    private static func resourceType(from object: [String: Any]) -> String? {
        stringValue(object["resourceType"])
    }

    private static func nestedString(_ object: [String: Any], path: [String]) -> String? {
        var current: Any? = object
        for component in path {
            current = (current as? [String: Any])?[component]
        }
        return stringValue(current)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let dict = value as? [String: Any] {
            return dict["value"] as? String
        }
        return nil
    }

    private static func deduplicatedNoteBlocks(_ blocks: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for block in blocks {
            let normalized = block
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(block.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return result
    }

    private static func plainText(fromMarkupString markup: String) -> String? {
        plainText(fromMarkupData: Data(markup.utf8))
    }

    private static func plainText(fromMarkupData data: Data) -> String? {
        return stripHTML(from: String(decoding: data, as: UTF8.self))
    }

    private static func extractTextFromPDF(data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string, !text.isEmpty {
                pages.append(text)
            }
        }
        let result = pages.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }

    private static func stripHTML(from html: String) -> String {
        html
            .replacingOccurrences(of: "(?i)</p>|<br\\s*/?>|</li>|</div>|</h[1-6]>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<li[^>]*>", with: "• ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
