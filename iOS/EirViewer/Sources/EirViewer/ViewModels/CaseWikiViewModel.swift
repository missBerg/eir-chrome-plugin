import Foundation

@MainActor
final class CaseWikiViewModel: ObservableObject {
    @Published private(set) var wiki: PatientCaseWiki?
    @Published private(set) var isBuilding = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusMessage = ""
    @Published var errorMessage: String?
    @Published var pendingCloudConsent: LLMProviderType?

    private var loadedProfileID: UUID?
    private var currentSignature: String?
    private var buildTask: Task<Void, Never>?

    var needsRebuild: Bool {
        guard let wiki, let currentSignature else { return currentSignature != nil }
        return wiki.documentSignature != currentSignature
    }

    var hasWiki: Bool {
        wiki != nil
    }

    func loadAndSync(profileID: UUID?, document: EirDocument?) {
        guard let profileID else {
            wiki = nil
            loadedProfileID = nil
            currentSignature = nil
            return
        }

        if loadedProfileID != profileID {
            loadedProfileID = profileID
            wiki = EncryptedStore.load(PatientCaseWiki.self, forKey: storageKey(profileID))
            errorMessage = nil
        }

        if let document {
            currentSignature = CaseSourceCardBuilder.documentSignature(for: document)
        } else {
            currentSignature = nil
        }
    }

    func autoBuildIfAllowed(
        profileID: UUID?,
        document: EirDocument?,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async {
        guard let profileID, let document, !isBuilding else { return }
        loadAndSync(profileID: profileID, document: document)
        guard needsRebuild else { return }
        guard let provider = settingsVM.activeProvider else { return }
        if provider.type.isLocal || ChatViewModel.hasCloudConsent(for: provider.type) {
            await build(
                profileID: profileID,
                document: document,
                settingsVM: settingsVM,
                localModelManager: localModelManager,
                requestConsentIfNeeded: false
            )
        }
    }

    func build(
        profileID: UUID?,
        document: EirDocument?,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager,
        requestConsentIfNeeded: Bool = true
    ) async {
        guard let profileID, let document else {
            errorMessage = "Import records before building a case wiki."
            return
        }
        guard let provider = settingsVM.activeProvider else {
            errorMessage = "Choose an AI provider in Settings before building a case wiki."
            return
        }

        if !provider.type.isLocal && !ChatViewModel.hasCloudConsent(for: provider.type) {
            if requestConsentIfNeeded {
                pendingCloudConsent = provider.type
            }
            return
        }

        buildTask?.cancel()
        isBuilding = true
        progress = 0
        statusMessage = "Starting case wiki"
        errorMessage = nil

        let service = CaseWikiIngestService()
        buildTask = Task {
            do {
                let built = try await service.buildWiki(
                    profileID: profileID,
                    document: document,
                    settingsVM: settingsVM,
                    localModelManager: localModelManager
                ) { [weak self] update in
                    self?.progress = update.progress
                    self?.statusMessage = update.status
                }

                guard !Task.isCancelled else { return }
                wiki = built
                currentSignature = built.documentSignature
                EncryptedStore.save(built, forKey: storageKey(profileID))
                progress = 1
                statusMessage = "Case wiki ready"
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                statusMessage = "Case wiki failed"
            }
            isBuilding = false
        }

        await buildTask?.value
    }

    func grantConsentAndBuild(
        profileID: UUID?,
        document: EirDocument?,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async {
        guard let provider = pendingCloudConsent else { return }
        ChatViewModel.grantCloudConsent(for: provider)
        pendingCloudConsent = nil

        if provider.usesManagedTrialAccess,
           let config = settingsVM.providers.first(where: { $0.type == provider }) {
            do {
                _ = try await settingsVM.provisionManagedAccess(for: config)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        await build(
            profileID: profileID,
            document: document,
            settingsVM: settingsVM,
            localModelManager: localModelManager,
            requestConsentIfNeeded: false
        )
    }

    func denyConsent() {
        pendingCloudConsent = nil
    }

    private func storageKey(_ profileID: UUID) -> String {
        "eir_case_wiki_v1_\(profileID.uuidString)"
    }
}
