import SwiftUI
import UIKit

@main
struct EirViewerApp: App {
    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var chatThreadStore = ChatThreadStore()
    @StateObject private var agentMemoryStore = AgentMemoryStore()
    @StateObject private var localModelManager = LocalModelManager()
    @StateObject private var healthDataExtractor = HealthDataExtractor()

    init() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = UIColor(AppColors.background.opacity(0.94))
        navAppearance.shadowColor = UIColor(AppColors.border.opacity(0.45))
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(AppColors.text)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppColors.text)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppColors.primaryStrong)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(AppColors.backgroundElevated)
        tabAppearance.shadowColor = UIColor(AppColors.border.opacity(0.7))

        let active = UIColor(AppColors.primaryStrong)
        let inactive = UIColor(AppColors.textTertiary)
        [tabAppearance.stackedLayoutAppearance,
         tabAppearance.inlineLayoutAppearance,
         tabAppearance.compactInlineLayoutAppearance].forEach { appearance in
            appearance.selected.iconColor = active
            appearance.selected.titleTextAttributes = [.foregroundColor: active]
            appearance.normal.iconColor = inactive
            appearance.normal.titleTextAttributes = [.foregroundColor: inactive]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

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
                .onOpenURL { url in
                    let ext = url.pathExtension.lowercased()
                    guard ext == "eir" || ext == "yaml" || ext == "yml" else { return }
                    if let profile = profileStore.addProfile(displayName: "", fileURL: url) {
                        profileStore.selectProfile(profile.id)
                    }
                }
        }
    }
}
