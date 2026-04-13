import StoreKit
import SwiftUI

#if canImport(DeviceCheck)
import DeviceCheck
#endif

private let managedCloudKeyVersion = "v2"

enum ResponseLanguagePreference: String, CaseIterable, Identifiable, Codable {
    case automatic
    case english
    case swedish
    case arabic
    case finnish
    case polish
    case somali

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .english:
            return "English"
        case .swedish:
            return "Swedish"
        case .arabic:
            return "Arabic"
        case .finnish:
            return "Finnish"
        case .polish:
            return "Polish"
        case .somali:
            return "Somali"
        }
    }

    var explicitLanguage: SupportedChatLanguage? {
        switch self {
        case .automatic:
            return nil
        case .english:
            return .english
        case .swedish:
            return .swedish
        case .arabic:
            return .arabic
        case .finnish:
            return .finnish
        case .polish:
            return .polish
        case .somali:
            return .somali
        }
    }
}

enum SupportedChatLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case swedish = "sv"
    case arabic = "ar"
    case finnish = "fi"
    case polish = "pl"
    case somali = "so"

    var id: String { rawValue }

    static let swedenPriorityLanguages: [SupportedChatLanguage] = [
        .swedish,
        .english,
        .arabic,
        .finnish,
        .polish,
        .somali,
    ]

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .swedish:
            return "Swedish"
        case .arabic:
            return "Arabic"
        case .finnish:
            return "Finnish"
        case .polish:
            return "Polish"
        case .somali:
            return "Somali"
        }
    }

    var promptName: String {
        switch self {
        case .english:
            return "English"
        case .swedish:
            return "Swedish"
        case .arabic:
            return "Arabic"
        case .finnish:
            return "Finnish"
        case .polish:
            return "Polish"
        case .somali:
            return "Somali"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en-US"
        case .swedish:
            return "sv-SE"
        case .arabic:
            return "ar"
        case .finnish:
            return "fi-FI"
        case .polish:
            return "pl-PL"
        case .somali:
            return "so-SO"
        }
    }

    var usesRightToLeftLayout: Bool {
        self == .arabic
    }

    static func from(localeIdentifier: String) -> SupportedChatLanguage {
        let normalized = localeIdentifier.lowercased()
        if normalized.hasPrefix("sv") { return .swedish }
        if normalized.hasPrefix("ar") { return .arabic }
        if normalized.hasPrefix("fi") { return .finnish }
        if normalized.hasPrefix("pl") { return .polish }
        if normalized.hasPrefix("so") { return .somali }
        return .english
    }
}

enum InterfaceLanguagePreference: String, CaseIterable, Identifiable, Codable {
    case system
    case english
    case swedish
    case arabic
    case finnish
    case polish
    case somali

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .english:
            return "English"
        case .swedish:
            return "Svenska"
        case .arabic:
            return "العربية"
        case .finnish:
            return "Suomi"
        case .polish:
            return "Polski"
        case .somali:
            return "Soomaali"
        }
    }

    var explicitLanguage: SupportedChatLanguage? {
        switch self {
        case .system:
            return nil
        case .english:
            return .english
        case .swedish:
            return .swedish
        case .arabic:
            return .arabic
        case .finnish:
            return .finnish
        case .polish:
            return .polish
        case .somali:
            return .somali
        }
    }
}

@MainActor
class SettingsViewModel: ObservableObject {
    static let eirTrialRequestsPerToken = 100
    static let eirTrialDailyTokenGrant = 10
    static let hostedClientKeyVersion = managedCloudKeyVersion
    private static let localDefaultMigrationKey = "eir_default_provider_local_migration_v1"
    private static let providerSelectionKey = "eir_has_explicitly_selected_provider_v1"
    private static let voiceTranscriptPolishKey = "eir_voice_transcript_polish_enabled_v1"
    private static let responseLanguageKey = "eir_response_language_preference_v1"
    private static let interfaceLanguageKey = "eir_interface_language_preference_v1"
    private static let openAIAccountSessionKey = "eir_openai_account_session_v1"
    private static let openAIAvailableModelsKey = "eir_openai_available_models_v1"

