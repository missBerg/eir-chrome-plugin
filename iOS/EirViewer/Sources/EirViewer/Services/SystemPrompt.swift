import Foundation

enum SystemPrompt {

    /// Build the full system prompt from agent memory files + medical records
    static func build(
        memory: AgentMemory,
        document: EirDocument?,
        includeToolInstructions: Bool = true,
        allowFollowUpQuestions: Bool = false,
        responseLanguagePreference: ResponseLanguagePreference = .automatic,
        sourceLanguage: SupportedChatLanguage? = nil
    ) -> String {
        var sections: [String] = []
        let hasRecords = !(document?.entries.isEmpty ?? true)

        // 1. Identity (SOUL.md)
        sections.append(memory.soul)

        // 2. User Profile (USER.md)
        sections.append("# User Profile\n\n\(memory.user)")

        // 3. Session Memory (MEMORY.md)
        sections.append("# Memory\n\n\(memory.memory)")

        // 4. Available Skills (AGENTS.md)
        sections.append(memory.agents)

        // 5. Tool instructions
        if includeToolInstructions && hasRecords {
            sections.append("""
            # Tool Usage

            You have access to tools that let you search records, retrieve details, and update your memory. \
            When a user asks about specific conditions, dates, or entries, use `search_records` to find relevant data. \
            Use `get_record_detail` when you need the full content of a specific entry. \
            Use `update_memory` to remember important facts for future conversations. \
            Use `update_user_profile` when you learn new information about the user.

            Always cite specific entries using `<JOURNAL_ENTRY id="ENTRY_ID"/>` format — this renders as a clickable link.
            """)
        } else if includeToolInstructions {
            sections.append("""
            # Tool Usage

            No health record document is attached to this chat right now.
            Do not search for or cite records unless a document is explicitly attached later in the conversation.
            Use memory tools only when relevant.
            """)
        }

        // 6. Medical Records Context
        if let doc = document, hasRecords {
            sections.append(buildRecordsContext(from: doc))
        }

        // 7. Response Guidelines
        var responseGuidelines = """
        # Response Guidelines

        \(responseLanguageRule(preference: responseLanguagePreference, sourceLanguage: sourceLanguage))
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

        if hasRecords {
            responseGuidelines += """
            - Use `<JOURNAL_ENTRY id="ENTRY_ID"/>` to cite specific entries — these become clickable links
            - Never cite entries using only bare IDs like `entry_002`; always wrap the exact ID in the JOURNAL_ENTRY tag
            """
        } else {
            responseGuidelines += """
            - No health record document is attached to this chat right now.
            - Do not claim to see records when none are attached.
            - Do not emit `<JOURNAL_ENTRY>` tags or fake record placeholders.
            - Answer general health, state, action, and care questions helpfully from the conversation and general guidance.
            - Only mention that records are missing when the user explicitly asks for record analysis or record-grounded facts.
            """
        }

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
        return build(
            memory: defaultMemory,
            document: document,
            includeToolInstructions: false,
            allowFollowUpQuestions: false,
            responseLanguagePreference: .automatic,
            sourceLanguage: nil
        )
    }

    /// Compact system prompt for on-device models — much shorter to reduce prefill time
    static func buildLocal(
        document: EirDocument?,
        userName: String? = nil,
        promptVersion: PromptVersion? = nil,
        allowFollowUpQuestions: Bool = false,
        responseLanguagePreference: ResponseLanguagePreference = .automatic,
        sourceLanguage: SupportedChatLanguage? = nil
    ) -> String {
        var prompt: String
        let hasRecords = !(document?.entries.isEmpty ?? true)
        if let version = promptVersion {
            prompt = version.systemPrompt
        } else {
            prompt = """
            You are Eir, a practical health guide.
            Goal: help the user understand their health and records in plain language.
            \(responseLanguageSentence(preference: responseLanguagePreference, sourceLanguage: sourceLanguage))
            """
        }

        if let name = userName, !name.isEmpty {
            prompt += "\n\n<user>\nName: \(name)\n</user>"
        }

        if let doc = document, hasRecords {
            prompt += "\n\n<records>"
            if let patient = doc.metadata.patient {
                prompt += "\nPatient: \(patient.name ?? "Unknown")"
                if let dob = patient.birthDate { prompt += " | born \(dob)" }
            }
            if let info = doc.metadata.exportInfo, let total = info.totalEntries {
                prompt += "\nTotal entries: \(total)"
            }
            let recent = doc.entries.prefix(8)
            if !recent.isEmpty {
                prompt += "\nThe records are already included below. Do not ask the user to provide records that are present in this block."
                prompt += "\nRecent entries:"
                for entry in recent {
                    prompt += localRecordContext(for: entry)
                }
                if doc.entries.count > 8 {
                    prompt += "\n(\(doc.entries.count - 8) more entries available)"
                }
            }
            prompt += "\n</records>"
        } else {
            prompt += """

            <context>
            No health record document is attached to this chat right now.
            The user can still ask general questions about health, state, actions, and care.
            Do not ask for records unless the user explicitly wants record-based analysis.
            </context>
            """
        }

        prompt += """

        <response_rules>
        - \(responseLanguageRuleText(preference: responseLanguagePreference, sourceLanguage: sourceLanguage))
        - Start with the answer.
        - Be concise by default.
        - Start directly with the insight, not meta statements.
        - \(hasRecords ? "Use the records only for record-specific facts." : "Use the conversation context only; no records are attached.") 
        - \(hasRecords ? "If records are included in the prompt, use them directly and never ask the user to provide those same records again." : "Do not ask the user to upload or paste records unless they specifically want record-based analysis.")
        - \(hasRecords ? "If the records do not answer the question, say so clearly." : "If the user asks for record-specific facts, say no records are attached to this chat right now.")
        - If context is insufficient, state that directly and avoid any extra caveat language.
        - Label broader advice as general guidance.
        - Explain medical terms simply.
        - Never invent medications, dosages, diagnoses, or test results.
        - Never give a definitive diagnosis.
        - If symptoms sound urgent, tell the user to seek professional care.
        - If there is a question that improves health literacy, answer directly and clearly.
        - Include practical, actionable next steps where appropriate.
        </response_rules>
        """

        if hasRecords {
            prompt += """
            Cite specific records with <JOURNAL_ENTRY id="ENTRY_ID"/>.
            Never write only bare entry IDs such as `entry_002`; always use the JOURNAL_ENTRY tag.
            """
        } else {
            prompt += """
            Never emit `<JOURNAL_ENTRY>` tags or fake record IDs when no records are attached.
            """
        }

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

    private static func responseLanguageRule(
        preference: ResponseLanguagePreference,
        sourceLanguage: SupportedChatLanguage?
    ) -> String {
        "- \(responseLanguageRuleText(preference: preference, sourceLanguage: sourceLanguage))"
    }

    private static func responseLanguageRuleText(
        preference: ResponseLanguagePreference,
        sourceLanguage: SupportedChatLanguage?
    ) -> String {
        if let explicit = preference.explicitLanguage {
            return "Reply in \(explicit.promptName), even if the records or note are written in another language."
        }

        if let sourceLanguage {
            return "Reply in \(sourceLanguage.promptName) to match the language of the note or message being discussed."
        }

        return "Reply in the same language as the user's message."
    }

    private static func responseLanguageSentence(
        preference: ResponseLanguagePreference,
        sourceLanguage: SupportedChatLanguage?
    ) -> String {
        let text = responseLanguageRuleText(preference: preference, sourceLanguage: sourceLanguage)
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func localRecordContext(for entry: EirEntry) -> String {
        var block = "\n- ID: \(entry.id) | \(entry.date ?? "?") | \(entry.category ?? "?")"
        if let type = entry.type, !type.isEmpty {
            block += " | \(type)"
        }
        if let summary = entry.content?.summary, !summary.isEmpty {
            block += "\n  Summary: \(truncated(summary, limit: 220))"
        }
        if let details = entry.content?.details, !details.isEmpty {
            block += "\n  Details: \(truncated(details, limit: 320))"
        }
        if let notes = entry.content?.notes, !notes.isEmpty {
            let joinedNotes = notes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !joinedNotes.isEmpty {
                block += "\n  Notes: \(truncated(joinedNotes, limit: 420))"
            }
        }
        return block
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        let endIndex = cleaned.index(cleaned.startIndex, offsetBy: limit)
        return cleaned[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "..."
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
