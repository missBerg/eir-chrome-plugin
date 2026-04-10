import Foundation

enum SystemPrompt {

    /// Build the full system prompt from agent memory files + medical records
    static func build(
        memory: AgentMemory,
        document: EirDocument?,
        includeToolInstructions: Bool = true,
        allowFollowUpQuestions: Bool = false
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
        var responseGuidelines = """
        # Response Guidelines

        - Respond in the same language the user writes in (Swedish or English)
        - Use `<JOURNAL_ENTRY id="ENTRY_ID"/>` to cite specific entries — these become clickable links
        - Never cite entries using only bare IDs like `entry_002`; always wrap the exact ID in the JOURNAL_ENTRY tag
        - Be concise by default; expand when asked for details
        - Start every response with the answer, not a preamble
        - For broad summary questions like "What stands out?", "Summarize my recent records", or "What has been happening lately?", answer directly with your best synthesis from the available records
        - For those broad record questions, prioritize 2 to 5 concrete observations and concise implications
        - Do not begin with caveats such as "I can..." "I need..." or "please provide more context..."
        - Do not ask the user to clarify or narrow first unless there is truly not enough context to answer at all
        - Flag findings that may need professional attention
        - Never provide definitive diagnoses — explain, analyze, and recommend follow-up
        - If unsure, say so rather than guessing about medical matters
        """

        if allowFollowUpQuestions {
            responseGuidelines += """
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
            """
        } else {
            responseGuidelines += """
            - Do not add follow-up questions.
            - Never emit `<FOLLOW_UP_QUESTIONS>` tags or question blocks.
            - Do not end the reply with questions for the user.
            - Do not add a "next questions", "questions you could ask", or similar section in prose.
            - Do not ask what the user wants to explore next.
            """
        }
        sections.append(responseGuidelines)

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
        return build(memory: defaultMemory, document: document, includeToolInstructions: false, allowFollowUpQuestions: false)
    }

    /// Compact system prompt for on-device models — much shorter to reduce prefill time
    static func buildLocal(
        document: EirDocument?,
        userName: String? = nil,
        promptVersion: PromptVersion? = nil,
        allowFollowUpQuestions: Bool = false
    ) -> String {
        var prompt: String
        if let version = promptVersion {
            prompt = version.systemPrompt
        } else {
            prompt = """
            You are Eir, a practical health guide.
            Goal: help the user understand their health and records in plain language.
            Reply in the user's language.
            """
        }

        if let name = userName, !name.isEmpty {
            prompt += "\n\n<user>\nName: \(name)\n</user>"
        }

        if let doc = document {
            prompt += "\n\n<records>"
            if let patient = doc.metadata.patient {
                prompt += "\nPatient: \(patient.name ?? "Unknown")"
                if let dob = patient.birthDate { prompt += " | born \(dob)" }
            }
            if let info = doc.metadata.exportInfo, let total = info.totalEntries {
                prompt += "\nTotal entries: \(total)"
            }
            let recent = doc.entries.prefix(12)
            if !recent.isEmpty {
                prompt += "\nRecent entries:"
                for entry in recent {
                    var line = "\n- ID: \(entry.id) | \(entry.date ?? "?") | \(entry.category ?? "?")"
                    if let type = entry.type, !type.isEmpty {
                        line += " | \(type)"
                    }
                    if let summary = entry.content?.summary, !summary.isEmpty {
                        line += " | \(summary)"
                    }
                    prompt += line
                }
                if doc.entries.count > 12 {
                    prompt += "\n(\(doc.entries.count - 12) more entries available)"
                }
            }
            prompt += "\n</records>"
        }

        prompt += """

        <response_rules>
        - Start with the answer.
        - Be concise by default.
        - Start directly with the insight, not meta statements.
        - Use the records only for record-specific facts.
        - If the records do not answer the question, say so clearly.
        - If context is insufficient, state that directly and avoid any extra caveat language.
        - Label broader advice as general guidance.
        - Explain medical terms simply.
        - Cite specific records with <JOURNAL_ENTRY id="ENTRY_ID"/>.
        - Never write only bare entry IDs such as `entry_002`; always use the JOURNAL_ENTRY tag.
        - Never invent medications, dosages, diagnoses, or test results.
        - Never give a definitive diagnosis.
        - If symptoms sound urgent, tell the user to seek professional care.
        - If there is a question that improves health literacy, answer directly and clearly.
        - Include practical, actionable next steps where appropriate.
        </response_rules>
        """

        if allowFollowUpQuestions {
            prompt += """
            Add follow-up questions only when they are clearly useful.
            If useful, put them at the end inside:
            <FOLLOW_UP_QUESTIONS>
            <QUESTION>...</QUESTION>
            </FOLLOW_UP_QUESTIONS>
            Write follow-up questions from the user's point of view.
            """
        } else {
            prompt += """
            Do not add follow-up questions.
            Never emit `<FOLLOW_UP_QUESTIONS>` tags.
            Do not end the reply with questions for the user.
            Do not add a "next questions" or "questions you could ask" section.
            Do not ask what the user wants to explore next.
            """
        }

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