    @Published var providers: [LLMProviderConfig]
    @Published var activeProviderType: LLMProviderType
    @Published var activePromptVersionId: String {
        didSet {
            UserDefaults.standard.set(activePromptVersionId, forKey: "eir_active_prompt_version")
        }
    }
    @Published var voiceTranscriptPolishEnabled: Bool {
        didSet {
            UserDefaults.standard.set(voiceTranscriptPolishEnabled, forKey: Self.voiceTranscriptPolishKey)
        }
    }
    @Published var responseLanguagePreference: ResponseLanguagePreference {
        didSet {
            UserDefaults.standard.set(responseLanguagePreference.rawValue, forKey: Self.responseLanguageKey)
        }
    }
    @Published var interfaceLanguagePreference: InterfaceLanguagePreference {
        didSet {
            UserDefaults.standard.set(interfaceLanguagePreference.rawValue, forKey: Self.interfaceLanguageKey)
        }
    }
    @Published var customPrompts: [PromptVersion] {
        didSet { saveCustomPrompts() }
    }
    @Published private(set) var managedAccessSnapshots: [LLMProviderType: ManagedCloudAccessSnapshot]
    @Published private(set) var openAIAccountSession: OpenAIAccountSession?
    @Published private(set) var pendingOpenAIDeviceCode: OpenAIDeviceCode?
    @Published private(set) var isOpenAIAccountBusy = false
    @Published private(set) var openAIAvailableModels: [String]
    @Published private(set) var isRefreshingOpenAIModels = false
    @Published var openAIAccountError: String?

    private let openAIAccountAuthService = OpenAIAccountAuthService()
    private var openAIAccountPollingTask: Task<Void, Never>?

    init() {
        let saved = Self.loadProviders()
        self.providers = saved
        self.activeProviderType = Self.loadActiveProvider()
        self.activePromptVersionId = UserDefaults.standard.string(forKey: "eir_active_prompt_version")
            ?? PromptLibrary.defaultVersionId
        self.voiceTranscriptPolishEnabled = UserDefaults.standard.object(forKey: Self.voiceTranscriptPolishKey) as? Bool ?? true
        self.responseLanguagePreference = Self.loadResponseLanguagePreference()
        self.interfaceLanguagePreference = Self.loadInterfaceLanguagePreference()
        self.customPrompts = Self.loadCustomPrompts()
        self.managedAccessSnapshots = Self.loadManagedAccessSnapshots()
        self.openAIAccountSession = Self.loadOpenAIAccountSession()
        self.openAIAvailableModels = Self.loadOpenAIAvailableModels()

        if !(PromptLibrary.versions + customPrompts).contains(where: { $0.id == activePromptVersionId }) {
            self.activePromptVersionId = PromptLibrary.defaultVersionId
        }

        if Self.shouldForceLocalDefault(current: activeProviderType) {
            self.activeProviderType = .local
            UserDefaults.standard.set(LLMProviderType.local.rawValue, forKey: "eir_active_provider")
            UserDefaults.standard.set(true, forKey: Self.localDefaultMigrationKey)
        }
    }

    deinit {
        openAIAccountPollingTask?.cancel()
    }

    var activeProvider: LLMProviderConfig? {
        providers.first(where: { $0.type == activeProviderType })
    }

    /// All available prompts: built-in + custom
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

    func deleteCustomPrompt(_ id: String) {
        customPrompts.removeAll { $0.id == id }
        if activePromptVersionId == id {
            activePromptVersionId = PromptLibrary.defaultVersionId
        }
    }

    private func saveCustomPrompts() {
        if let data = try? JSONEncoder().encode(customPrompts) {
            UserDefaults.standard.set(data, forKey: "eir_custom_prompts")
        }
    }

