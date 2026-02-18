import Foundation

struct ToolContext {
    let document: EirDocument?
    let allDocuments: [(profileID: UUID, personName: String, document: EirDocument)]
    let agentMemoryStore: AgentMemoryStore?
    let clinicStore: ClinicStore?
    let embeddingStore: EmbeddingStore?
}

actor ToolRegistry {

    // MARK: - Tool Definitions

    static let tools: [ToolDefinition] = [
        ToolDefinition(
            name: "get_medical_records",
            description: "Retrieve ALL medical records with full details. Call this whenever the user asks about their health records, journal entries, treatments, medications, lab results, diagnoses, or any medical history. Returns every entry for all family members (or filtered by person). One call gives you everything you need — no follow-up calls required.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "person": ToolProperty(type: "string", description: "Filter by person name. Omit to get records for ALL family members."),
                ],
                required: nil
            )
        ),
        ToolDefinition(
            name: "find_clinics",
            description: "Search for nearby healthcare clinics in Sweden by name or type.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "query": ToolProperty(type: "string", description: "Search term for clinic name or address"),
                    "type": ToolProperty(
                        type: "string",
                        description: "Clinic type to filter by",
                        enum: ["Vårdcentral", "Tandvård", "Psykiatri", "Barn/BVC", "Rehab/Fysio", "Ögon", "Hud", "Ortoped", "Kirurgi", "Gynekolog", "Akut/Jour", "Labb/Röntgen", "Vaccination", "Ungdom"]
                    ),
                    "limit": ToolProperty(type: "integer", description: "Max number of results to return (default 10)"),
                ],
                required: nil
            )
        ),
        ToolDefinition(
            name: "update_memory",
            description: "Update the agent's long-term memory with important facts to remember across conversations. Use sparingly for key health context.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "content": ToolProperty(type: "string", description: "The full updated memory content in markdown format"),
                ],
                required: ["content"]
            )
        ),
        ToolDefinition(
            name: "name_agent",
            description: "Set your name. Call this when the user chooses a name for you during onboarding.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "name": ToolProperty(type: "string", description: "The name the user chose for you"),
                ],
                required: ["name"]
            )
        ),
        ToolDefinition(
            name: "update_user_profile",
            description: "Update a section of the user's health profile with new information learned during conversation.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "section": ToolProperty(
                        type: "string",
                        description: "Which section to update",
                        enum: ["basic_info", "health_goals", "conditions", "preferences"]
                    ),
                    "content": ToolProperty(type: "string", description: "The updated content for this section"),
                ],
                required: ["section", "content"]
            )
        ),
    ]

    // MARK: - Execution

    func execute(call: ToolCall, context: ToolContext) async -> ToolResult {
        guard let args = parseArguments(call.arguments) else {
            return ToolResult(toolCallId: call.id, content: "Error: Could not parse tool arguments")
        }

        switch call.name {
        case "get_medical_records":
            return getMedicalRecords(args: args, allDocuments: context.allDocuments, callId: call.id)
        case "find_clinics":
            return await findClinics(args: args, clinicStore: context.clinicStore, callId: call.id)
        case "name_agent":
            guard let store = context.agentMemoryStore else {
                return ToolResult(toolCallId: call.id, content: "Error: Agent memory not available")
            }
            return await nameAgent(args: args, store: store, callId: call.id)
        case "update_memory":
            guard let store = context.agentMemoryStore else {
                return ToolResult(toolCallId: call.id, content: "Error: Agent memory not available")
            }
            return await updateMemory(args: args, store: store, callId: call.id)
        case "update_user_profile":
            guard let store = context.agentMemoryStore else {
                return ToolResult(toolCallId: call.id, content: "Error: Agent memory not available")
            }
            return await updateUserProfile(args: args, store: store, callId: call.id)
        default:
            return ToolResult(toolCallId: call.id, content: "Error: Unknown tool '\(call.name)'")
        }
    }

    // MARK: - Tool Implementations

    private func getMedicalRecords(args: [String: Any], allDocuments: [(profileID: UUID, personName: String, document: EirDocument)], callId: String) -> ToolResult {
        guard !allDocuments.isEmpty else {
            return ToolResult(toolCallId: callId, content: "No medical records loaded.")
        }

        let personFilter = args["person"] as? String
        // Use composite IDs whenever multiple profiles are loaded (not just in filtered results)
        let useCompositeIDs = allDocuments.count > 1

        let docs: [(profileID: UUID, personName: String, document: EirDocument)]
        if let personFilter {
            docs = allDocuments.filter { $0.personName.localizedCaseInsensitiveContains(personFilter) }
        } else {
            docs = allDocuments
        }

        guard !docs.isEmpty else {
            return ToolResult(toolCallId: callId, content: "No records found for '\(personFilter ?? "")'.")
        }

        var output = ""

        for (profileID, personName, doc) in docs {
            output += "# \(personName)\n"
            if let patient = doc.metadata.patient {
                if let dob = patient.birthDate { output += "Born: \(dob)\n" }
            }
            output += "Total entries: \(doc.entries.count)\n\n"

            for entry in doc.entries {
                // Always prefix with person name when multiple profiles exist,
                // so the LLM naturally includes it in citations
                let refID = useCompositeIDs ? "\(personName)::\(entry.id)" : entry.id
                output += "## [\(refID)] \(entry.date ?? "?")"
                if let time = entry.time { output += " \(time)" }
                output += " — \(entry.category ?? "?")"
                if let type = entry.type { output += " / \(type)" }
                output += "\n"

                if let provider = entry.provider?.name { output += "Provider: \(provider)\n" }
                if let person = entry.responsiblePerson {
                    output += "Responsible: \(person.name ?? "?") (\(person.role ?? "?"))\n"
                }
                if let summary = entry.content?.summary {
                    output += "\(summary)\n"
                }
                if let details = entry.content?.details, !details.isEmpty {
                    output += "\(details)\n"
                }
                if let notes = entry.content?.notes, !notes.isEmpty {
                    for note in notes { output += "- \(note)\n" }
                }
                if let tags = entry.tags, !tags.isEmpty {
                    output += "Tags: \(tags.joined(separator: ", "))\n"
                }
                output += "\n"
            }
        }

        return ToolResult(toolCallId: callId, content: output)
    }

    private func findClinics(args: [String: Any], clinicStore: ClinicStore?, callId: String) async -> ToolResult {
        guard let store = clinicStore else {
            return ToolResult(toolCallId: callId, content: "Clinic search is not available.")
        }

        let query = args["query"] as? String
        let typeFilter = args["type"] as? String
        let limit = (args["limit"] as? Int) ?? 10

        let clinics = await MainActor.run { store.allClinics }

        var results = clinics

        if let typeFilter {
            results = results.filter { clinic in
                let type = ClinicType.categorize(clinic.name)
                return type?.rawValue == typeFilter
            }
        }

        if let query, !query.isEmpty {
            let lowered = query.lowercased()
            results = results.filter { clinic in
                clinic.name.localizedCaseInsensitiveContains(lowered)
                    || (clinic.address?.localizedCaseInsensitiveContains(lowered) ?? false)
            }
        }

        let limited = results.prefix(limit)

        if limited.isEmpty {
            return ToolResult(toolCallId: callId, content: "No clinics found matching your search.")
        }

        var output = "Found \(results.count) clinics"
        if results.count > limit { output += " (showing first \(limit))" }
        output += ":\n\n"

        for clinic in limited {
            output += "### \(clinic.name)\n"
            if let address = clinic.address { output += "- Address: \(address)\n" }
            if let phone = clinic.phone { output += "- Phone: \(phone)\n" }
            if let url = clinic.url { output += "- Website: \(url)\n" }
            if clinic.hasMvkServices { output += "- Has 1177 e-services\n" }
            if clinic.videoOrChat { output += "- Offers video/chat consultations\n" }
            output += "\n"
        }

        return ToolResult(toolCallId: callId, content: output)
    }

    private func nameAgent(args: [String: Any], store: AgentMemoryStore, callId: String) async -> ToolResult {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: callId, content: "Error: name is required")
        }
        await MainActor.run {
            store.setAgentName(name)
        }
        return ToolResult(toolCallId: callId, content: "Agent name set to '\(name)'.")
    }

    private func updateMemory(args: [String: Any], store: AgentMemoryStore, callId: String) async -> ToolResult {
        guard let content = args["content"] as? String else {
            return ToolResult(toolCallId: callId, content: "Error: content is required")
        }
        await MainActor.run {
            store.updateMemory(content)
        }
        return ToolResult(toolCallId: callId, content: "Memory updated successfully.")
    }

    private func updateUserProfile(args: [String: Any], store: AgentMemoryStore, callId: String) async -> ToolResult {
        guard let section = args["section"] as? String,
              let content = args["content"] as? String else {
            return ToolResult(toolCallId: callId, content: "Error: section and content are required")
        }

        await MainActor.run {
            var current = store.memory.user

            let sectionHeaders: [String: String] = [
                "basic_info": "## Basic Info",
                "health_goals": "## Health Goals",
                "conditions": "## Conditions & Medications",
                "preferences": "## Preferences",
            ]

            guard let header = sectionHeaders[section] else {
                return
            }

            if let headerRange = current.range(of: header) {
                let afterHeader = current[headerRange.upperBound...]
                if let nextSection = afterHeader.range(of: "\n## ") {
                    current = String(current[..<headerRange.upperBound]) + "\n" + content + "\n" + String(current[nextSection.lowerBound...])
                } else {
                    current = String(current[..<headerRange.upperBound]) + "\n" + content + "\n"
                }
            } else {
                current += "\n\(header)\n\(content)\n"
            }

            store.updateUser(current)
        }

        return ToolResult(toolCallId: callId, content: "User profile section '\(section)' updated successfully.")
    }

    // MARK: - Helpers

    private func parseArguments(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || json == "{}" {
                return [:]
            }
            return nil
        }
        return obj
    }
}
