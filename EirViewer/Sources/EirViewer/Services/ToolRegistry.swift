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
            name: "get_records_request_guide",
            description: "Get provider-specific instructions for obtaining medical records (download + HIPAA request workflow). Use this whenever the user asks how to request, download, transfer, or collect records from a provider like Kaiser Georgia.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "provider": ToolProperty(type: "string", description: "Healthcare provider name (for example: 'Kaiser Permanente Georgia')"),
                    "state": ToolProperty(type: "string", description: "US state abbreviation or name (for example: 'GA' or 'Georgia')"),
                ],
                required: ["provider"]
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
        case "get_records_request_guide":
            return getRecordsRequestGuide(args: args, callId: call.id)
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

    private func getRecordsRequestGuide(args: [String: Any], callId: String) -> ToolResult {
        guard let providerRaw = args["provider"] as? String else {
            return ToolResult(toolCallId: callId, content: "Error: provider is required")
        }
        let provider = providerRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.isEmpty else {
            return ToolResult(toolCallId: callId, content: "Error: provider is required")
        }

        let state = (args["state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if isKaiserGeorgia(provider: provider, state: state) {
            return ToolResult(
                toolCallId: callId,
                content: buildKaiserGeorgiaRecordsGuide(provider: provider)
            )
        }

        return ToolResult(
            toolCallId: callId,
            content: buildGenericUSRecordsGuide(provider: provider, state: state)
        )
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

    private func isKaiserGeorgia(provider: String, state: String?) -> Bool {
        let normalizedProvider = provider.lowercased()
        let normalizedState = state?.lowercased()

        let mentionsKaiser = normalizedProvider.contains("kaiser")
            || normalizedProvider.contains("kp.org")
            || normalizedProvider.contains("kp ")
        let mentionsGeorgiaInProvider = normalizedProvider.contains("georgia")
        let mentionsGeorgiaInState = normalizedState == "ga" || normalizedState == "georgia"

        return mentionsKaiser && (mentionsGeorgiaInProvider || mentionsGeorgiaInState)
    }

    private func buildKaiserGeorgiaRecordsGuide(provider: String) -> String {
        """
        # Medical Records Request Guide — Kaiser Permanente Georgia

        This workflow helps you get your records from **\(provider)** as quickly as possible.

        ## 1) Fastest path: download what is already available in the portal
        1. Sign in to your Kaiser account at https://healthy.kaiserpermanente.org/
        2. Open your medical record/download area (labels vary by screen, often under My Health Manager/Medical Record).
        3. Download available sections first (visit summaries, labs, medications, immunizations, after-visit summaries).
        4. Save files with clear names by date range.

        ## 2) Request your full chart when portal data is incomplete
        Ask Kaiser Georgia Release of Information/Health Information Management for your **designated record set** (or clearly list what you need: encounters, labs, imaging reports, operative notes, billing records, etc.).

        Include:
        - Full legal name (and prior names if relevant)
        - Date of birth
        - Member/medical record number (if known)
        - Date range requested
        - Exact record types needed
        - Delivery format (PDF, portal release, secure email, mail)
        - Where records should be sent (you, another doctor, attorney, insurer)

        ## 3) Copy/paste request template
        Subject: Medical records request (HIPAA right of access)

        Hello Kaiser Permanente Georgia Release of Information team,

        I am requesting a copy of my medical records under my HIPAA right of access.

        Name: [FULL NAME]
        Date of birth: [MM/DD/YYYY]
        Member/Medical record number: [IF KNOWN]
        Date range requested: [START] to [END]

        Please provide:
        [LIST RECORD TYPES YOU WANT]

        Delivery preference:
        [PORTAL DOWNLOAD / SECURE EMAIL / MAILED COPY]

        Send to:
        [YOUR EMAIL/ADDRESS OR RECEIVING PROVIDER DETAILS]

        Please confirm receipt and let me know if you need an authorization form or identity verification.

        Thank you,
        [YOUR NAME]
        [PHONE]

        ## 4) Timeline and follow-up
        - HIPAA access requests are generally fulfilled within **30 days** (with a possible extension in some cases).
        - If you do not receive confirmation, follow up in writing and keep timestamps/screenshots.
        - If a specific item is denied or missing, ask for the denial reason and how to appeal/correct the request scope.

        ## 5) Important edge cases
        - For minors/dependents, include guardian documents if required.
        - Behavioral health/substance-use records can require extra authorization language.
        - Imaging may need a separate request channel from standard chart notes.

        Note: Contact paths can change by facility. Use the current Kaiser Georgia Release of Information channel listed in your portal or facility contact page.
        """
    }

    private func buildGenericUSRecordsGuide(provider: String, state: String?) -> String {
        let stateLine: String
        if let state, !state.isEmpty {
            stateLine = " (\(state))"
        } else {
            stateLine = ""
        }

        return """
        # Medical Records Request Guide — \(provider)\(stateLine)

        ## 1) Check portal download first
        1. Sign in to the provider portal.
        2. Export available records (visit summaries, labs, medications, immunizations, imaging reports).
        3. Save copies before requesting additional documents.

        ## 2) Request full records (HIPAA right of access)
        Contact the provider's Release of Information/Health Information Management office and request your records in writing.

        Include:
        - Full name and date of birth
        - Patient/member/medical record number (if known)
        - Date range
        - Exact record categories
        - Delivery format and destination

        ## 3) Copy/paste template
        Subject: Medical records request (HIPAA right of access)

        Hello \(provider) Release of Information team,

        I am requesting a copy of my medical records under my HIPAA right of access.
        Name: [FULL NAME]
        DOB: [MM/DD/YYYY]
        Date range: [START] to [END]
        Records requested: [LIST]
        Delivery method: [PORTAL / EMAIL / MAIL]

        Please confirm receipt and let me know if you require identity verification or an authorization form.

        Thank you,
        [YOUR NAME]
        [PHONE]

        ## 4) Timing
        HIPAA requests are generally fulfilled within 30 days (extensions are sometimes allowed).
        """
    }
}