    private func saveManagedAccessSnapshots() {
        let payload = managedAccessSnapshots.map { ManagedAccessRecord(type: $0.key, snapshot: $0.value) }
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

    private static func loadResponseLanguagePreference() -> ResponseLanguagePreference {
        guard let raw = UserDefaults.standard.string(forKey: Self.responseLanguageKey),
              let preference = ResponseLanguagePreference(rawValue: raw) else {
            return .automatic
        }
        return preference
    }

    private static func loadInterfaceLanguagePreference() -> InterfaceLanguagePreference {
        guard let raw = UserDefaults.standard.string(forKey: Self.interfaceLanguageKey),
              let preference = InterfaceLanguagePreference(rawValue: raw) else {
            return .system
        }
        return preference
    }

    var resolvedInterfaceLanguage: SupportedChatLanguage {
        if let explicit = interfaceLanguagePreference.explicitLanguage {
            return explicit
        }
        let preferredLanguage = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        return SupportedChatLanguage.from(localeIdentifier: preferredLanguage)
    }

    var interfaceLocale: Locale {
        Locale(identifier: resolvedInterfaceLanguage.localeIdentifier)
    }

    var interfaceLayoutDirection: LayoutDirection {
        resolvedInterfaceLanguage.usesRightToLeftLayout ? .rightToLeft : .leftToRight
    }

    func apiKey(for type: LLMProviderType) -> String {
        KeychainService.get(key: "eir_api_key_\(type.rawValue)") ?? ""
    }

    func hasStoredCredential(for type: LLMProviderType) -> Bool {
        if type == .openai {
            return openAIAccountSession != nil || !apiKey(for: type).isEmpty
        }
        if type.usesManagedTrialAccess {
            return hasManagedAccessToken(for: type)
        }
        return !apiKey(for: type).isEmpty
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

    func resolvedCredential(for config: LLMProviderConfig) async throws -> String {
        if config.type.usesManagedTrialAccess {
            let existing = managedAccessToken(for: config.type)
            if !existing.isEmpty {
                return existing
            }

            _ = try await provisionManagedAccess(for: config)
            let token = managedAccessToken(for: config.type)
            guard !token.isEmpty else {
                throw LLMError.requestFailed("Trial access was provisioned, but no usable cloud token was returned.")
            }
            return token
        }

        if config.type == .openai, let session = openAIAccountSession {
            do {
                let refreshed = try await openAIAccountAuthService.usableSession(from: session)
                if refreshed != session {
                    storeOpenAIAccountSession(refreshed)
                }
                return refreshed.accessToken
            } catch {
                let fallbackKey = apiKey(for: config.type)
                if !fallbackKey.isEmpty {
                    return fallbackKey
                }
                throw error
            }
        }

        let key = apiKey(for: config.type)
        guard !key.isEmpty else {
            throw LLMError.noAPIKey
        }
        return key
    }

    func startOpenAIAccountSignIn() async {
        openAIAccountPollingTask?.cancel()
        openAIAccountError = nil
        isOpenAIAccountBusy = true

        do {
            let deviceCode = try await openAIAccountAuthService.requestDeviceCode()
            pendingOpenAIDeviceCode = deviceCode
            isOpenAIAccountBusy = false

            openAIAccountPollingTask = Task { [weak self] in
                guard let self else { return }
                await self.finishOpenAIAccountSignIn(with: deviceCode)
            }
        } catch {
            pendingOpenAIDeviceCode = nil
            isOpenAIAccountBusy = false
            openAIAccountError = error.localizedDescription
        }
    }

    func cancelOpenAIAccountSignIn() {
        openAIAccountPollingTask?.cancel()
        openAIAccountPollingTask = nil
        pendingOpenAIDeviceCode = nil
        isOpenAIAccountBusy = false
    }

    func refreshOpenAIAccountSignInStatus() async {
        guard let deviceCode = pendingOpenAIDeviceCode else { return }
        guard !isOpenAIAccountBusy else { return }
        openAIAccountPollingTask?.cancel()
        isOpenAIAccountBusy = true

        openAIAccountPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.finishOpenAIAccountSignIn(with: deviceCode)
        }
    }

    func disconnectOpenAIAccount() {
        cancelOpenAIAccountSignIn()
        openAIAccountError = nil
        clearOpenAIAccountSession()
        setOpenAIAvailableModels([])
    }

    func refreshOpenAIAvailableModels(force: Bool = false) async {
        guard let session = openAIAccountSession else { return }
        if isRefreshingOpenAIModels { return }
        if !force && !openAIAvailableModels.isEmpty { return }

        isRefreshingOpenAIModels = true
        defer { isRefreshingOpenAIModels = false }

        do {
            let usable = try await openAIAccountAuthService.usableSession(from: session)
            if usable != session {
                storeOpenAIAccountSession(usable)
            }

            let models = try await openAIAccountAuthService.fetchAvailableModels(accessToken: usable.accessToken)
            setOpenAIAvailableModels(models)
            applyBestAvailableOpenAIModelIfNeeded(from: models)
        } catch {
            if force {
                openAIAccountError = error.localizedDescription
            }
        }
    }

    private func finishOpenAIAccountSignIn(with deviceCode: OpenAIDeviceCode) async {
        do {
            let session = try await openAIAccountAuthService.completeDeviceCodeLogin(deviceCode: deviceCode)
            guard !Task.isCancelled else { return }
            storeOpenAIAccountSession(session)
            applyOpenAICodexDefaultsIfNeeded()
            await refreshOpenAIAvailableModels(force: true)
            pendingOpenAIDeviceCode = nil
            isOpenAIAccountBusy = false
            openAIAccountError = nil
        } catch is CancellationError {
            isOpenAIAccountBusy = false
        } catch {
            pendingOpenAIDeviceCode = nil
            isOpenAIAccountBusy = false
            openAIAccountError = error.localizedDescription
        }
    }

    @discardableResult
    func provisionManagedAccess(for config: LLMProviderConfig) async throws -> ManagedCloudAccessSnapshot {
        let normalizedBaseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBaseURL.isEmpty else {
            throw LLMError.requestFailed("Set the hosted Eir cloud API URL before provisioning trial credits.")
        }

        let bootstrap = try await ManagedCloudBootstrapClient.bootstrap(baseURLString: normalizedBaseURL)
        let token = bootstrap.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw LLMError.requestFailed("Secure cloud access setup completed without a usable client token.")
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
        if UserDefaults.standard.object(forKey: trialStartedAtKey(for: config.type)) == nil {
            UserDefaults.standard.set(snapshot.provisionedAt, forKey: trialStartedAtKey(for: config.type))
        }
        saveManagedAccessSnapshots()
        objectWillChange.send()
        return snapshot
    }

    func clearManagedAccess(for type: LLMProviderType) {
        KeychainService.delete(key: managedAccessTokenKey(for: type))
        managedAccessSnapshots.removeValue(forKey: type)
        UserDefaults.standard.removeObject(forKey: trialStartedAtKey(for: type))
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

    @discardableResult
    func syncBillingPurchases(_ purchases: [BillingPurchaseClaim], for type: LLMProviderType) async throws -> ManagedCloudAccessSnapshot {
        guard let config = providers.first(where: { $0.type == type }) else {
            throw LLMError.noProvider
        }

        let token = try await resolvedCredential(for: config)
        let normalizedBaseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedBaseURL)?.appending(path: "client/billing/sync") else {
            throw LLMError.requestFailed("The hosted Eir cloud billing URL is not valid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(BillingPurchaseSyncRequest(purchases: purchases))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let payload = try? JSONDecoder().decode(ManagedCloudBootstrapError.self, from: data)
            let message = payload?.error ?? String(data: data, encoding: .utf8) ?? "Billing sync failed."
            throw LLMError.requestFailed(message)
        }

        let payload = try JSONDecoder().decode(BillingPurchaseSyncResponse.self, from: data)
        let snapshot = ManagedCloudAccessSnapshot(
            clientId: payload.clientId,
            mode: payload.mode,
            attestation: managedAccessSnapshots[type]?.attestation,
            quota: payload.quota,
            provisionedAt: managedAccessSnapshots[type]?.provisionedAt ?? Date(),
            bootstrapBaseURL: normalizedBaseURL
        )
        managedAccessSnapshots[type] = snapshot
        saveManagedAccessSnapshots()
        objectWillChange.send()
        return snapshot
    }

    func updateProvider(_ config: LLMProviderConfig) {
        if let idx = providers.firstIndex(where: { $0.type == config.type }) {
            let oldConfig = providers[idx]
            providers[idx] = config

            if config.type.usesManagedTrialAccess &&
                oldConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) !=
                config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) {
                clearManagedAccess(for: config.type)
            }
        }
        saveProviders()
    }

