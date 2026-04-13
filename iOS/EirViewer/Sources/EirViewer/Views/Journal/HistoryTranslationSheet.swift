import SwiftUI

struct HistoryTranslationSheet: View {
    let entries: [EirEntry]

    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var localModelManager: LocalModelManager
    @EnvironmentObject private var translationStore: JournalTranslationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Translate the journal timeline with the current model. Original notes always stay available.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Section("Languages") {
                    ForEach(translationTargets, id: \.self) { language in
                        Button {
                            Task {
                                await translationStore.translate(
                                    entries: entries,
                                    to: language,
                                    settingsVM: settingsVM,
                                    localModelManager: localModelManager
                                )
                                if translationStore.errorMessage == nil {
                                    dismiss()
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(language.displayName)
                                    Spacer()
                                    if translationStore.selectedLanguage == language {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppColors.primary)
                                    }
                                }

                                let translatedCount = translationStore.translatedCount(for: entries, language: language)
                                let totalCount = translationStore.translatableCount(for: entries)
                                if totalCount > 0 {
                                    Text("\(translatedCount) of \(totalCount) translated")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                        .disabled(translationStore.isTranslating)
                    }
                }

                if translationStore.isTranslating {
                    Section("Progress") {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: translationStore.progress)
                            if translationStore.totalEntries > 0 {
                                Text("\(translationStore.currentEntryIndex) of \(translationStore.totalEntries)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.text)
                            }
                            if let currentEntryLabel = translationStore.currentEntryLabel {
                                Text(currentEntryLabel)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }

                if let errorMessage = translationStore.errorMessage, !errorMessage.isEmpty {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(AppColors.red)
                    }
                }
            }
            .navigationTitle("Translate History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var translationTargets: [SupportedChatLanguage] {
        SupportedChatLanguage.swedenPriorityLanguages
    }
}
