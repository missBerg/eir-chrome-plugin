import StoreKit
import SwiftUI
import HealthKit
import UIKit
import WebKit

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var agentMemoryStore: AgentMemoryStore
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    @State private var showingAddPerson = false
    @State private var showHealthKitImport = false
    @State private var renamingProfileID: UUID?
    @State private var renameText: String = ""

    var body: some View {
        Form {
            // MARK: - Eir Account
            Section("Eir Account") {
                NavigationLink {
                    EirAccountView()
                        .navigationTitle("Eir Account")
                } label: {
                    EirAccountRow()
                }
            }

            // MARK: - People
            Section("People") {
                ForEach(profileStore.profiles) { profile in
                    PersonRow(
                        profile: profile,
                        isSelected: profile.id == profileStore.selectedProfileID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        profileStore.selectProfile(profile.id)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            profileStore.removeProfile(profile.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            renameText = profile.displayName
                            renamingProfileID = profile.id
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(AppColors.primary)
                    }
                }

                Button {
                    showingAddPerson = true
                } label: {
                    Label("Add Person...", systemImage: "person.badge.plus")
                }

                if HKHealthStore.isHealthDataAvailable() {
                    Button {
                        showHealthKitImport = true
                    } label: {
                        Label("Import from Apple Health", systemImage: "heart.fill")
                    .foregroundColor(AppColors.pink)
                    }
                }
            }

            Section("Language") {
                Picker("App language", selection: $settingsVM.interfaceLanguagePreference) {
                    ForEach(InterfaceLanguagePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }

                Picker("Response language", selection: $settingsVM.responseLanguagePreference) {
                    ForEach(ResponseLanguagePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
            }

            Section("Chat") {
                if let profileID = profileStore.selectedProfileID {
                    Toggle(
                        "Show AI follow-up suggestions",
                        isOn: Binding(
                            get: { profileStore.showChatFollowUpSuggestions(for: profileID) },
                            set: { profileStore.setShowChatFollowUpSuggestions($0, for: profileID) }
                        )
                    )
                }
            }

            // MARK: - AI Provider
            Section("AI Provider") {
                Picker("Active Provider", selection: $settingsVM.activeProviderType) {
                    ForEach(LLMProviderType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            // MARK: - Local Models & Prompt Style (shown first when local is active)
            if settingsVM.activeProviderType.isLocal {
                ForEach(settingsVM.providers.filter({ $0.type.isLocal })) { config in
                    ProviderSection(config: config)
                        .environmentObject(settingsVM)
                }

                PromptStyleSection()
                    .environmentObject(settingsVM)
            }

            // MARK: - Cloud Provider Cards
            ForEach(settingsVM.providers.filter({ !$0.type.isLocal })) { config in
                ProviderSection(config: config)
                    .environmentObject(settingsVM)
            }

            // MARK: - Agent Configuration
            Section("Agent Configuration") {
                AgentConfigCard(
                    title: "Identity (SOUL.md)",
                    defaultContent: AgentDefaults.defaultSoul,
                    content: $agentMemoryStore.memory.soul
                )
                AgentConfigCard(
                    title: "User Profile (USER.md)",
                    defaultContent: AgentDefaults.defaultUser,
                    content: $agentMemoryStore.memory.user
                )
                AgentConfigCard(
                    title: "Memory (MEMORY.md)",
                    defaultContent: AgentDefaults.defaultMemory,
                    content: $agentMemoryStore.memory.memory
                )
                AgentConfigCard(
                    title: "Skills (AGENTS.md)",
                    defaultContent: AgentDefaults.defaultAgents,
                    content: $agentMemoryStore.memory.agents
                )
            }
            .onChange(of: agentMemoryStore.memory.soul) { _, _ in agentMemoryStore.save() }
            .onChange(of: agentMemoryStore.memory.user) { _, _ in agentMemoryStore.save() }
            .onChange(of: agentMemoryStore.memory.memory) { _, _ in agentMemoryStore.save() }
            .onChange(of: agentMemoryStore.memory.agents) { _, _ in agentMemoryStore.save() }

            // MARK: - Privacy & Data
            Section("Privacy & Data") {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(AppColors.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API keys are stored securely in Keychain")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text("On-device models keep all data on your phone")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text("Free Trial for Eir is hosted by Eir in Stockholm, with Berget providing the inference route")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                if hasAnyCloudConsent {
                    Button(role: .destructive) {
                        resetCloudConsent()
                    } label: {
                        Label("Reset Cloud Data Sharing Consent", systemImage: "arrow.counterclockwise")
                            .font(.callout)
                    }
                }

                Link(destination: URL(string: "https://eir.health/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showingAddPerson) {
            AddPersonSheet()
        }
        .sheet(isPresented: $showHealthKitImport) {
            HealthKitImportView()
                .environmentObject(profileStore)
        }
        .alert("Rename Person", isPresented: Binding(
            get: { renamingProfileID != nil },
            set: { if !$0 { renamingProfileID = nil } }
        )) {
            TextField("Display name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingProfileID = nil
            }
            Button("Rename") {
                if let id = renamingProfileID {
                    profileStore.renameProfile(id, to: renameText)
                }
                renamingProfileID = nil
            }
        } message: {
            Text("Enter a new display name for this person.")
        }
    }

    private var hasAnyCloudConsent: Bool {
        LLMProviderType.allCases.filter { !$0.isLocal }.contains { type in
            ChatViewModel.hasCloudConsent(for: type)
        }
    }

    private func resetCloudConsent() {
        for type in LLMProviderType.allCases where !type.isLocal {
            UserDefaults.standard.removeObject(forKey: "cloudConsent_\(type.rawValue)")
        }
    }
}

// MARK: - Provider Section

private struct ProviderSection: View {
    let config: LLMProviderConfig
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var localModelManager: LocalModelManager
    @ObservedObject private var codexDiagnostics = CodexNetworkDiagnosticsStore.shared
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var showKey = false
    @State private var isProvisioningManagedAccess = false
    @State private var managedAccessSnapshot: ManagedCloudAccessSnapshot?
    @State private var managedAccessError: String?
    @State private var isExpanded = false
    @State private var didCopyOpenAICode = false
    @State private var lastAutoCopiedCode: String?
    @State private var inlineSignInURL: URL?
    @State private var showOpenAIDiagnostics = false

    var isActive: Bool { settingsVM.activeProviderType == config.type }
    var hasKey: Bool { !apiKey.isEmpty }
    var usesManagedTrial: Bool { config.type.usesManagedTrialAccess }
    var hasOpenAIAccount: Bool {
        config.type == .openai && settingsVM.openAIAccountSession != nil
    }
    var latestCodexDiagnostic: CodexNetworkDiagnostic? {
        codexDiagnostics.entries.first(where: { $0.category == "ChatGPT account" })
    }
    var hasOpenAIAvailableModels: Bool {
        config.type == .openai && !settingsVM.openAIAvailableModels.isEmpty
    }
    var isConfigured: Bool {
        if usesManagedTrial {
            return settingsVM.hasManagedAccessToken(for: config.type)
        }
        if config.type == .openai {
            return hasOpenAIAccount || hasKey
        }
        return hasKey
    }
    var statusText: String {
        if usesManagedTrial {
            return isConfigured ? "Trial ready" : "Free credits available"
        }
        if config.type == .openai && hasOpenAIAccount {
            return "ChatGPT connected"
        }
        return hasKey ? "Configured" : "No API key"
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                if config.type.isLocal {
                    LocalModelSection()
                } else if usesManagedTrial {
                    managedCloudSection
                } else {
                    if config.type == .openai {
                        openAIAccountSection
                    }

                    HStack {
                        if showKey {
                            TextField("API Key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                        }

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .onChange(of: apiKey) { _, newValue in
                        settingsVM.setApiKey(newValue, for: config.type)
                    }

                    if config.type == .openai && hasOpenAIAvailableModels {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Available models")
                                    .foregroundColor(AppColors.textSecondary)
                                Spacer()
                                Button {
                                    Task { await settingsVM.refreshOpenAIAvailableModels(force: true) }
                                } label: {
                                    if settingsVM.isRefreshingOpenAIModels {
                                        ProgressView()
                                    } else {
                                        Text("Refresh")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(settingsVM.isRefreshingOpenAIModels)
                            }

                            Picker("Model", selection: $model) {
                                ForEach(settingsVM.openAIAvailableModels, id: \.self) { availableModel in
                                    Text(availableModel).tag(availableModel)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: model) { _, newValue in
                                var updated = config
                                updated.model = newValue
                                settingsVM.updateProvider(updated)
                            }
                        }
                    } else {
                        HStack {
                            Text("Model")
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            TextField("Model name", text: $model)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: model) { _, newValue in
                                    var updated = config
                                    updated.model = newValue
                                    settingsVM.updateProvider(updated)
                                }
                        }
                    }

                    if config.type == .custom {
                        HStack {
                            Text("Base URL")
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                            TextField("https://api.example.com/v1", text: $baseURL)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: baseURL) { _, newValue in
                                    var updated = config
                                    updated.baseURL = newValue
                                    settingsVM.updateProvider(updated)
                                }
                        }
                    }

                    if !isActive && isConfigured {
                        Button("Use \(config.type.displayName)") {
                            settingsVM.setActiveProvider(config.type)
                        }
                        .foregroundColor(AppColors.primary)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(config.type.displayName)
                                .font(.headline)
                            if isActive {
                                Text("Active")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.primary)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        if config.type.isLocal {
                            Text("Runs entirely on device")
                                .font(.caption2)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        } else if usesManagedTrial {
                            Text("Eir-hosted cloud route")
                                .font(.caption2)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        } else {
                            Text(config.model)
                                .font(.caption2)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if config.type.isLocal {
                        Text(localModelManager.preferredModel?.displayName ?? "On device")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isConfigured ? AppColors.green : AppColors.border)
                                .frame(width: 8, height: 8)
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(isConfigured ? AppColors.green : AppColors.textSecondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            apiKey = settingsVM.apiKey(for: config.type)
            baseURL = config.baseURL
            model = config.model
            managedAccessSnapshot = settingsVM.managedAccessSnapshot(for: config.type)
            isExpanded = isActive || config.type.isLocal
            if config.type == .openai, settingsVM.openAIAccountSession != nil {
                Task { await settingsVM.refreshOpenAIAvailableModels() }
            }
        }
        .onChange(of: settingsVM.activeProviderType) { _, newValue in
            if newValue == config.type {
                isExpanded = true
            }
        }
        .onReceive(settingsVM.$providers) { providers in
            if let updatedConfig = providers.first(where: { $0.type == config.type }) {
                baseURL = updatedConfig.baseURL
                model = updatedConfig.model
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard config.type == .openai,
                  newValue == .active,
                  settingsVM.pendingOpenAIDeviceCode != nil else { return }

            Task { await settingsVM.refreshOpenAIAccountSignInStatus() }
        }
    }

    private var managedCloudSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Free Trial for Eir")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.text)
                Text("Use daily credits to try Eir's hosted AI.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.aiSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let managedAccessSnapshot {
                quotaView(snapshot: managedAccessSnapshot)
            }

            if usesManagedTrial {
                billingSection
            }

            if let managedAccessError, !managedAccessError.isEmpty {
                Text(managedAccessError)
                    .font(.caption)
                    .foregroundColor(AppColors.danger)
            }

            Button {
                Task { await provisionManagedAccess() }
            } label: {
                HStack {
                    if isProvisioningManagedAccess {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(managedAccessSnapshot == nil ? "Start Free Trial" : "Refresh Trial Access")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryStrong)
            .disabled(isProvisioningManagedAccess)

            if !isActive {
                Button("Use \(config.type.displayName)") {
                    settingsVM.setActiveProvider(config.type)
                }
                .foregroundColor(AppColors.primary)
            }
        }
    }

    private var openAIAccountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("ChatGPT account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.text)
                    Text("Experimental")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14))
                        .clipShape(Capsule())
                }

                Text("Use the same OpenAI account flow as Codex to try your ChatGPT subscription here.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.backgroundMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let session = settingsVM.openAIAccountSession {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.email ?? session.accountID ?? "Connected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.text)

                    if let planType = session.planType, !planType.isEmpty {
                        Text(planType.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Text("OpenAI account auth will be used before the manual API key.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.aiSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let deviceCode = settingsVM.pendingOpenAIDeviceCode {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter this code")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)

                    HStack(spacing: 12) {
                        Text(deviceCode.userCode)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundColor(AppColors.text)
                            .textSelection(.enabled)

                        Spacer()

                        Button(didCopyOpenAICode ? "Copied" : "Copy") {
                            UIPasteboard.general.string = deviceCode.userCode
                            withAnimation(.easeInOut(duration: 0.2)) {
                                didCopyOpenAICode = true
                            }

                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                await MainActor.run {
                                    didCopyOpenAICode = false
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Copy the code, open ChatGPT sign-in, paste it there, then come back here. Eir will keep checking, and you can also refresh the status manually.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)

                    HStack {
                        Button("Open in Browser") {
                            if let url = URL(string: deviceCode.verificationURL) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.primaryStrong)

                        Button("Check Status") {
                            Task { await settingsVM.refreshOpenAIAccountSignInStatus() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(settingsVM.isOpenAIAccountBusy)

                        Button("Cancel") {
                            settingsVM.cancelOpenAIAccountSignIn()
                        }
                        .buttonStyle(.bordered)
                    }

                    if settingsVM.isOpenAIAccountBusy {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Finishing sign-in…")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    } else {
                        Text("Waiting for confirmation. Return here after the browser step if you want to check again.")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    if let inlineSignInURL {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("ChatGPT sign-in")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppColors.textSecondary)
                                Spacer()
                                Button("Hide") {
                                    self.inlineSignInURL = nil
                                }
                                .buttonStyle(.bordered)
                            }

                            InlineWebView(
                                url: inlineSignInURL,
                                prefillCode: deviceCode.userCode
                            )
                                .frame(height: 420)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.8), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundMuted)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onAppear {
                    autoCopyOpenAICodeIfNeeded(deviceCode.userCode)
                    inlineSignInURL = URL(string: deviceCode.verificationURL)
                }
                .onChange(of: deviceCode.userCode) { _, newValue in
                    autoCopyOpenAICodeIfNeeded(newValue)
                }
                .onChange(of: deviceCode.verificationURL) { _, newValue in
                    inlineSignInURL = URL(string: newValue)
                }
            } else {
                Button {
                    Task { await settingsVM.startOpenAIAccountSignIn() }
                } label: {
                    HStack {
                        if settingsVM.isOpenAIAccountBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(hasOpenAIAccount ? "Reconnect ChatGPT Account" : "Sign In with ChatGPT")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primaryStrong)
                .disabled(settingsVM.isOpenAIAccountBusy)
            }

            if let error = settingsVM.openAIAccountError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.danger)
            }

            openAIDiagnosticsSection

            if hasOpenAIAccount {
                Button("Disconnect ChatGPT Account", role: .destructive) {
                    settingsVM.disconnectOpenAIAccount()
                }
            }

            Divider()
        }
    }

    private func autoCopyOpenAICodeIfNeeded(_ code: String) {
        guard lastAutoCopiedCode != code else { return }
        UIPasteboard.general.string = code
        lastAutoCopiedCode = code
        didCopyOpenAICode = true

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                didCopyOpenAICode = false
            }
        }
    }

    private var openAIDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showOpenAIDiagnostics) {
                if let diagnostic = latestCodexDiagnostic {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Updated", value: diagnostic.updatedAt.formatted(date: .omitted, time: .standard))
                        LabeledContent("Status", value: diagnostic.statusCode.map(String.init) ?? "No HTTP response")
                        LabeledContent("Content-Type", value: diagnostic.contentType.isEmpty ? "None" : diagnostic.contentType)
                        LabeledContent("Bytes", value: "\(diagnostic.bytesRead)")
                        LabeledContent("Lines", value: "\(diagnostic.lineCount)")
                        LabeledContent("Outcome", value: diagnostic.outcome)

                        if let error = diagnostic.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(AppColors.danger)
                        }

                        if !diagnostic.parserEvents.isEmpty {
                            Text("Parser events: \(diagnostic.parserEvents.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }

                        if !diagnostic.responseHeaders.isEmpty {
                            let headersText = diagnostic.responseHeaders
                                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                                .map { "\($0.key): \($0.value)" }
                                .joined(separator: "\n")
                            Text(headersText)
                                .font(.caption2.monospaced())
                                .foregroundColor(AppColors.textSecondary)
                                .textSelection(.enabled)
                        }

                        if !diagnostic.rawPreview.isEmpty {
                            ScrollView {
                                Text(diagnostic.rawPreview)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(AppColors.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 90, maxHeight: 180)
                            .padding(10)
                            .background(AppColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        HStack {
                            Button("Copy Diagnostics") {
                                UIPasteboard.general.string = diagnostic.shareText
                            }
                            .buttonStyle(.bordered)

                            Button("Clear") {
                                codexDiagnostics.clear()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Text("No recent ChatGPT account request has been logged yet.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.top, 8)
                }
            } label: {
                HStack {
                    Text("Connection diagnostics")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    if let diagnostic = latestCodexDiagnostic {
                        Text(diagnostic.outcome)
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func quotaView(snapshot: ManagedCloudAccessSnapshot) -> some View {
        let balance = settingsVM.eirTrialBalance(for: snapshot, type: config.type)
        let usageProgress = balance.totalTokens > 0 ? Double(balance.usedTokens) / Double(balance.totalTokens) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trial usage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.text)
                Spacer()
                Text(snapshot.mode.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.aiStrong)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.auraSubtle)
                    .clipShape(Capsule())
            }

            ProgressView(value: usageProgress)
                .tint(AppColors.aiStrong)

            HStack {
                quotaMetric(title: "Used", value: "\(balance.usedTokens)")
                Spacer()
                quotaMetric(title: "Total", value: "\(balance.totalTokens)")
                Spacer()
                quotaMetric(title: "Remaining", value: "\(balance.remainingTokens)")
            }

            Text("1 token = \(balance.requestsPerToken) hosted requests. You receive \(balance.dailyTokenGrant) new tokens each day.")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
            Text("\(max(snapshot.quota.used.requests, 0)) hosted requests used")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
            Text("Provisioned on \(snapshot.provisionedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Upgrade")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.text)

            if purchaseManager.hasBillingProducts {
                if let subscription = purchaseManager.subscriptionProduct {
                    billingProductButton(
                        title: subscription.displayName,
                        subtitle: "Monthly subscription",
                        price: subscription.displayPrice
                    ) {
                        Task { await purchase(subscription) }
                    }
                }

                ForEach(purchaseManager.topUpProducts, id: \.id) { product in
                    billingProductButton(
                        title: product.displayName,
                        subtitle: "Extra hosted requests",
                        price: product.displayPrice
                    ) {
                        Task { await purchase(product) }
                    }
                }

                Button("Restore Purchases") {
                    Task { await restorePurchases() }
                }
                .foregroundColor(AppColors.primary)
                .disabled(purchaseManager.isPurchasing)
            } else {
                Text("Add App Store product IDs to enable subscriptions and top-ups.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            if let purchaseError = purchaseManager.lastError, !purchaseError.isEmpty {
                Text(purchaseError)
                    .font(.caption)
                    .foregroundColor(AppColors.danger)
            }
        }
    }

    private func billingProductButton(
        title: String,
        subtitle: String,
        price: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                Text(price)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryStrong)
            }
            .padding(12)
            .background(AppColors.backgroundMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(purchaseManager.isPurchasing)
    }

    private func quotaMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundColor(AppColors.text)
            Text(title)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private func provisionManagedAccess() async {
        isProvisioningManagedAccess = true
        managedAccessError = nil
        defer { isProvisioningManagedAccess = false }

        do {
            managedAccessSnapshot = try await settingsVM.provisionManagedAccess(for: config)
        } catch {
            managedAccessError = error.localizedDescription
        }
    }

    private func purchase(_ product: Product) async {
        do {
            if let snapshot = try await purchaseManager.purchase(product, settingsVM: settingsVM) {
                managedAccessSnapshot = snapshot
                managedAccessError = nil
            }
        } catch {
            managedAccessError = error.localizedDescription
        }
    }

    private func restorePurchases() async {
        do {
            if let snapshot = try await purchaseManager.restorePurchases(settingsVM: settingsVM) {
                managedAccessSnapshot = snapshot
                managedAccessError = nil
            }
        } catch {
            managedAccessError = error.localizedDescription
        }
    }
}

private struct InlineWebView: UIViewRepresentable {
    let url: URL
    let prefillCode: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(prefillCode: prefillCode)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.prefillCode = prefillCode
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var prefillCode: String?

        init(prefillCode: String?) {
            self.prefillCode = prefillCode
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            scheduleAutofill(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let targetURL = navigationAction.request.url {
                webView.load(URLRequest(url: targetURL))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil, let targetURL = navigationAction.request.url {
                webView.load(URLRequest(url: targetURL))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func scheduleAutofill(in webView: WKWebView) {
            attemptAutofill(in: webView)
            let delays: [TimeInterval] = [0.35, 0.9, 1.8, 3.0]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.attemptAutofill(in: webView)
                }
            }
        }

        private func attemptAutofill(in webView: WKWebView) {
            guard let code = prefillCode?.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !code.isEmpty else {
                return
            }

            let script = """
            (function() {
              const code = '\(code)';
              const candidates = Array.from(document.querySelectorAll('input, textarea, [contenteditable="true"]')).filter((element) => {
                if (element.disabled || element.readOnly) return false;
                const style = window.getComputedStyle(element);
                return style.display !== 'none' && style.visibility !== 'hidden';
              });
              const target = candidates.find((element) => {
                const description = [
                  element.name || '',
                  element.id || '',
                  element.placeholder || '',
                  element.getAttribute('aria-label') || '',
                  element.getAttribute('autocomplete') || ''
                ].join(' ').toLowerCase();
                return /code|otp|verification|device|user/.test(description);
              }) || candidates[0];

              if (!target) return 'no-input';

              target.focus();
              if (target.isContentEditable) {
                target.textContent = code;
              } else {
                target.value = code;
              }
              target.dispatchEvent(new InputEvent('input', { bubbles: true, data: code, inputType: 'insertText' }));
              target.dispatchEvent(new Event('change', { bubbles: true }));
              const submitButton = Array.from(document.querySelectorAll('button, input[type="submit"]')).find((element) => {
                const label = (element.innerText || element.value || element.getAttribute('aria-label') || '').toLowerCase();
                return /continue|next|verify|submit/.test(label);
              });
              if (submitButton) {
                submitButton.click();
              }
              return 'filled';
            })();
            """

            webView.evaluateJavaScript(script)
        }
    }
}

// MARK: - Local Model Section

private struct LocalModelSection: View {
    @EnvironmentObject var localModelManager: LocalModelManager
    @EnvironmentObject var settingsVM: SettingsViewModel
    @State private var showAddModel = false
    @State private var newModelId = ""

    var body: some View {
        Toggle(isOn: $settingsVM.voiceTranscriptPolishEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Polish voice transcripts on-device")
                    .foregroundColor(AppColors.text)
                Text("Use the local model to clean up short voice notes before the app uses them.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .tint(AppColors.primary)

        // Error banner
        if case .error(let msg) = localModelManager.status {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }

        // Model list
        ForEach(localModelManager.models) { model in
            LocalModelRow(model: model)
        }
        .onDelete { offsets in
            let ids = offsets.map { localModelManager.models[$0].id }
            for id in ids {
                localModelManager.removeModel(id)
            }
        }

        // Add model button
        Button {
            newModelId = ""
            showAddModel = true
        } label: {
            Label("Add Model...", systemImage: "plus.circle")
        }
        .foregroundColor(AppColors.primary)
        .alert("Add Model", isPresented: $showAddModel) {
            TextField("mlx-community/model-name", text: $newModelId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let id = newModelId.trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty else { return }
                let name = LocalModel.defaultDisplayName(for: id)
                localModelManager.addModel(id: id, displayName: name)
            }
        } message: {
            Text("Enter a HuggingFace model ID")
        }

        // Unload from memory
        if localModelManager.activeModelId != nil {
            Button(role: .destructive) {
                localModelManager.unloadModel()
            } label: {
                Label("Unload from Memory", systemImage: "xmark.circle")
            }
        }

        // Use on-device button
        if localModelManager.isReady && settingsVM.activeProviderType != .local {
            Button("Use On-Device") {
                settingsVM.setActiveProvider(.local)
            }
            .foregroundColor(AppColors.primary)
        }
    }
}

// MARK: - Local Model Row

private struct LocalModelRow: View {
    let model: LocalModel
    @EnvironmentObject var localModelManager: LocalModelManager

    var isActive: Bool { localModelManager.activeModelId == model.id }
    var isPreferred: Bool { localModelManager.preferredModelId == model.id }
    var isDownloading: Bool { localModelManager.downloadingModelId == model.id }
    var isLoading: Bool {
        isDownloading && localModelManager.status == .loading
    }
    var hasMeaningfulProgress: Bool {
        localModelManager.downloadProgress > 0.001
    }

    var body: some View {
        Button {
            Task { await localModelManager.selectModel(model.id) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.displayName)
                                .font(.subheadline)
                                .foregroundColor(AppColors.text)
                            if model.isExperimental {
                                Text("Experimental")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AppColors.orange.opacity(0.14))
                                    .foregroundColor(AppColors.orange)
                                    .clipShape(Capsule())
                            }
                            if isPreferred {
                                Text("Preferred")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AppColors.primary.opacity(0.14))
                                    .foregroundColor(AppColors.primary)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(model.id)
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppColors.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.caption)
                                .foregroundColor(AppColors.green)
                        }
                    } else if isLoading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    } else if isDownloading {
                        if hasMeaningfulProgress {
                            Text("\(Int(localModelManager.downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(AppColors.yellow)
                        } else {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Preparing...")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    } else if isPreferred {
                        Text("Ready when needed")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                // Download progress bar
                if isDownloading && localModelManager.status == .downloading {
                    if hasMeaningfulProgress {
                        ProgressView(value: localModelManager.downloadProgress)
                            .tint(AppColors.primary)
                    } else {
                        ProgressView()
                            .tint(AppColors.primary)
                    }
                }
            }
        }
        .disabled(isDownloading || (localModelManager.status == .downloading && !isDownloading))
    }
}

// MARK: - Prompt Style Section

private struct PromptStyleSection: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @State private var showCreatePrompt = false
    @State private var editingPrompt: PromptVersion?
    @State private var templatingPrompt: PromptVersion?
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let active = settingsVM.activePromptVersion {
                    Button {
                        if active.isBuiltIn {
                            templatingPrompt = active
                        } else {
                            editingPrompt = active
                        }
                    } label: {
                        Label(
                            active.isBuiltIn ? "Customize Current Style..." : "Edit Current Style...",
                            systemImage: active.isBuiltIn ? "slider.horizontal.3" : "pencil"
                        )
                    }
                    .foregroundColor(AppColors.primary)

                    Text("Short, direct prompts work best for on-device models.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                ForEach(settingsVM.allPromptVersions) { version in
                    Button {
                        settingsVM.activePromptVersionId = version.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(version.name)
                                        .font(.body)
                                        .foregroundColor(AppColors.text)
                                    if !version.isBuiltIn {
                                        Text("Custom")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(AppColors.primary.opacity(0.15))
                                            .foregroundColor(AppColors.primary)
                                            .cornerRadius(3)
                                    }
                                }
                                Text(version.description)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Spacer()
                            if settingsVM.activePromptVersionId == version.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppColors.primary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if version.isBuiltIn {
                            Button {
                                templatingPrompt = version
                            } label: {
                                Label("Customize", systemImage: "doc.on.doc")
                            }
                            .tint(AppColors.primary)
                        } else {
                            Button(role: .destructive) {
                                settingsVM.deleteCustomPrompt(version.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingPrompt = version
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(AppColors.primary)
                        }
                    }
                }

                Button {
                    showCreatePrompt = true
                } label: {
                    Label("Create Custom Style...", systemImage: "plus.circle")
                }
                .foregroundColor(AppColors.primary)
            } label: {
                HStack {
                    Text("Prompt Style")
                    Spacer()
                    if let active = settingsVM.activePromptVersion {
                        Text(active.name)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePrompt) {
            PromptEditorSheet(settingsVM: settingsVM)
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditorSheet(settingsVM: settingsVM, editing: prompt)
        }
        .sheet(item: $templatingPrompt) { prompt in
            PromptEditorSheet(settingsVM: settingsVM, template: prompt)
        }
    }
}

// MARK: - Prompt Editor Sheet

private struct PromptEditorSheet: View {
    @ObservedObject var settingsVM: SettingsViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var description: String
    @State private var systemPrompt: String

    private let editingId: String?
    private let isTemplate: Bool

    init(settingsVM: SettingsViewModel, editing: PromptVersion? = nil, template: PromptVersion? = nil) {
        self.settingsVM = settingsVM
        self.editingId = editing?.id
        self.isTemplate = template != nil && editing == nil
        _name = State(initialValue: editing?.name ?? template.map { "\($0.name) Copy" } ?? "")
        _description = State(initialValue: editing?.description ?? template?.description ?? "")
        _systemPrompt = State(initialValue: editing?.systemPrompt ?? template?.systemPrompt ?? """
        You are Eir, a practical health guide.
        Goal: help the user understand their health and records in plain language.
        Reply in the user's language.

        Rules:
        - Use the records only for record-specific facts.
        - If the records do not answer the question, say that clearly.
        - General health guidance is allowed, but label it as general guidance.
        - Explain medical terms simply.
        - Start with the answer.
        - Cite specific entries with <JOURNAL_ENTRY id="ENTRY_ID"/>.
        - Never invent medications, results, diagnoses, or dosages.
        - Never give a definitive diagnosis.
        - Only suggest follow-up questions when there is a clearly useful next question.
        """)
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Simple & Friendly", text: $name)
                }

                Section("Description") {
                    TextField("Short description", text: $description)
                }

                Section("System Prompt") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 200)
                        .font(.system(.caption, design: .monospaced))
                }

                Section {
                    Text("Keep it short and direct for on-device models. Patient records and user context are appended automatically.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .navigationTitle(editingId != nil ? "Edit Prompt" : (isTemplate ? "Customize Prompt" : "New Prompt Style"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
                        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespaces)

                        if let id = editingId {
                            let updated = PromptVersion(
                                id: id,
                                name: trimmedName,
                                description: trimmedDesc,
                                systemPrompt: trimmedPrompt
                            )
                            settingsVM.updateCustomPrompt(updated)
                        } else {
                            settingsVM.addCustomPrompt(
                                name: trimmedName,
                                description: trimmedDesc,
                                systemPrompt: trimmedPrompt
                            )
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
