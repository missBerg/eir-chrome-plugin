import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var providers: [LLMProviderConfig]
    @Published var activeProviderType: LLMProviderType
    @Published var activePromptVersionId: String {
        didSet {
            UserDefaults.standard.set(activePromptVersionId, forKey: "eir_active_prompt_version")
        }
    }
    @Published var customPrompts: [PromptVersion] {
        didSet { saveCustomPrompts() }
    }
    @Published private(set) var managedAccessSnapshots: [LLMProviderType: ManagedCloudAccessSnapshot]

    init() {
        self.providers = Self.loadProviders()
        self.activeProviderType = Self.loadActiveProvider()
        self.activePromptVersionId = UserDefaults.standard.string(forKey: "eir_active_prompt_version")
            ?? PromptLibrary.defaultVersionId
        self.customPrompts = Self.loadCustomPrompts()
        self.managedAccessSnapshots = Self.loadManagedAccessSnapshots()
    }

    var activeProvider: LLMProviderConfig? {
        providers.first(where: { $0.type == activeProviderType })
    }

    var allPromptVersions: [PromptVersion] {
        PromptLibrary.versions + customPrompts
    }

    var activePromptVersion: PromptVersion? {
        allPromptVersions.first(where: { $0.id == activePromptVersionId })
    }

    func addCustomPrompt(name: String, description: String, systemPrompt: String) {
        let prompt = PromptVersion(
            id: "custom_\(UUID().uuidString)",
            name: name,
            description: description,
            systemPrompt: systemPrompt
        )
        customPrompts.append(prompt)
    }

    func updateCustomPrompt(_ prompt: PromptVersion) {
        if let idx = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[idx] = prompt
        }
    }

    func deleteCustomPrompt(id: String) {
        customPrompts.removeAll { $0.id == id }
        if activePromptVersionId == id {
            activePromptVersionId = PromptLibrary.defaultVersionId
        }
    }

    func apiKey(for type: LLMProviderType) -> String {
        KeychainService.get(key: "eir_api_key_\(type.rawValue)") ?? ""
    }

    func setApiKey(_ key: String, for type: LLMProviderType) {
        if key.isEmpty {
            KeychainService.delete(key: "eir_api_key_\(type.rawValue)")
        } else {
            KeychainService.set(key: "eir_api_key_\(type.rawValue)", value: key)
        }
        objectWillChange.send()
    }

    func managedAccessSnapshot(for type: LLMProviderType) -> ManagedCloudAccessSnapshot? {
        managedAccessSnapshots[type]
    }

    func hasManagedAccessToken(for type: LLMProviderType) -> Bool {
        !managedAccessToken(for: type).isEmpty
    }

    func credentialIfAvailable(for type: LLMProviderType) -> String {
        if type.usesManagedTrialAccess {
            return managedAccessToken(for: type)
        }
        return apiKey(for: type)
    }

    @discardableResult
    func provisionManagedAccess(for config: LLMProviderConfig) async throws -> ManagedCloudAccessSnapshot {
        let normalizedBaseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBaseURL.isEmpty else {
            throw LLMError.requestFailed("Set the hosted Eir cloud URL before provisioning free credits.")
        }

        let bootstrap = try await ManagedCloudBootstrapClient.bootstrap(baseURLString: normalizedBaseURL)
        let token = bootstrap.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw LLMError.requestFailed("Cloud access was provisioned without a usable client token.")
        }

        KeychainService.set(key: managedAccessTokenKey(for: config.type), value: token)

        let snapshot = ManagedCloudAccessSnapshot(
            clientId: bootstrap.clientId,
            mode: bootstrap.mode,
            attestation: bootstrap.attestation,
            quota: bootstrap.quota,
            provisionedAt: Date(),
            bootstrapBaseURL: normalizedBaseURL
        )
        managedAccessSnapshots[config.type] = snapshot
        saveManagedAccessSnapshots()
        objectWillChange.send()
        return snapshot
    }

    func clearManagedAccess(for type: LLMProviderType) {
        KeychainService.delete(key: managedAccessTokenKey(for: type))
        managedAccessSnapshots.removeValue(forKey: type)
        saveManagedAccessSnapshots()
        objectWillChange.send()
    }

    func updateManagedAccessQuota(_ quota: ManagedCloudQuota, for type: LLMProviderType) {
        guard var snapshot = managedAccessSnapshots[type] else { return }
        snapshot = ManagedCloudAccessSnapshot(
            clientId: snapshot.clientId,
            mode: snapshot.mode,
            attestation: snapshot.attestation,
            quota: quota,
            provisionedAt: snapshot.provisionedAt,
            bootstrapBaseURL: snapshot.bootstrapBaseURL
        )
        managedAccessSnapshots[type] = snapshot
        saveManagedAccessSnapshots()
        objectWillChange.send()
    }

    func updateProvider(_ config: LLMProviderConfig) {
        if let idx = providers.firstIndex(where: { $0.type == config.type }) {
            let previous = providers[idx]
            providers[idx] = config

            if config.type.usesManagedTrialAccess &&
                previous.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) !=
                config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) {
                clearManagedAccess(for: config.type)
            }
        }
        saveProviders()
    }

    func setActiveProvider(_ type: LLMProviderType) {
        activeProviderType = type
        UserDefaults.standard.set(type.rawValue, forKey: "eir_active_provider")
    }

    private func saveProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: "eir_providers")
        }
    }

    private func saveCustomPrompts() {
        if let data = try? JSONEncoder().encode(customPrompts) {
            UserDefaults.standard.set(data, forKey: "eir_custom_prompts")
        }
    }

    private func saveManagedAccessSnapshots() {
        let payload = managedAccessSnapshots.map { ManagedCloudAccessRecord(type: $0.key, snapshot: $0.value) }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: "eir_managed_access_snapshots")
        }
    }

    private static func loadCustomPrompts() -> [PromptVersion] {
        if let data = UserDefaults.standard.data(forKey: "eir_custom_prompts"),
           let saved = try? JSONDecoder().decode([PromptVersion].self, from: data) {
            return saved
        }
        return []
    }

    private static func loadProviders() -> [LLMProviderConfig] {
        let sortOrder = Dictionary(uniqueKeysWithValues: LLMProviderType.allCases.enumerated().map { ($1, $0) })

        if let data = UserDefaults.standard.data(forKey: "eir_providers"),
           let saved = try? JSONDecoder().decode([LLMProviderConfig].self, from: data) {
            let existingTypes = Set(saved.map(\.type))
            let missing = LLMProviderType.allCases
                .filter { !existingTypes.contains($0) }
                .map { LLMProviderConfig(type: $0) }
            return (saved + missing).sorted {
                (sortOrder[$0.type] ?? .max) < (sortOrder[$1.type] ?? .max)
            }
        }

        return LLMProviderType.allCases.map { LLMProviderConfig(type: $0) }
    }

    private static func loadManagedAccessSnapshots() -> [LLMProviderType: ManagedCloudAccessSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: "eir_managed_access_snapshots"),
              let records = try? JSONDecoder().decode([ManagedCloudAccessRecord].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: records.map { ($0.type, $0.snapshot) })
    }

    private static func loadActiveProvider() -> LLMProviderType {
        if let raw = UserDefaults.standard.string(forKey: "eir_active_provider"),
           let type = LLMProviderType(rawValue: raw) {
            return type
        }
        return .bergetTrial
    }

    private func managedAccessToken(for type: LLMProviderType) -> String {
        KeychainService.get(key: managedAccessTokenKey(for: type))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func managedAccessTokenKey(for type: LLMProviderType) -> String {
        "eir_managed_cloud_token_\(type.storageSlug)"
    }
}