    func setActiveProvider(_ type: LLMProviderType) {
        activeProviderType = type
        UserDefaults.standard.set(type.rawValue, forKey: "eir_active_provider")
        UserDefaults.standard.set(true, forKey: Self.providerSelectionKey)
    }

    private func saveProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: "eir_providers")
        }
    }

    private static func loadProviders() -> [LLMProviderConfig] {
        let sortOrder = Dictionary(uniqueKeysWithValues: LLMProviderType.allCases.enumerated().map { ($1, $0) })

        if let data = UserDefaults.standard.data(forKey: "eir_providers"),
           let saved = try? JSONDecoder().decode([LLMProviderConfig].self, from: data) {
            // Merge in any new provider types that were added since last save
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
              let records = try? JSONDecoder().decode([ManagedAccessRecord].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: records.map { ($0.type, $0.snapshot) })
    }

    private static func loadActiveProvider() -> LLMProviderType {
        if let raw = UserDefaults.standard.string(forKey: "eir_active_provider"),
           let type = LLMProviderType(rawValue: raw) {
            return type
        }
        return .local
    }

    private static func loadOpenAIAccountSession() -> OpenAIAccountSession? {
        guard let raw = KeychainService.get(key: Self.openAIAccountSessionKey),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(OpenAIAccountSession.self, from: data)
    }

    private static func loadOpenAIAvailableModels() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: Self.openAIAvailableModelsKey),
              let models = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return models
    }

    private func storeOpenAIAccountSession(_ session: OpenAIAccountSession) {
        guard let data = try? JSONEncoder().encode(session),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        KeychainService.set(key: Self.openAIAccountSessionKey, value: raw)
        openAIAccountSession = session
        objectWillChange.send()
    }

    private func clearOpenAIAccountSession() {
        KeychainService.delete(key: Self.openAIAccountSessionKey)
        openAIAccountSession = nil
        objectWillChange.send()
    }

    private func setOpenAIAvailableModels(_ models: [String]) {
        openAIAvailableModels = models
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: Self.openAIAvailableModelsKey)
        }
    }

    private func applyOpenAICodexDefaultsIfNeeded() {
        guard let index = providers.firstIndex(where: { $0.type == .openai }) else { return }
        var config = providers[index]
        var changed = false

        if config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || config.model == "gpt-4.1" {
            config.model = "gpt-5.4"
            changed = true
        }

        if changed {
            providers[index] = config
            saveProviders()
        }
    }

    private func applyBestAvailableOpenAIModelIfNeeded(from models: [String]) {
        guard let index = providers.firstIndex(where: { $0.type == .openai }) else { return }
        guard let preferred = preferredOpenAIModel(from: models) else { return }

        let current = providers[index].model.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldReplace = current.isEmpty
            || current == LLMProviderType.openai.defaultModel
            || current == "gpt-5.4"
            || !models.contains(current)

        guard shouldReplace else { return }
        var config = providers[index]
        config.model = preferred
        providers[index] = config
        saveProviders()
    }

    private func preferredOpenAIModel(from models: [String]) -> String? {
        let priority = [
            "gpt-5.4",
            "gpt-5.2",
            "gpt-5.1",
            "gpt-5",
            "gpt-4.1",
            "gpt-4o",
        ]
        for candidate in priority where models.contains(candidate) {
            return candidate
        }
        return models.first
    }

    private static func shouldForceLocalDefault(current: LLMProviderType) -> Bool {
        if UserDefaults.standard.bool(forKey: Self.providerSelectionKey) {
            return false
        }
        if UserDefaults.standard.bool(forKey: Self.localDefaultMigrationKey) {
            return false
        }
        return current != .local
    }

    private func managedAccessToken(for type: LLMProviderType) -> String {
        KeychainService.get(key: managedAccessTokenKey(for: type))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func managedAccessTokenKey(for type: LLMProviderType) -> String {
        "eir_managed_cloud_token_\(type.storageSlug)_\(Self.hostedClientKeyVersion)"
    }

    private func trialStartedAtKey(for type: LLMProviderType) -> String {
        "eir_managed_cloud_trial_started_at_\(type.storageSlug)_\(Self.hostedClientKeyVersion)"
    }

    func eirTrialBalance(for snapshot: ManagedCloudAccessSnapshot, type: LLMProviderType, now: Date = Date()) -> EirTrialBalance {
        let calendar = Calendar.current
        let trialStartedAt = (UserDefaults.standard.object(forKey: trialStartedAtKey(for: type)) as? Date) ?? snapshot.provisionedAt
        let startDay = calendar.startOfDay(for: trialStartedAt)
        let currentDay = calendar.startOfDay(for: now)
        let elapsedDays = max(calendar.dateComponents([.day], from: startDay, to: currentDay).day ?? 0, 0)
        let totalTokens = (elapsedDays + 1) * Self.eirTrialDailyTokenGrant
        let usedRequests = max(snapshot.quota.used.requests, 0)
        let usedTokens = usedRequests == 0 ? 0 : Int(ceil(Double(usedRequests) / Double(Self.eirTrialRequestsPerToken)))

        return EirTrialBalance(
            usedTokens: usedTokens,
            totalTokens: totalTokens,
            remainingTokens: max(totalTokens - usedTokens, 0),
            requestsPerToken: Self.eirTrialRequestsPerToken,
            dailyTokenGrant: Self.eirTrialDailyTokenGrant
        )
    }
}

