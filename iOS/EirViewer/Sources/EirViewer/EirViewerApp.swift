import GoogleSignIn
import SwiftUI

@main
struct EirViewerApp: App {
    init() {
        _ = EirAuthService.shared
    }

    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var chatThreadStore = ChatThreadStore()
    @StateObject private var agentMemoryStore = AgentMemoryStore()
    @StateObject private var localModelManager = LocalModelManager()
    @StateObject private var healthDataExtractor = HealthDataExtractor()
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var actionsVM = ActionsViewModel()
    @StateObject private var forYouVM = ForYouViewModel()
    @StateObject private var nextBestActionVM = NextBestHealthActionViewModel()
    @StateObject private var stateActionVM = StateActionRecommendationViewModel()
    @StateObject private var journalTranslationStore = JournalTranslationStore()
    @StateObject private var caseWikiVM = CaseWikiViewModel()
    @StateObject private var assessmentStore = AssessmentHistoryStore()
    @StateObject private var stateCheckInStore = StateCheckInStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentVM)
                .environmentObject(chatVM)
                .environmentObject(settingsVM)
                .environmentObject(profileStore)
                .environmentObject(chatThreadStore)
                .environmentObject(agentMemoryStore)
                .environmentObject(localModelManager)
                .environmentObject(healthDataExtractor)
                .environmentObject(purchaseManager)
                .environmentObject(actionsVM)
                .environmentObject(forYouVM)
                .environmentObject(nextBestActionVM)
                .environmentObject(stateActionVM)
                .environmentObject(journalTranslationStore)
                .environmentObject(caseWikiVM)
                .environmentObject(assessmentStore)
                .environmentObject(stateCheckInStore)
                .environment(\.locale, settingsVM.interfaceLocale)
                .environment(\.layoutDirection, settingsVM.interfaceLayoutDirection)
                .task {
                    guard !AppRuntimeContext.isRunningTests else { return }
                    await localModelManager.prewarmPreferredModelIfNeeded(
                        activeProviderType: settingsVM.activeProviderType
                    )
                }
                .onChange(of: settingsVM.activeProviderType) { _, providerType in
                    guard !AppRuntimeContext.isRunningTests else { return }
                    Task {
                        await localModelManager.prewarmPreferredModelIfNeeded(
                            activeProviderType: providerType
                        )
                    }
                }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "eir" || ext == "yaml" || ext == "yml" else { return }
                    if let profile = profileStore.addProfile(displayName: "", fileURL: url) {
                        profileStore.selectProfile(profile.id)
                    }
                }
        }
    }
}
