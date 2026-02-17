import Foundation

enum SystemPrompt {
    static func build(from document: EirDocument?) -> String {
        var prompt = """
        You are a helpful medical assistant for Eir, a Swedish healthcare records viewer. \
        You help users understand their medical records written in Swedish. \
        You can explain medical terms, summarize visits, and answer health-related questions. \
        Always be accurate and note when something requires professional medical advice. \
        Respond in the same language the user writes in.
        """

        guard let doc = document else { return prompt }

        if let patient = doc.metadata.patient {
            prompt += "\n\nPatient: \(patient.name ?? "Unknown")"
            if let dob = patient.birthDate {
                prompt += ", born \(dob)"
            }
        }

        if let info = doc.metadata.exportInfo {
            if let total = info.totalEntries {
                prompt += "\nTotal entries: \(total)"
            }
            if let range = info.dateRange {
                prompt += "\nDate range: \(range.start ?? "?") to \(range.end ?? "?")"
            }
        }

        let entries = doc.entries.prefix(50)
        if !entries.isEmpty {
            prompt += "\n\nRecent medical records:\n"
            for entry in entries {
                prompt += "\n---\n"
                prompt += "Date: \(entry.date)"
                if let time = entry.time { prompt += " \(time)" }
                prompt += "\nCategory: \(entry.category)"
                if let type = entry.type { prompt += "\nType: \(type)" }
                if let provider = entry.provider?.name { prompt += "\nProvider: \(provider)" }
                if let person = entry.responsiblePerson {
                    prompt += "\nResponsible: \(person.name ?? "?") (\(person.role ?? "?"))"
                }
                if let summary = entry.content?.summary { prompt += "\nSummary: \(summary)" }
                if let details = entry.content?.details { prompt += "\nDetails: \(details)" }
                if let notes = entry.content?.notes, !notes.isEmpty {
                    prompt += "\nNotes: \(notes.joined(separator: "; "))"
                }
            }
        }

        return prompt
    }
}