private struct ManagedAccessRecord: Codable {
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

struct EirTrialBalance {
    let usedTokens: Int
    let totalTokens: Int
    let remainingTokens: Int
    let requestsPerToken: Int
    let dailyTokenGrant: Int
}

struct BillingPurchaseClaim: Codable, Hashable, Identifiable {
    let transactionId: String
    let originalTransactionId: String
    let productId: String
    let productType: String
    let purchasedAt: Date
    let expiresAt: Date?
    let revokedAt: Date?

    var id: String { transactionId }
}

private struct BillingPurchaseSyncRequest: Encodable {
    let purchases: [BillingPurchaseClaim]
}

private struct BillingPurchaseSyncResponse: Decodable {
    let clientId: String
    let mode: String
    let quota: ManagedCloudQuota
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published var lastError: String?
    @Published var isLoading = false
    @Published var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    init() {
        guard !AppRuntimeContext.isRunningTests else { return }

        updatesTask = Task {
            await observeTransactionUpdates()
        }

        Task {
            await refreshProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var subscriptionProductID: String {
        Bundle.main.object(forInfoDictionaryKey: "EIRBillingSubscriptionProductID") as? String ?? ""
    }

    var topUpProductIDs: [String] {
        Bundle.main.object(forInfoDictionaryKey: "EIRBillingTopUpProductIDs") as? [String] ?? []
    }

    var hasBillingProducts: Bool {
        !allProductIDs.isEmpty
    }

    var subscriptionProduct: Product? {
        let id = subscriptionProductID
        guard !id.isEmpty else { return nil }
        return products.first(where: { $0.id == id })
    }

    var topUpProducts: [Product] {
        let ids = Set(topUpProductIDs)
        return products.filter { ids.contains($0.id) }
    }

    func refreshProducts() async {
        let ids = allProductIDs
        guard !ids.isEmpty else {
            products = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: ids).sorted { lhs, rhs in
                let lhsRank = productTypeRank(lhs.type)
                let rhsRank = productTypeRank(rhs.type)
                if lhsRank == rhsRank {
                    return lhs.price < rhs.price
                }
                return lhsRank < rhsRank
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            purchased.insert(transaction.productID)
        }
        purchasedProductIDs = purchased
    }

    @discardableResult
    func purchase(_ product: Product, settingsVM: SettingsViewModel) async throws -> ManagedCloudAccessSnapshot? {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verifiedTransaction(from: verification)
            let claim = BillingPurchaseClaim(
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                productId: transaction.productID,
                productType: productTypeName(transaction.productType),
                purchasedAt: transaction.purchaseDate,
                expiresAt: transaction.expirationDate,
                revokedAt: transaction.revocationDate
            )
            let snapshot = try await settingsVM.syncBillingPurchases([claim], for: .bergetTrial)
            await transaction.finish()
            await refreshEntitlements()
            return snapshot
        case .pending:
            lastError = "Purchase is pending approval."
            return nil
        case .userCancelled:
            return nil
        @unknown default:
            lastError = "Purchase failed."
            return nil
        }
    }

    @discardableResult
    func restorePurchases(settingsVM: SettingsViewModel) async throws -> ManagedCloudAccessSnapshot? {
        try await AppStore.sync()
        await refreshEntitlements()

        var claims: [BillingPurchaseClaim] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            claims.append(
                BillingPurchaseClaim(
                    transactionId: String(transaction.id),
                    originalTransactionId: String(transaction.originalID),
                    productId: transaction.productID,
                    productType: productTypeName(transaction.productType),
                    purchasedAt: transaction.purchaseDate,
                    expiresAt: transaction.expirationDate,
                    revokedAt: transaction.revocationDate
                )
            )
        }

        guard !claims.isEmpty else { return nil }
        return try await settingsVM.syncBillingPurchases(claims, for: .bergetTrial)
    }

