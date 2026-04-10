import Foundation

enum SystemPrompt {

    /// Build the full system prompt from agent memory files + medical records
    static func build(
        memory: AgentMemory,
        document: EirDocument?,
        includeToolInstructions: Bool = true
    ) -> String {
        var sections: [String] = []

        // 1. Identity (SOUL.md)
        sections.append(memory.soul)

        // 2. User Profile (USER.md)
        sections.append("# User Profile\n\n\(memory.user)")

        // 3. Session Memory (MEMORY.md)
        sections.append("# Memory\n\n\(memory.memory)")

        // 4. Available Skills (AGENTS.md)
        sections.append(memory.agents)

        // 5. Tool instructions
        if includeToolInstructions {
            sections.append("""
            # Tool Usage

            You have access to tools that let you search records, retrieve details, and update your memory. \
            When a user asks about specific conditions, dates, or entries, use `search_records` to find relevant data. \
            Use `get_record_detail` when you need the full content of a specific entry. \
            Use `update_memory` to remember important facts for future conversations. \
            Use `update_user_profile` when you learn new information about the user.

            Always cite specific entries using `<JOURNAL_ENTRY id="ENTRY_ID"/>` format — this renders as a clickable link.
            """)
        }

        // 6. Medical Records Context
        if let doc = document {
            sections.append(buildRecordsContext(from: doc))
        }

        // 7. Response Guidelines
        sections.append("""
        # Response Guidelines

        - Respond in the same language the user writes in (Swedish or English)
        - Use `<JOURNAL_ENTRY id="ENTRY_ID"/>` to cite specific entries — these become clickable links
        - Be concise by default; expand when asked for details
        - For broad summary questions like "What stands out?", "Summarize my recent records", or "What has been happening lately?", answer directly with your best synthesis from the available records
        - For those broad record questions, lead with 2 to 5 concrete observations before asking any narrowing or follow-up question
        - Do not ask the user to clarify or narrow first unless there is truly not enough context to answer at all
        - Flag findings that may need professional attention
        - Never provide definitive diagnoses — explain, analyze, and recommend follow-up
        - If unsure, say so rather than guessing about medical matters
        - Only add follow-up questions when there is a genuinely useful, natural next question for the user
        - If there is no clear next question, omit the entire follow-up block
        - When helpful, end with up to 3 short next questions the user could ask you inside:
          <FOLLOW_UP_QUESTIONS>
          <QUESTION>...</QUESTION>
          </FOLLOW_UP_QUESTIONS>
        - Write those questions from the user's point of view, like "What should I watch for next?" or "What questions should I ask care?"
        - Do not write them from your own point of view, such as "Would you like me to..." or "Are you interested in..."
        - Do not generate vague filler questions like "Can you tell me more?" or "What would you like to ask next?"
        - Put follow-up questions at the very end, and do not mention the tags in normal prose
        """)

        return sections.joined(separator: "\n\n---\n\n")
    }

    /// Legacy build method for backward compatibility (title generation etc.)
    static func build(from document: EirDocument?) -> String {
        let defaultMemory = AgentMemory(
            soul: AgentDefaults.defaultSoul,
            user: AgentDefaults.defaultUser,
            memory: AgentDefaults.defaultMemory,
            agents: AgentDefaults.defaultAgents
        )
        return build(memory: defaultMemory, document: document, includeToolInstructions: false)
    }

