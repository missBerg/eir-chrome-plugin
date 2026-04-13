import SwiftUI

struct EntryDetailView: View {
    let entry: EirEntry
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var chatThreadStore: ChatThreadStore
    @EnvironmentObject var agentMemoryStore: AgentMemoryStore
    @EnvironmentObject var localModelManager: LocalModelManager
    @EnvironmentObject var translationStore: JournalTranslationStore
    @State private var requestedTranslationLanguage: SupportedChatLanguage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    CategoryBadge(category: entry.category ?? "Övrigt")

                    if let status = entry.status {
                        Text(status)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(status == "Osignerad" ? AppColors.orange.opacity(0.12) : AppColors.divider)
                            .foregroundColor(status == "Osignerad" ? AppColors.orange : AppColors.textSecondary)
                            .cornerRadius(4)
                    }

                    Spacer()

                    Text(entry.displayDate)
                        .font(.callout)
                        .foregroundColor(AppColors.textSecondary)
                    if let time = entry.time {
                        Text(time)
                            .font(.callout)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                // Summary
                if let summary = translationStore.summary(for: entry) {
                    Text(summary)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.text)
                }

                // Type
                if let type = entry.type, !type.isEmpty {
                    Text(type)
                        .font(.title3)
                        .foregroundColor(AppColors.textSecondary)
                }

                if !translationStore.availableLanguages(for: entry).isEmpty {
                    translationLanguageChips
                }

                Divider()

                // Provider info
                if let provider = entry.provider {
                    GroupBox("Vårdgivare") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let name = provider.name {
                                Label(name, systemImage: "building.2")
                            }
                            if let region = provider.region {
                                Label(region, systemImage: "map")
                            }
                            if let location = provider.location {
                                Label(location, systemImage: "mappin.and.ellipse")
                            }
                        }
                        .font(.callout)
                        .foregroundColor(AppColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Responsible person
                if let person = entry.responsiblePerson {
                    GroupBox("Ansvarig") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let name = person.name {
                                Label(name, systemImage: "person")
                            }
                            if let role = person.role {
                                Label(role, systemImage: "stethoscope")
                            }
                        }
                        .font(.callout)
                        .foregroundColor(AppColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Details
                if let details = translationStore.details(for: entry), !details.isEmpty {
                    GroupBox(entry.detailSectionTitle) {
                        Text(details)
                            .font(.body)
                            .foregroundColor(AppColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                // Notes
                if let notes = translationStore.notes(for: entry), !notes.isEmpty {
                    GroupBox(entry.notesSectionTitle) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(notes, id: \.self) { note in
                                if entry.isClinicalNote {
                                    Text(note)
                                        .font(.body)
                                        .foregroundColor(AppColors.text)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 2)
                                } else {
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(AppColors.primary)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 6)
                                        Text(note)
                                            .font(.body)
                                            .foregroundColor(AppColors.text)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Tags
                if let tags = entry.tags, !tags.isEmpty {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppColors.divider)
                                .foregroundColor(AppColors.textSecondary)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(AppColors.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(translationTargets, id: \.self) { language in
                        Button(language.displayName) {
                            requestedTranslationLanguage = language
                            Task {
                                await translationStore.translateEntry(
                                    entry,
                                    to: language,
                                    settingsVM: settingsVM,
                                    localModelManager: localModelManager
                                )
                            }
                        }
                    }

                    if translationStore.selectedLanguage != nil {
                        Divider()
                        Button("Show Original") {
                            translationStore.setSelectedLanguage(nil)
                        }
                    }
                } label: {
                    Label("Translate", systemImage: "globe")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let profileID = profileStore.selectedProfileID else { return }
                    let includeFollowUpQuestions = profileStore.showChatFollowUpSuggestions(for: profileID)
                    chatVM.explainEntry(
                        entry,
                        document: documentVM.document,
                        settingsVM: settingsVM,
                        chatThreadStore: chatThreadStore,
                        profileID: profileID,
                        agentMemoryStore: agentMemoryStore,
                        localModelManager: localModelManager,
                        includeFollowUpQuestions: includeFollowUpQuestions
                    )
                } label: {
                    Label("Explain with AI", systemImage: "sparkles")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if translationStore.isTranslating, requestedTranslationLanguage != nil {
                VStack(spacing: 6) {
                    ProgressView(value: translationStore.progress) {
                        Text("Translating note...")
                    }
                    if translationStore.totalEntries > 0 {
                        Text("\(translationStore.currentEntryIndex) of \(translationStore.totalEntries)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let profileID = profileStore.selectedProfileID {
                recordSelectionBar(profileID: profileID)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(AppColors.background.opacity(0.96))
            }
        }
    }

    private var translationTargets: [SupportedChatLanguage] {
        SupportedChatLanguage.swedenPriorityLanguages
    }

    private var translationLanguageChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                translationChip(title: "Original", isSelected: translationStore.selectedLanguage == nil) {
                    translationStore.setSelectedLanguage(nil)
                }

                ForEach(translationStore.availableLanguages(for: entry), id: \.self) { language in
                    translationChip(title: language.displayName, isSelected: translationStore.selectedLanguage == language) {
                        translationStore.setSelectedLanguage(language)
                    }
                }
            }
        }
    }

    private func translationChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : AppColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? AppColors.primary : AppColors.backgroundMuted)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func recordSelectionBar(profileID: UUID) -> some View {
        let included = profileStore.isRecordIncludedInChat(entry.id, for: profileID)

        Button {
            profileStore.setRecordIncludedInChat(!included, entryID: entry.id, for: profileID)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: included ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(included ? AppColors.primary : AppColors.orange)
                Text(included ? "Used in Chat" : "Excluded from Chat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.text)
                Spacer()
                Text(included ? "Tap to remove" : "Tap to include")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