    private var allProductIDs: [String] {
        var ids: [String] = []
        let subscription = subscriptionProductID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subscription.isEmpty {
            ids.append(subscription)
        }
        ids.append(contentsOf: topUpProductIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return Array(Set(ids))
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            do {
                let transaction = try verifiedTransaction(from: result)
                await refreshEntitlements()
                await transaction.finish()
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func verifiedTransaction(from result: VerificationResult<StoreKit.Transaction>) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw LLMError.requestFailed("Purchase verification failed.")
        }
    }

    private func productTypeName(_ type: Product.ProductType) -> String {
        switch type {
        case .autoRenewable:
            return "auto_renewable"
        case .consumable:
            return "consumable"
        case .nonConsumable:
            return "non_consumable"
        case .nonRenewable:
            return "non_renewing"
        default:
            return "unknown"
        }
    }

    private func productTypeRank(_ type: Product.ProductType) -> Int {
        switch type {
        case .autoRenewable:
            return 0
        case .consumable:
            return 1
        case .nonConsumable:
            return 2
        case .nonRenewable:
            return 3
        default:
            return 4
        }
    }
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
    private static let installIDKey = "eir_managed_cloud_install_id_\(managedCloudKeyVersion)"
    private static let appAttestKeyIDKey = "eir_managed_cloud_app_attest_key_id_\(managedCloudKeyVersion)"

    private struct RequestBody: Encodable {
        let installId: String
        let platform: String
        let attestation: ManagedCloudBootstrapAttestation
    }

    static func bootstrap(baseURLString: String) async throws -> ManagedCloudBootstrapResponse {
        let normalizedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: normalizedBaseURL) else {
            throw LLMError.requestFailed("The hosted Eir cloud API URL is not valid.")
        }

        let context = await currentContext()

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
            let message = payload?.error ?? String(data: data, encoding: .utf8) ?? "Secure cloud access setup failed."
            throw LLMError.requestFailed(message)
        }