    /// Compact system prompt for on-device models — much shorter to reduce prefill time
    static func buildLocal(
        document: EirDocument?,
        userName: String? = nil,
        promptVersion: PromptVersion? = nil
    ) -> String {
        var prompt: String
        if let version = promptVersion {
            prompt = version.systemPrompt
        } else {
            prompt = """
            You are Eir, a calm and helpful health companion. Respond in the same language the user writes in. Records may be in Swedish — translate when useful.

            You can help in two modes:
            1. Record-grounded mode: when the user asks about their records, labs, medications, visits, or dates, use only the provided records.
            2. General health mode: when the user asks broader health questions, reflection questions, behavior change questions, or "what should I do now?" questions, you may give general supportive health guidance without pretending it came from the records.

            Core rules:
            - Be warm, clear, and practical.
            - Be concise by default.
            - Never claim the records say something unless it is explicitly written there.
            - If record-specific information is missing, say that clearly.
            - For broad summary questions like "What stands out in my recent records?" or "What has been happening lately?", answer directly with the most important patterns you can see from the available records.
            - For those broad record questions, lead with concrete observations first instead of asking the user to narrow the request.
            - Whenever you reference a specific journal note or record entry, include `<JOURNAL_ENTRY id="ENTRY_ID"/>` right next to that reference.
            - Never invent medications, dosages, diagnoses, or test results.
            - Never provide definitive diagnoses.
            - For urgent or concerning symptoms, recommend appropriate professional care.
            - When giving general guidance, label it as general guidance rather than record-based fact.
            """
        }

        if let name = userName, !name.isEmpty {
            prompt += "\n\nThe user is \(name). All records below belong to this person."
        }

        if let doc = document {
            prompt += "\n\n# Patient Records\n"
            if let patient = doc.metadata.patient {
                prompt += "Patient: \(patient.name ?? "Unknown")"
                if let dob = patient.birthDate { prompt += ", born \(dob)" }
                prompt += "\n"
            }
            if let info = doc.metadata.exportInfo, let total = info.totalEntries {
                prompt += "Total entries: \(total)\n"
            }
            let recent = doc.entries.prefix(15)
            if !recent.isEmpty {
                prompt += "\nRecent entries:\n"
                for entry in recent {
                    prompt += "- \(entry.date ?? "?") [\(entry.category ?? "?")] "
                    if let summary = entry.content?.summary { prompt += summary }
                    prompt += " (ID: \(entry.id))\n"
                }
                if doc.entries.count > 15 {
                    prompt += "(\(doc.entries.count - 15) more entries available)\n"
                }
            }
        }

        prompt += """

        
        RESPONSE STYLE:
        - If the question is about the user's records, ground the answer in the records and say what is or is not there.
        - If the question is a broader health question, answer helpfully and practically, while staying medically cautious.
        - If both apply, separate record facts from general guidance.
        - For broad record-summary questions, start with the answer itself, not a request for clarification.
        - When summarizing records, prefer a short "what stands out" synthesis with the most important recent changes, visits, patterns, or unresolved items.
        - When you mention a specific note, visit, result, or record item from the records above, cite it with `<JOURNAL_ENTRY id="ENTRY_ID"/>`.
        - Only add follow-up questions when there is a genuinely useful, natural next question for the user.
        - If there is no clear next question, omit the entire follow-up block.
        - When helpful, end with up to 3 short next questions the user could ask you inside:
          <FOLLOW_UP_QUESTIONS>
          <QUESTION>...</QUESTION>
          </FOLLOW_UP_QUESTIONS>
        - Write those questions from the user's point of view, not your own.
        - Avoid lines like "Would you like me to..." or "Are you interested in..."
        - Do not generate vague filler questions like "Can you tell me more?" or "What would you like to ask next?"
        - Put follow-up questions at the very end, and do not mention the tags in normal prose.
        """

        return prompt
    }

    // MARK: - Records Context

    private static func buildRecordsContext(from doc: EirDocument) -> String {
        var context = "# Medical Records\n\n"

        // Patient metadata
        if let patient = doc.metadata.patient {
            context += "**Patient**: \(patient.name ?? "Unknown")"
            if let dob = patient.birthDate { context += ", born \(dob)" }
            if let pnr = patient.personalNumber { context += " (\(pnr))" }
            context += "\n"
        }

        if let info = doc.metadata.exportInfo {
            if let total = info.totalEntries {
                context += "**Total entries**: \(total)\n"
            }
            if let range = info.dateRange {
                context += "**Date range**: \(range.start ?? "?") to \(range.end ?? "?")\n"
            }
            if let providers = info.healthcareProviders, !providers.isEmpty {
                context += "**Providers**: \(providers.joined(separator: ", "))\n"
            }
        }

        // Entries with tiered detail
        let entries = doc.entries
        if entries.isEmpty { return context }

        context += "\n## Journal Entries (\(entries.count) total)\n\n"

        // First 100: full details
        let fullDetailEntries = entries.prefix(100)
        for entry in fullDetailEntries {
            context += formatEntryFull(entry)
        }

        // Remaining: summary only
        if entries.count > 100 {
            context += "\n## Earlier Entries (summary)\n\n"
            let summaryEntries = entries.dropFirst(100)
            for entry in summaryEntries {
                context += formatEntrySummary(entry)
            }
        }

        return context
    }

    private static func formatEntryFull(_ entry: EirEntry) -> String {
        var text = "---\n"
        text += "ID: \(entry.id)\n"
        text += "Date: \(entry.date ?? "Unknown")"
        if let time = entry.time { text += " \(time)" }
        text += "\nCategory: \(entry.category ?? "Unknown")"
        if let type = entry.type { text += "\nType: \(type)" }
        if let provider = entry.provider?.name { text += "\nProvider: \(provider)" }
        if let person = entry.responsiblePerson {
            text += "\nResponsible: \(person.name ?? "?") (\(person.role ?? "?"))"
        }
        if let status = entry.status { text += "\nStatus: \(status)" }
        if let summary = entry.content?.summary { text += "\nSummary: \(summary)" }
        if let details = entry.content?.details { text += "\nDetails: \(details)" }
        if let notes = entry.content?.notes, !notes.isEmpty {
            text += "\nNotes: \(notes.joined(separator: "; "))"
        }
        text += "\n"
        return text
    }

    private static func formatEntrySummary(_ entry: EirEntry) -> String {
        var text = "- \(entry.date ?? "?") [\(entry.category ?? "?")] "
        if let provider = entry.provider?.name { text += "@ \(provider) " }
        if let summary = entry.content?.summary { text += "— \(summary)" }
        text += " (ID: \(entry.id))\n"
        return text
    }
}
