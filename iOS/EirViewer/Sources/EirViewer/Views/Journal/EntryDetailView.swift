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
    @State private var showDictation = false

    var body: some View {
        let accent = AppColors.categoryColor(for: entry.category ?? "Övrigt")

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            CategoryBadge(category: entry.category ?? "Övrigt")

                            if let summary = entry.content?.summary {
                                Text(summary)
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundColor(AppColors.text)
                            }

                            if let type = entry.type, !type.isEmpty {
                                Text(type)
                                    .font(.title3)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }

                        Spacer(minLength: 16)

                        VStack(alignment: .trailing, spacing: 6) {
                            Text(entry.displayDate)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppColors.textSecondary)

                            if let time = entry.time {
                                Text(time)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            if let status = entry.status {
                                Text(status)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(status == "Osignerad" ? AppColors.warningSoft : AppColors.backgroundMuted)
                                    .foregroundColor(status == "Osignerad" ? AppColors.warning : AppColors.textSecondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(22)
                .background(AppColors.backgroundElevated)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent)
                        .frame(width: 4)
                        .padding(.vertical, 18)
                        .padding(.leading, 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .shadow(color: AppColors.shadow, radius: 12, y: 6)

                if let provider = entry.provider {
                    sectionCard(title: "Vårdgivare", icon: "building.2.fill", tint: AppColors.info) {
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

                if let person = entry.responsiblePerson {
                    sectionCard(title: "Ansvarig", icon: "stethoscope", tint: AppColors.primary) {
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

                if let details = entry.content?.details, !details.isEmpty {
                    sectionCard(title: "Detaljer", icon: "doc.text.fill", tint: AppColors.primaryStrong) {
                        Text(details)
                            .font(.body)
                            .foregroundColor(AppColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                if let notes = entry.content?.notes, !notes.isEmpty {
                    sectionCard(title: "Anteckningar", icon: "sparkles", tint: AppColors.ai) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(notes, id: \.self) { note in
                                noteCard(note: note)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let tags = entry.tags, !tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppColors.backgroundMuted)
                                .foregroundColor(AppColors.textSecondary)
                                .clipShape(Capsule())
                        }
                    }
                }

                explainEntryCard
            }
            .padding(20)
        }
        .background(AppColors.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    explainWholeEntry()
                } label: {
                    Label("Explain with AI", systemImage: "sparkles")
                }
                .tint(AppColors.aiStrong)
            }
        }
        .sheet(isPresented: $showDictation) {
            VoiceNoteComposerSheet(title: "Röstfråga") { draft in
                askAboutEntry(with: draft)
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.text)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func noteCard(note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(AppColors.aiStrong)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            Text(note)
                .font(.body)
                .foregroundColor(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundMuted)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var explainEntryCard: some View {
        HStack(spacing: 12) {
            Button {
                explainWholeEntry()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.aiStrong)

                    Text("Förklara med Artificiell Intelligens")
                        .font(.headline)
                        .foregroundColor(AppColors.text)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppColors.aiStrong)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.aiSoft, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                showDictation = true
            } label: {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.aura)
                    .frame(width: 58, height: 58)
                    .background(AppColors.backgroundElevated)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(AppColors.aiSoft, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .shadow(color: AppColors.shadow, radius: 10, y: 4)
    }

    private func explainWholeEntry() {
        guard let profileID = profileStore.selectedProfileID else { return }
        chatVM.explainEntry(
            entry,
            document: documentVM.document,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager
        )
    }

    private func askAboutEntry(with draft: RecordedVoiceNoteDraft) {
        guard let profileID = profileStore.selectedProfileID else { return }
        chatVM.askAboutEntry(
            entry,
            voiceNote: draft,
            document: documentVM.document,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager
        )
    }
}
