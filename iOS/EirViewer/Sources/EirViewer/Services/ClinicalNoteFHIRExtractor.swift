import Foundation

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
        let candidates: [String?] = [
            stringValue(resourceObject["title"]),
            stringValue(resourceObject["description"]),
            nestedString(resourceObject, path: ["type", "text"]),
            nestedString(resourceObject, path: ["code", "text"]),
            trimmedFallback
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Klinisk anteckning"
    }

    private static func metadataLines(
        resourceObject: [String: Any]?,
        fallbackResourceType: String?,
        fallbackIdentifier: String?
    ) -> [String] {
        var lines: [String] = ["Importerad från Apple Health"]

        if let resourceType = resourceObject.flatMap(resourceType(from:)) ?? fallbackResourceType,
           !resourceType.isEmpty {
            lines.append("FHIR-resurs: \(resourceType)")
        }

        if let identifier = resourceObject.flatMap({ stringValue($0["id"]) }) ?? fallbackIdentifier,
           !identifier.isEmpty {
            lines.append("FHIR-ID: \(identifier)")
        }

        if let status = resourceObject.flatMap({ stringValue($0["status"]) }), !status.isEmpty {
            lines.append("Status: \(status)")
        }

        if let date = resourceObject.flatMap({ stringValue($0["date"]) ?? stringValue($0["created"]) }),
           !date.isEmpty {
            lines.append("Dokumentdatum: \(date)")
        }

        return lines
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