private struct ManagedCloudAccessRecord: Codable {
    let type: LLMProviderType
    let snapshot: ManagedCloudAccessSnapshot
}

struct ManagedCloudAccessSnapshot: Codable {
    let clientId: String
    let mode: String
    let attestation: ManagedCloudBootstrapAttestation?
    let quota: ManagedCloudQuota
    let provisionedAt: Date
    let bootstrapBaseURL: String
}

struct ManagedCloudQuota: Codable {
    struct UsageBlock: Codable {
        let requests: Int
        let audioSeconds: Int
        let estimatedCostUsd: Double
    }

    let used: UsageBlock
    let limits: UsageBlock
    let remaining: UsageBlock
}

struct ManagedCloudBootstrapAttestation: Codable, Sendable {
    let provider: String
    let status: String
    let isSupported: Bool
    let keyID: String?
    let evidence: String?
}

private struct ManagedCloudBootstrapResponse: Decodable {
    let clientId: String
    let bearerToken: String
    let mode: String
    let attestation: ManagedCloudBootstrapAttestation?
    let quota: ManagedCloudQuota
}

private struct ManagedCloudBootstrapError: Decodable {
    let error: String
}

private struct ManagedCloudBootstrapContext {
    let installID: String
    let platform: String
    let attestation: ManagedCloudBootstrapAttestation
}

private enum ManagedCloudBootstrapClient {
    private static let installIDKey = "eir_managed_cloud_install_id_macos"

    private struct RequestBody: Encodable {
        let installId: String
        let platform: String
        let attestation: ManagedCloudBootstrapAttestation
    }

    static func bootstrap(baseURLString: String) async throws -> ManagedCloudBootstrapResponse {
        let normalizedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: normalizedBaseURL) else {
            throw LLMError.requestFailed("The hosted Eir cloud URL is not valid.")
        }

        let context = currentContext()

        var request = URLRequest(url: baseURL.appending(path: "client/bootstrap"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                installId: context.installID,
                platform: context.platform,
                attestation: context.attestation
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let payload = try? JSONDecoder().decode(ManagedCloudBootstrapError.self, from: data)
            let message = payload?.error ?? String(data: data, encoding: .utf8) ?? "Cloud bootstrap failed."
            throw LLMError.requestFailed(message)
        }

        return try JSONDecoder().decode(ManagedCloudBootstrapResponse.self, from: data)
    }

    private static func currentContext() -> ManagedCloudBootstrapContext {
        ManagedCloudBootstrapContext(
            installID: installID(),
            platform: "macos",
            attestation: ManagedCloudBootstrapAttestation(
                provider: "none",
                status: "unavailable",
                isSupported: false,
                keyID: nil,
                evidence: nil
            )
        )
    }

    private static func installID() -> String {
        let stored = KeychainService.get(key: installIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty {
            return stored
        }

        let generated = UUID().uuidString.lowercased()
        KeychainService.set(key: installIDKey, value: generated)
        return generated
    }
}
