import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        TabView {
            LLMSettingsTab()
                .environmentObject(settingsVM)
                .tabItem {
                    Label("LLM Providers", systemImage: "cpu")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct LLMSettingsTab: View {
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Active provider picker
                HStack {
                    Text("Active Provider")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $settingsVM.activeProviderType) {
                        ForEach(LLMProviderType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .frame(width: 150)
                }
                .padding(.horizontal)

                Divider()

                ForEach(settingsVM.providers) { config in
                    ProviderRow(config: config)
                        .environmentObject(settingsVM)
                }
            }
            .padding()
        }
    }
}

struct ProviderRow: View {
    let config: LLMProviderConfig
    @EnvironmentObject var settingsVM: SettingsViewModel
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""

    var isActive: Bool { settingsVM.activeProviderType == config.type }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(config.type.rawValue)
                        .font(.headline)
                    if isActive {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    Spacer()
                }

                LabeledContent("API Key") {
                    SecureField("Enter API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .onChange(of: apiKey) { _, newValue in
                            settingsVM.setApiKey(newValue, for: config.type)
                        }
                }

                if config.type == .custom {
                    LabeledContent("Base URL") {
                        TextField("https://...", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                            .onChange(of: baseURL) { _, newValue in
                                var updated = config
                                updated.baseURL = newValue
                                settingsVM.updateProvider(updated)
                            }
                    }
                }

                LabeledContent("Model") {
                    TextField("Model name", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .onChange(of: model) { _, newValue in
                            var updated = config
                            updated.model = newValue
                            settingsVM.updateProvider(updated)
                        }
                }
            }
            .padding(4)
        }
        .padding(.horizontal)
        .onAppear {
            apiKey = settingsVM.apiKey(for: config.type)
            baseURL = config.baseURL
            model = config.model
        }
    }
}
