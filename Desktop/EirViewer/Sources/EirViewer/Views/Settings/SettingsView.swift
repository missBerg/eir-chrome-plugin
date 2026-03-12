import SwiftUI

// macOS Settings window (Cmd+,)
struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var agentMemoryStore: AgentMemoryStore
    @EnvironmentObject var embeddingStore: EmbeddingStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var localModelManager: LocalModelManager

    var body: some View {
        InlineSettingsView()
            .environmentObject(settingsVM)
            .environmentObject(agentMemoryStore)
            .environmentObject(embeddingStore)
            .environmentObject(modelManager)
            .environmentObject(localModelManager)
            .frame(width: 600, height: 750)
    }
}

// Full in-app settings view (used in sidebar navigation and Settings window)
struct InlineSettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var agentMemoryStore: AgentMemoryStore
    @EnvironmentObject var embeddingStore: EmbeddingStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var localModelManager: LocalModelManager
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.text)
                    Text("Configure AI providers to chat about your medical records")
                        .foregroundColor(AppColors.textSecondary)
                }

                // Active provider
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Provider")
                                .font(.headline)
                                .foregroundColor(AppColors.text)
                            Text("Choose which AI provider to use for chat")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer()
                        Picker("", selection: $settingsVM.activeProviderType) {
                            ForEach(LLMProviderType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .frame(width: 160)
                    }
                    .padding(4)
                }

                // Local model settings (shown when On-Device is active)
                if settingsVM.activeProviderType.isLocal {
                    LocalModelSettingsView()
                    PromptStyleSettingsView()
                }

                // Provider cards (hide local from card list)
                ForEach(settingsVM.providers.filter { !$0.type.isLocal }) { config in
                    ProviderCard(config: config)
                        .environmentObject(settingsVM)
                }

                // Smart Search (Embeddings)
                EmbeddingSettingsView()

                // Agent Configuration
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Agent Configuration")
                            .font(.headline)
                            .foregroundColor(AppColors.text)
                        Text("Customize the AI agent's identity, memory, and capabilities")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)

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
                        // Reset Agent button
                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset Agent")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppColors.text)
                                Text("Resets all files to defaults — the agent will re-introduce itself on next chat")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Spacer()
                            Button("Reset") {
                                showResetConfirmation = true
                            }
                            .foregroundColor(AppColors.red)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: agentMemoryStore.memory.soul) { _, _ in agentMemoryStore.save() }
                .onChange(of: agentMemoryStore.memory.user) { _, _ in agentMemoryStore.save() }
                .onChange(of: agentMemoryStore.memory.memory) { _, _ in agentMemoryStore.save() }
                .onChange(of: agentMemoryStore.memory.agents) { _, _ in agentMemoryStore.save() }
                .alert("Reset Agent?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        agentMemoryStore.resetToDefaults()
                    }
                } message: {
                    Text("This will reset the agent's identity, user profile, memory, and skills to defaults. The agent will re-introduce itself on the next chat.")
                }

                // Info
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(AppColors.primary)
                    Text("API keys are stored securely in macOS Keychain")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .background(AppColors.background)
    }
}

struct ProviderCard: View {
    let config: LLMProviderConfig
    @EnvironmentObject var settingsVM: SettingsViewModel
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var showKey = false
    @State private var isProvisioningManagedAccess = false
    @State private var managedAccessSnapshot: ManagedCloudAccessSnapshot?
    @State private var managedAccessError: String = ""