        return try JSONDecoder().decode(ManagedCloudBootstrapResponse.self, from: data)
    }

    private static func currentContext() async -> ManagedCloudBootstrapContext {
        ManagedCloudBootstrapContext(
            installID: installID(),
            platform: "ios",
            attestation: await attestation()
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

    private static func attestation() async -> ManagedCloudBootstrapAttestation {
#if canImport(DeviceCheck)
        if #available(iOS 14.0, *), DCAppAttestService.shared.isSupported {
            let keyID = await appAttestKeyID()
            return ManagedCloudBootstrapAttestation(
                provider: "app_attest",
                status: keyID == nil ? "supported_uninitialized" : "supported_key_ready",
                isSupported: true,
                keyID: keyID,
                evidence: nil
            )
        }
#endif

        return ManagedCloudBootstrapAttestation(
            provider: "none",
            status: "unavailable",
            isSupported: false,
            keyID: nil,
            evidence: nil
        )
    }

#if canImport(DeviceCheck)
    @available(iOS 14.0, *)
    private static func appAttestKeyID() async -> String? {
        let stored = KeychainService.get(key: appAttestKeyIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty {
            return stored
        }

        do {
            let generated: String = try await withCheckedThrowingContinuation { continuation in
                DCAppAttestService.shared.generateKey { keyID, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: keyID ?? "")
                }
            }

            let normalized = generated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                return nil
            }

            KeychainService.set(key: appAttestKeyIDKey, value: normalized)
            return normalized
        } catch {
            return nil
        }
    }
#endif
}