    var isActive: Bool { settingsVM.activeProviderType == config.type }
    var hasKey: Bool { !apiKey.isEmpty }
    var usesManagedTrial: Bool { config.type.usesManagedTrialAccess }
    var isConfigured: Bool {
        usesManagedTrial ? settingsVM.hasManagedAccessToken(for: config.type) : hasKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(config.type.rawValue)
                            .font(.headline)
                            .foregroundColor(AppColors.text)
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
                    Text(usesManagedTrial ? "Eir-hosted cloud route in Stockholm" : config.type.defaultBaseURL)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConfigured ? AppColors.green : AppColors.border)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(isConfigured ? AppColors.green : AppColors.textSecondary)
                }

                if !isActive {
                    Button("Use") {
                        settingsVM.setActiveProvider(config.type)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primary)
                    .controlSize(.small)
                    .disabled(!isConfigured)
                }
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if usesManagedTrial {
                    managedTrialContent
                } else {
                    apiKeyContent
                }

                // Model field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.text)

                    TextField("Model name", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model) { _, newValue in
                            var updated = config
                            updated.model = newValue
                            settingsVM.updateProvider(updated)
                        }
                }

                // Custom base URL
                if config.type == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base URL")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.text)

                        TextField("https://api.example.com/v1", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: baseURL) { _, newValue in
                                var updated = config
                                updated.baseURL = newValue
                                settingsVM.updateProvider(updated)
                            }
                    }
                }
            }
            .padding(16)
        }
        .background(AppColors.card)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? AppColors.primary.opacity(0.3) : AppColors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        .onAppear {
            apiKey = settingsVM.apiKey(for: config.type)
            baseURL = config.baseURL
            model = config.model
            managedAccessSnapshot = settingsVM.managedAccessSnapshot(for: config.type)
        }
    }

    private var statusText: String {
        if usesManagedTrial {
            return isConfigured ? "Trial ready" : "Free credits available"
        }
        return hasKey ? "Configured" : "No API key"
    }

    private var apiKeyContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API Key")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.text)

            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField("Enter your API key", text: $apiKey)
                    } else {
                        SecureField("Enter your API key", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onChange(of: apiKey) { _, newValue in
                    settingsVM.setApiKey(newValue, for: config.type)
                }

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(showKey ? "Hide key" : "Show key")
            }

            if config.type == .anthropic, !hasKey {
                Text("Get a key at console.anthropic.com")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            } else if config.type == .minimax, !hasKey {
                Text("Get a key at platform.minimax.io — uses Anthropic format")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            } else if config.type == .groq, !hasKey {
                Text("Free API key at console.groq.com")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private var managedTrialContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hosted by Eir")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.text)
                Text("Data is sent through Eir servers in Stockholm with zero Eir retention. Berget AI performs the inference using \(config.model).")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let snapshot = managedAccessSnapshot {
                quotaView(snapshot.quota)
            }

            if !managedAccessError.isEmpty {
                Text(managedAccessError)
                    .font(.caption)
                    .foregroundColor(AppColors.red)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await provisionManagedAccess() }
                } label: {
                    if isProvisioningManagedAccess {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(managedAccessSnapshot == nil ? "Provision Free Credits" : "Refresh Trial Access")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primary)
                .disabled(isProvisioningManagedAccess)

                if managedAccessSnapshot != nil {
                    Button("Clear Trial") {
                        settingsVM.clearManagedAccess(for: config.type)
                        managedAccessSnapshot = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func quotaView(_ quota: ManagedCloudQuota) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let total = max(1, quota.limits.requests)
            let progress = min(max(Double(quota.used.requests) / Double(total), 0), 1)

            HStack {
                Text("Trial usage")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.text)
                Spacer()
                Text("\(quota.used.requests) used · \(quota.remaining.requests) left")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            ProgressView(value: progress)
                .tint(AppColors.aiStrong)

            Text("\(quota.limits.requests) total requests included")
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(12)
        .background(AppColors.backgroundMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func provisionManagedAccess() async {
        isProvisioningManagedAccess = true
        managedAccessError = ""
        do {
            var updated = config
            updated.baseURL = baseURL
            settingsVM.updateProvider(updated)
            managedAccessSnapshot = try await settingsVM.provisionManagedAccess(for: updated)
            if !isActive {
                settingsVM.setActiveProvider(config.type)
            }
        } catch {
            managedAccessError = error.localizedDescription
        }
        isProvisioningManagedAccess = false
    }
}
