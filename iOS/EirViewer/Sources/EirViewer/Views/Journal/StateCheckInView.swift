import Charts
import SwiftUI

enum StateDimensionGroup: String, CaseIterable, Identifiable {
    case body = "Body"
    case mind = "Mind"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body:
            return "Body"
        case .mind:
            return "Mind"
        }
    }

    var summary: String {
        switch self {
        case .body:
            return "Physical fuel, comfort, and body load."
        case .mind:
            return "Mood, clarity, and drive."
        }
    }
}

private enum StateCheckInInputMode: String, CaseIterable, Identifiable {
    case feeling = "Feelings"
    case number = "0-10"

    var id: String { rawValue }
}

struct StateCheckInView: View {
    @EnvironmentObject private var actionsVM: ActionsViewModel
    @EnvironmentObject private var documentVM: DocumentViewModel
    @EnvironmentObject private var nextBestActionVM: NextBestHealthActionViewModel
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var stateActionVM: StateActionRecommendationViewModel

    @ObservedObject var store: StateCheckInStore

    @State private var draft = StateSnapshotDraft()
    @State private var note = ""
    @State private var justSavedID: UUID?
    @State private var inputMode: StateCheckInInputMode = .feeling
    @State private var isDetailExpanded = false
    @State private var isNoteExpanded = false
    @State private var isGuideExpanded = false
    @State private var lastSavedFingerprint: String?
    @State private var showSaveCelebration = false
    @State private var saveAnimationToken = 0
    @State private var showVoiceComposer = false
    @State private var isTranscribingVoiceNote = false
    @State private var isInferringFromNote = false
    @State private var noteInferenceMessage: String?
    @State private var noteInferenceTask: Task<Void, Never>?
    @State private var skipNextNoteInference = false
    @State private var lastInferredSignature: String?
    @State private var postSaveActionPrompt: PostCheckInActionPrompt?
    @FocusState private var isNoteEditorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                feelingWheelSection

                if !store.records.isEmpty {
                    recentStatesSection
                }

                adaptiveActionSection
                reflectionSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(stateBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("State")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .top) {
            if showSaveCelebration {
                saveCelebrationBanner
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
            }
        }
        .sensoryFeedback(.success, trigger: saveAnimationToken)
        .sheet(isPresented: $showVoiceComposer) {
            VoiceNoteComposerSheet(title: "Voice Check-In") { recordedDraft in
                Task {
                    await handleVoiceNote(recordedDraft)
                }
            }
        }
        .sheet(item: $postSaveActionPrompt) { prompt in
            SuggestedNextActionSheet(
                prompt: prompt,
                isAlreadyCompleted: actionsVM.isCompletedToday(prompt.action),
                onOpenAction: {
                    NotificationCenter.default.post(name: .navigateToAction, object: nil)
                },
                onDoNow: {
                    completeRecommendedAction(prompt.action)
                },
                onFeedback: { helpful in
                    await recordRecommendedActionFeedback(prompt.action, helpful: helpful)
                    postSaveActionPrompt = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            store.load(for: profileStore.selectedProfileID)
            loadDraftFromLatest()
            syncAdaptiveRecommendation()
        }
        .onChange(of: profileStore.selectedProfileID) {
            store.load(for: profileStore.selectedProfileID)
            loadDraftFromLatest()
            syncAdaptiveRecommendation()
        }
        .onChange(of: draft) {
            syncAdaptiveRecommendation()
        }
        .onChange(of: note) {
            syncAdaptiveRecommendation()
            handleNoteChanged()
        }
        .onChange(of: store.records.count) {
            syncAdaptiveRecommendation()
        }
        .onDisappear {
            noteInferenceTask?.cancel()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isNoteEditorFocused = false
                }
            }
        }
    }

    private var feelingWheelSection: some View {
        let entry = currentFeelingEntry

        return VStack(alignment: .leading, spacing: 18) {
            feelingSectionHeader
            inputModeControl
            feelingWheelCard(entry: entry)
            noteComposerSection
            feelingPrimaryActions(entry: entry)

            if !canSaveCurrentState {
                Label("This feeling is already saved. Change the wheel or note to save a new snapshot.", systemImage: "checkmark.seal")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(22)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
    }

    private var feelingSectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How are you feeling?")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
            }

            Spacer()

            Text(activeProfileLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: "C2410C"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.82))
                .clipShape(Capsule())
        }
    }

    private var inputModeControl: some View {
        Picker("Input mode", selection: $inputMode) {
            ForEach(StateCheckInInputMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private func feelingWheelCard(entry: StateFeelingEntry) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            entry.tint.opacity(0.08),
                            Color.white.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(entry.tint.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 16)

            VStack(spacing: 14) {
                feelingCenterLabel(entry: entry)

                Picker("How are you feeling?", selection: overallFeelingBinding) {
                    ForEach(StateFeelingEntry.entries) { feeling in
                        Text(inputMode == .feeling ? feeling.title : "\(feeling.level)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tag(feeling.level)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipped()
            }
            .padding(.vertical, 18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func feelingCenterLabel(entry: StateFeelingEntry) -> some View {
        VStack(spacing: 4) {
            Text(entry.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
            Text("\(entry.level) / 10")
                .font(.caption.weight(.bold))
                .foregroundStyle(entry.tint)
            Text(entry.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var noteComposerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.88))

                if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Type or speak a little more about this moment")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                }

                TextEditor(text: $note)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 112)
                    .background(Color.clear)
                    .focused($isNoteEditorFocused)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button {
                    showVoiceComposer = true
                } label: {
                    Label(
                        isTranscribingVoiceNote ? "Transcribing..." : "Voice note",
                        systemImage: isTranscribingVoiceNote ? "waveform.badge.magnifyingglass" : "waveform.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isTranscribingVoiceNote ? AppColors.textSecondary : AppColors.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTranscribingVoiceNote)

                Spacer(minLength: 0)

                noteInferenceStatusView
            }
        }
    }

    @ViewBuilder
    private var noteInferenceStatusView: some View {
        if isTranscribingVoiceNote || isInferringFromNote {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(isTranscribingVoiceNote ? "Listening..." : "Reading note...")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.92))
            .clipShape(Capsule())
        } else if let noteInferenceMessage, !noteInferenceMessage.isEmpty {
            Label(noteInferenceMessage, systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: "0F766E"))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(hex: "0F766E").opacity(0.1))
                .clipShape(Capsule())
        }
    }

    private func feelingPrimaryActions(entry: StateFeelingEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                resetDraft()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.white.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                saveSnapshot()
            } label: {
                Label(saveButtonTitle, systemImage: saveButtonSystemImage)
                    .font(.headline)
                    .foregroundStyle(canSaveCurrentState ? .white : AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        canSaveCurrentState
                        ? entry.tint
                        : Color.white.opacity(0.92)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                canSaveCurrentState ? Color.clear : AppColors.border,
                                lineWidth: 1
                            )
                    )
                    .symbolEffect(.bounce, value: saveAnimationToken)
            }
            .buttonStyle(.plain)
            .disabled(!canSaveCurrentState)
            .opacity(canSaveCurrentState ? 1 : 0.82)
        }
    }

    private func followUpToggleButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isActive ? .white : AppColors.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isActive ? .white : AppColors.text)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isActive ? Color.white.opacity(0.82) : AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(isActive ? AppColors.primary : Color.white.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isActive ? Color.clear : AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var noteFollowUpButton: some View {
        let title = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add note" : "Edit note"
        let subtitle = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Write what is shaping this feeling"
            : note.trimmingCharacters(in: .whitespacesAndNewlines)

        return followUpToggleButton(
            title: isNoteExpanded ? "Hide note" : title,
            subtitle: subtitle,
            systemImage: "square.and.pencil",
            isActive: isNoteExpanded
        ) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                isNoteExpanded.toggle()
            }
        }
    }

    private var recentStatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent states")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                    Text("A quick read on how your state has moved lately.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text("\(min(store.records.count, 7)) shown")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.82))
                    .clipShape(Capsule())
            }

            RecentStateTrendChart(
                points: recentStateTrendPoints,
                highlightedRecordID: justSavedID
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 0), spacing: 10),
                    GridItem(.flexible(minimum: 0), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(Array(store.records.prefix(6))) { record in
                    Button {
                        loadDraft(from: record)
                    } label: {
                        RecentStateMiniCard(
                            record: record,
                            isHighlighted: justSavedID == record.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tune the details")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                    Text("Optional: refine body and mind after the main feeling is set.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text(overallDescriptor.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(overallDescriptor.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(overallDescriptor.tint.opacity(0.12))
                    .clipShape(Capsule())
            }

            groupSection(.body)
            groupSection(.mind)
            interpretationGuideSection
        }
        .padding(22)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var adaptiveActionSection: some View {
        if let recommendation = stateActionVM.recommendation,
           let action = recommendedAction {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Best next action")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppColors.text)
                        Text("Chosen on-device from your current state and past follow-ups.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    Text(stateActionVM.summary.learningLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: "0F766E"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "0F766E").opacity(0.12))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(action.category.softTint)
                                .frame(width: 56, height: 56)

                            Image(systemName: action.category.systemImage)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(action.category.tint)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(recommendation.headline)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppColors.text)
                            Text(recommendation.summary)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recommendation.whyItFits, id: \.self) { item in
                            Label(item, systemImage: "sparkles")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    HStack(spacing: 8) {
                        recommendationChip("\(Int(recommendation.confidence * 100))% confidence")
                        recommendationChip(stateActionVM.summary.statusLine)
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(action.category.tint.opacity(0.16), lineWidth: 1)
                )

                HStack(spacing: 12) {
                    Button {
                        NotificationCenter.default.post(name: .navigateToAction, object: nil)
                    } label: {
                        Label("Open Action", systemImage: "arrow.right.circle")
                            .font(.headline)
                            .foregroundStyle(AppColors.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        completeRecommendedAction(action)
                    } label: {
                        Label(
                            actionsVM.isCompletedToday(action) ? "Done today" : "I did this",
                            systemImage: actionsVM.isCompletedToday(action) ? "checkmark.seal.fill" : "checkmark.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(actionsVM.isCompletedToday(action) ? AppColors.textSecondary : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(actionsVM.isCompletedToday(action) ? Color.white.opacity(0.88) : action.category.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(actionsVM.isCompletedToday(action) ? AppColors.border : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(actionsVM.isCompletedToday(action))
                    .opacity(actionsVM.isCompletedToday(action) ? 0.82 : 1)
                }
            }
            .padding(22)
            .background(Color.white.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
        }
    }

    private func recommendationChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(hex: "F8FAFC"))
            .clipShape(Capsule())
    }

    private var interpretationGuideSection: some View {
        DisclosureGroup(isExpanded: $isGuideExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Use these as orientation cues, not as diagnosis. The ranges are only there to help you notice the shape of the moment.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(StateDimensionDefinition.catalog) { dimension in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(dimension.color)
                                .frame(width: 10, height: 10)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(dimension.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppColors.text)
                                Text(dimension.detail)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            guideRow(title: "0-3", text: dimension.lowRangeDescription)
                            guideRow(title: "4-6", text: dimension.midRangeDescription)
                            guideRow(title: "7-10", text: dimension.highRangeDescription)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            guideTagBlock(
                                title: "Often linked with",
                                items: dimension.relatedSystems
                            )
                            guideTagBlock(
                                title: "Body signs",
                                items: dimension.bodySignals
                            )
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(dimension.color.opacity(0.16), lineWidth: 1)
                    )
                }
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.headline)
                    .foregroundStyle(Color(hex: "0F766E"))

                VStack(alignment: .leading, spacing: 4) {
                    Text("How to read the signals")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                    Text("Descriptions for low, middle, and high states, plus simple body cues.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(AppColors.text)
        .padding(22)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
    }

    private func guideRow(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 38, alignment: .leading)

            Text(text)
                .font(.caption)
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func guideTagBlock(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.textSecondary)

            FlowLayout(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupSection(_ group: StateDimensionGroup) -> some View {
        let dimensions = StateDimensionDefinition.catalog.filter { $0.group == group }

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.text)
                Text(group.summary)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: 12) {
                ForEach(dimensions) { dimension in
                    StateDimensionSliderCard(
                        dimension: dimension,
                        value: wheelBinding(for: dimension)
                    )
                }
            }
        }
        .padding(18)
        .background(groupBackground(for: group))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.86), lineWidth: 1)
        )
    }

    private func groupBackground(for group: StateDimensionGroup) -> LinearGradient {
        switch group {
        case .body:
            return LinearGradient(
                colors: [Color(hex: "FFF7ED"), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mind:
            return LinearGradient(
                colors: [Color(hex: "EEF2FF"), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Optional note")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColors.text)

            TextField("What is shaping this state right now?", text: $note, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(AppColors.text)
                .padding(16)
                .background(Color.white.opacity(0.84))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .lineLimit(2 ... 4)
        }
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reflection")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColors.text)

            Text(StateInsightGenerator.describe(draft: draft, note: note))
                .font(.subheadline)
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(StateInsightGenerator.highlights(for: draft), id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "F8FAFC"),
                    Color(hex: "EFF6FF")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.86), lineWidth: 1)
        )
    }

    private var latestTimestampLabel: String {
        guard let latest = store.records.first else { return "None yet" }
        return latest.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var activeProfileLabel: String {
        guard let name = profileStore.selectedProfile?.displayName else { return "Profile" }
        return name.localizedCaseInsensitiveContains("sample") ? "Sample Data" : name
    }

    private var overallFeelingBinding: Binding<Int> {
        Binding(
            get: { inferredFeelingLevel(for: draft) },
            set: { newValue in
                applyOverallFeeling(level: newValue)
            }
        )
    }

    private var currentFeelingEntry: StateFeelingEntry {
        StateFeelingEntry.entry(for: inferredFeelingLevel(for: draft))
    }

    private var recommendationStateRecord: StateCheckInRecord {
        StateCheckInRecord(
            id: justSavedID ?? UUID(),
            createdAt: store.records.first?.createdAt ?? Date(),
            scores: draft.scores,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            reflection: StateInsightGenerator.describe(draft: draft, note: note)
        )
    }

    private var recentStateTrendPoints: [RecentStateTrendPoint] {
        Array(store.records.prefix(7).reversed().enumerated()).map { index, record in
            let level = inferredFeelingLevel(for: record.scores)
            return RecentStateTrendPoint(
                recordID: record.id,
                position: index,
                level: level,
                label: record.createdAt.formatted(.dateTime.weekday(.narrow)),
                detailLabel: record.createdAt.formatted(date: .abbreviated, time: .shortened),
                entry: StateFeelingEntry.entry(for: level)
            )
        }
    }

    private var recommendedAction: HealthAction? {
        guard let actionID = stateActionVM.recommendation?.actionID else { return nil }
        return actionsVM.actions.first(where: { $0.id == actionID })
    }

    private var currentFingerprint: String {
        snapshotFingerprint(scores: draft.scores, note: note)
    }

    private var canSaveCurrentState: Bool {
        guard profileStore.selectedProfileID != nil else { return false }
        return currentFingerprint != lastSavedFingerprint
    }

    private var saveButtonTitle: String {
        canSaveCurrentState ? "Save state" : "Saved"
    }

    private var saveButtonSystemImage: String {
        canSaveCurrentState ? "checkmark.circle.fill" : "checkmark.seal.fill"
    }

    private var overallDescriptor: StateOverallDescriptor {
        StateInsightGenerator.overallDescriptor(for: draft)
    }

    private var saveCelebrationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(hex: "0F766E"))

            VStack(alignment: .leading, spacing: 2) {
                Text("State saved")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.text)
                Text("Your latest snapshot is now part of State history.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
    }

    private var stateBackground: some View {
        ZStack {
            AppColors.background
            LinearGradient(
                colors: [
                    Color(hex: "FFFBEB").opacity(0.84),
                    Color(hex: "F8FAFC"),
                    Color(hex: "EEF2FF").opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(hex: "FDE68A").opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 24)
                .offset(x: -150, y: -250)

            Circle()
                .fill(Color(hex: "BFDBFE").opacity(0.26))
                .frame(width: 340, height: 340)
                .blur(radius: 24)
                .offset(x: 150, y: 260)
        }
    }

    private func wheelBinding(for dimension: StateDimensionDefinition) -> Binding<Int> {
        Binding(
            get: { Int(round(draft.score(for: dimension.id) * 10)) },
            set: { newValue in
                draft.setScore(Double(newValue) / 10.0, for: dimension.id)
            }
        )
    }

    private func inferredFeelingLevel(for draft: StateSnapshotDraft) -> Int {
        inferredFeelingLevel(for: draft.scores)
    }

    private func inferredFeelingLevel(for scores: [String: Double]) -> Int {
        let contributions = StateDimensionDefinition.catalog.map { dimension in
            let score = scores[dimension.id] ?? 0.5
            return dimension.highIsPositive ? score : (1 - score)
        }

        let average = contributions.reduce(0, +) / Double(contributions.count)
        return Int(round(average * 10))
    }

    private func applyOverallFeeling(level: Int) {
        let normalized = max(0, min(10, level))
        let positive = Double(normalized) / 10.0
        let stress = 1 - positive

        draft.setScore(positive, for: "physical_energy")
        draft.setScore(max(0, min(1, positive * 0.95 + 0.02)), for: "mental_energy")
        draft.setScore(positive, for: "mood")
        draft.setScore(max(0, min(1, positive * 0.9 + 0.05)), for: "motivation")
        draft.setScore(max(0, min(1, positive * 0.92 + 0.04)), for: "body_comfort")
        draft.setScore(max(0, min(1, stress)), for: "stress_load")
    }

    private func resetDraft() {
        draft = StateSnapshotDraft.neutral
        skipNextNoteInference = true
        note = ""
        noteInferenceMessage = nil
        lastInferredSignature = nil
        justSavedID = nil
        syncAdaptiveRecommendation()
    }

    private func loadDraftFromLatest() {
        guard let latest = store.records.first else {
            lastSavedFingerprint = nil
            resetDraft()
            return
        }
        lastSavedFingerprint = snapshotFingerprint(record: latest)
        loadDraft(from: latest)
    }

    private func loadDraft(from record: StateCheckInRecord) {
        draft = StateSnapshotDraft(scores: record.scores)
        skipNextNoteInference = true
        note = record.note
        noteInferenceMessage = nil
        lastInferredSignature = snapshotFingerprint(scores: record.scores, note: record.note)
        justSavedID = record.id
        syncAdaptiveRecommendation()
    }

    private func saveSnapshot() {
        guard canSaveCurrentState else { return }
        guard let record = store.save(draft: draft, note: note) else { return }
        justSavedID = record.id
        lastSavedFingerprint = snapshotFingerprint(record: record)
        saveAnimationToken += 1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            showSaveCelebration = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                showSaveCelebration = false
            }
        }
        loadDraft(from: record)
        syncAdaptiveRecommendation()
        presentPostSaveActionPrompt(for: record)
    }

    private func syncAdaptiveRecommendation() {
        actionsVM.sync(profileID: profileStore.selectedProfileID, document: documentVM.document)
        stateActionVM.sync(
            profileID: profileStore.selectedProfileID,
            actions: actionsVM.actions,
            state: recommendationStateRecord
        )
    }

    private func handleNoteChanged() {
        if skipNextNoteInference {
            skipNextNoteInference = false
            return
        }

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            noteInferenceTask?.cancel()
            noteInferenceMessage = nil
            lastInferredSignature = nil
            isInferringFromNote = false
            return
        }

        queueNoteInference(for: trimmed, voiceEnergy: nil)
    }

    private func queueNoteInference(for text: String, voiceEnergy: Double?) {
        let signature = inferenceSignature(for: text, voiceEnergy: voiceEnergy)
        guard signature != lastInferredSignature else { return }

        noteInferenceTask?.cancel()
        noteInferenceTask = Task {
            if voiceEnergy == nil {
                try? await Task.sleep(nanoseconds: 850_000_000)
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isInferringFromNote = true
            }

            let result = await inferState(from: text, voiceEnergy: voiceEnergy)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                applyOverallFeeling(level: result.level)
                lastInferredSignature = signature
                noteInferenceMessage = "Detected \(StateFeelingEntry.entry(for: result.level).title) \(result.level)/10"
                isInferringFromNote = false
                syncAdaptiveRecommendation()
            }
        }
    }

    private func handleVoiceNote(_ draft: RecordedVoiceNoteDraft) async {
        defer {
            try? FileManager.default.removeItem(at: draft.fileURL)
        }

        let energy = analyzedVoiceEnergy(from: draft.waveform)

        await MainActor.run {
            isTranscribingVoiceNote = true
            noteInferenceMessage = nil
        }

        do {
            let transcript = try await AppleSpeechTranscriptionService.transcribe(url: draft.fileURL)
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw LLMError.requestFailed("The voice note could not be turned into text.")
            }

            await MainActor.run {
                let existing = note.trimmingCharacters(in: .whitespacesAndNewlines)
                skipNextNoteInference = true
                note = existing.isEmpty ? trimmed : "\(existing)\n\(trimmed)"
                isTranscribingVoiceNote = false
            }

            queueNoteInference(for: trimmed, voiceEnergy: energy)
        } catch {
            if let config = settingsVM.activeProvider, config.type.usesManagedTrialAccess {
                do {
                    let transcript = try await VoiceNoteTranscriptionService.transcribe(draft: draft, settingsVM: settingsVM)
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        throw LLMError.requestFailed("The voice note could not be turned into text.")
                    }

                    await MainActor.run {
                        let existing = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        skipNextNoteInference = true
                        note = existing.isEmpty ? trimmed : "\(existing)\n\(trimmed)"
                        isTranscribingVoiceNote = false
                    }

                    queueNoteInference(for: trimmed, voiceEnergy: energy)
                    return
                } catch {
                    let lowered = error.localizedDescription.lowercased()
                    if lowered.contains("trial") || lowered.contains("quota") || lowered.contains("credit") || lowered.contains("transcription") {
                        applyVoiceEnergyFallback(
                            energy,
                            message: "Voice tone read. Add text too if you want the full meaning captured."
                        )
                        return
                    }
                }
            }

            let lowered = error.localizedDescription.lowercased()
            if lowered.contains("speech") || lowered.contains("recognition") || lowered.contains("transcription") {
                applyVoiceEnergyFallback(
                    energy,
                    message: "Voice tone read. Add text too if you want the full meaning captured."
                )
                return
            }

            await MainActor.run {
                isTranscribingVoiceNote = false
                noteInferenceMessage = error.localizedDescription
            }
        }
    }

    private func inferState(from text: String, voiceEnergy: Double?) async -> StateSignalInference {
        let heuristic = StateNoteInferenceEngine.heuristicInference(text: text, voiceEnergy: voiceEnergy)

        guard let config = settingsVM.activeProvider else {
            return heuristic
        }

        guard !config.type.isLocal, ChatViewModel.hasCloudConsent(for: config.type) else {
            return heuristic
        }

        do {
            let credential = try await settingsVM.resolvedCredential(for: config)
            let service = LLMService(config: config, apiKey: credential)
            let response = try await service.completeChat(messages: [
                (role: "system", content: StateNoteInferenceEngine.systemPrompt),
                (role: "user", content: StateNoteInferenceEngine.prompt(text: text, voiceEnergy: voiceEnergy, fallback: heuristic))
            ])
            return StateNoteInferenceEngine.decode(response) ?? heuristic
        } catch {
            return heuristic
        }
    }

    private func inferenceSignature(for text: String, voiceEnergy: Double?) -> String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
        let energyPart = voiceEnergy.map { String(format: "%.3f", $0) } ?? "-"
        return "\(normalized)|\(energyPart)"
    }

    private func analyzedVoiceEnergy(from waveform: [Double]) -> Double? {
        guard !waveform.isEmpty else { return nil }

        let normalized = waveform.map { sample in
            max(0, min(1, (sample - 0.12) / 0.88))
        }
        let count = Double(normalized.count)
        guard count > 0 else { return nil }

        let mean = normalized.reduce(0, +) / count
        let peak = normalized.max() ?? mean
        let activeRatio = Double(normalized.filter { $0 > 0.18 }.count) / count
        let variance = normalized.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / count
        let spread = sqrt(variance)

        let composite = (mean * 0.42) + (peak * 0.28) + (activeRatio * 0.18) + (spread * 0.12)
        return max(0, min(1, composite))
    }

    @MainActor
    private func applyVoiceEnergyFallback(_ energy: Double?, message: String) {
        let inferred = StateNoteInferenceEngine.heuristicInference(text: "", voiceEnergy: energy)
        applyOverallFeeling(level: inferred.level)
        isTranscribingVoiceNote = false
        isInferringFromNote = false
        noteInferenceMessage = message
        lastInferredSignature = nil
        syncAdaptiveRecommendation()
    }

    private func completeRecommendedAction(_ action: HealthAction) {
        guard !actionsVM.isCompletedToday(action) else { return }

        actionsVM.toggleCompletedToday(action)
        Task {
            await nextBestActionVM.saveOutcome(
                RecoveryActionOutcome(actionID: action.id, completed: true),
                document: documentVM.document,
                actions: actionsVM.actions
            )
        }
        syncAdaptiveRecommendation()
    }

    private func presentPostSaveActionPrompt(for record: StateCheckInRecord) {
        guard let recommendation = stateActionVM.recommendation,
              let action = recommendedAction else {
            postSaveActionPrompt = nil
            return
        }

        postSaveActionPrompt = PostCheckInActionPrompt(
            action: action,
            recommendation: recommendation,
            entry: StateFeelingEntry.entry(for: inferredFeelingLevel(for: record.scores))
        )
    }

    private func recordRecommendedActionFeedback(_ action: HealthAction, helpful: Bool) async {
        if !actionsVM.isCompletedToday(action) {
            actionsVM.toggleCompletedToday(action)
        }

        await nextBestActionVM.saveOutcome(
            RecoveryActionOutcome(
                actionID: action.id,
                completed: true,
                helpfulnessRating: helpful ? 5 : 1,
                notes: helpful ? "Helpful from State follow-up." : "Not helpful from State follow-up."
            ),
            document: documentVM.document,
            actions: actionsVM.actions
        )
        syncAdaptiveRecommendation()
    }

    private func snapshotFingerprint(scores: [String: Double], note: String) -> String {
        let scorePart = StateDimensionDefinition.catalog
            .map { dimension in
                let value = scores[dimension.id] ?? 0.5
                return "\(dimension.id)=\(Int(round(value * 10)))"
            }
            .joined(separator: "|")

        let normalizedNote = note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        return "\(scorePart)|note=\(normalizedNote)"
    }

    private func snapshotFingerprint(record: StateCheckInRecord) -> String {
        snapshotFingerprint(scores: record.scores, note: record.note)
    }
}

private struct StateDimensionSliderCard: View {
    let dimension: StateDimensionDefinition
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dimension.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColors.text)

                    Text(dimension.descriptor(for: Double(value) / 10))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(dimension.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text("\(value)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(dimension.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(dimension.color.opacity(0.1))
                    .clipShape(Capsule())
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int(round($0)) }
                ),
                in: 0 ... 10,
                step: 1
            )
            .tint(dimension.color)
            .sensoryFeedback(.selection, trigger: value)

            HStack(spacing: 8) {
                Text(dimension.lowLabel.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                Text(dimension.highLabel.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(dimension.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(dimension.color.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct RecentStateTrendPoint: Identifiable {
    let recordID: UUID
    let position: Int
    let level: Int
    let label: String
    let detailLabel: String
    let entry: StateFeelingEntry

    var id: UUID { recordID }
}

private struct PostCheckInActionPrompt: Identifiable {
    let action: HealthAction
    let recommendation: StateActionRecommendation
    let entry: StateFeelingEntry

    var id: String { action.id }
}

private struct RecentStateTrendChart: View {
    let points: [RecentStateTrendPoint]
    let highlightedRecordID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let latest = points.last {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(latest.level) / 10")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.text)
                        Text(latest.entry.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(latest.entry.tint)
                    }

                    Spacer()

                    Text(latest.detailLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Chart(points) { point in
                AreaMark(
                    x: .value("State", point.position),
                    yStart: .value("Baseline", 0),
                    yEnd: .value("Level", point.level)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "F59E0B").opacity(0.18),
                            Color(hex: "0F766E").opacity(0.2),
                            Color(hex: "06B6D4").opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("State", point.position),
                    y: .value("Level", point.level)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "C2410C"),
                            Color(hex: "0F766E"),
                            Color(hex: "06B6D4")
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(points) { item in
                    PointMark(
                        x: .value("State", item.position),
                        y: .value("Level", item.level)
                    )
                    .symbolSize(item.recordID == highlightedRecordID ? 120 : 70)
                    .foregroundStyle(item.entry.tint)
                }

                RuleMark(y: .value("Neutral", 5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(Color.white.opacity(0.95))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 5, 10]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        .foregroundStyle(Color.white.opacity(0.75))
                    AxisValueLabel {
                        if let level = value.as(Int.self) {
                            Text("\(level)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: points.map(\.position)) { value in
                    AxisValueLabel {
                        if let position = value.as(Int.self),
                           let point = points.first(where: { $0.position == position }) {
                            Text(point.label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... 10)
            .frame(height: 190)
        }
        .padding(18)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        )
    }
}

private struct RecentStateMiniCard: View {
    let record: StateCheckInRecord
    let isHighlighted: Bool

    private var entry: StateFeelingEntry {
        StateFeelingEntry.entry(for: StateInsightGenerator.feelingLevel(for: record.scores))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.tint.opacity(isHighlighted ? 0.18 : 0.12))
                    .frame(width: 42, height: 42)

                Text("\(entry.level)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(entry.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(isHighlighted ? 0.96 : 0.84))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHighlighted ? entry.tint.opacity(0.32) : AppColors.border, lineWidth: 1)
        )
    }
}

private struct SuggestedNextActionSheet: View {
    let prompt: PostCheckInActionPrompt
    let isAlreadyCompleted: Bool
    let onOpenAction: () -> Void
    let onDoNow: () -> Void
    let onFeedback: (Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAwaitingFeedback = false
    @State private var isSubmittingFeedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested next action")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(prompt.entry.tint)
                    Text(prompt.action.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                    Text(prompt.action.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    actionChip(prompt.action.category.title, tint: prompt.action.category.tint)
                    actionChip(prompt.action.durationLabel, tint: prompt.entry.tint)
                    actionChip("\(prompt.entry.level)/10 state", tint: prompt.entry.tint)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Why this fits")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.text)

                    ForEach(prompt.recommendation.whyItFits, id: \.self) { item in
                        Label(item, systemImage: "sparkles")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try this now")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.text)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(prompt.action.steps.prefix(4).enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(prompt.action.category.tint)
                                    .clipShape(Circle())

                                Text(step)
                                    .font(.subheadline)
                                    .foregroundStyle(AppColors.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(prompt.action.category.tint.opacity(0.14), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    if isAwaitingFeedback || isAlreadyCompleted {
                        Text("Did that help?")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppColors.text)

                        HStack(spacing: 12) {
                            feedbackButton(
                                title: "Helpful",
                                systemImage: "hand.thumbsup.fill",
                                tint: Color(hex: "0F766E")
                            ) {
                                await submitFeedback(helpful: true)
                            }

                            feedbackButton(
                                title: "Not really",
                                systemImage: "hand.thumbsdown.fill",
                                tint: Color(hex: "C2410C")
                            ) {
                                await submitFeedback(helpful: false)
                            }
                        }

                        Button("I’ll answer later") {
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    } else {
                        Button {
                            onDoNow()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                isAwaitingFeedback = true
                            }
                        } label: {
                            Label("Do it right now", systemImage: "play.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(prompt.action.category.tint)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 12) {
                            Button("Open in Action") {
                                onOpenAction()
                                dismiss()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )

                            Button("Not now") {
                                dismiss()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.76))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "FFFBEB"),
                    Color.white,
                    prompt.entry.tint.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private func submitFeedback(helpful: Bool) async {
        guard !isSubmittingFeedback else { return }
        isSubmittingFeedback = true
        await onFeedback(helpful)
        isSubmittingFeedback = false
        dismiss()
    }

    private func actionChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.1))
            .clipShape(Capsule())
    }

    private func feedbackButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmittingFeedback)
        .opacity(isSubmittingFeedback ? 0.8 : 1)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct StateCheckInRecord: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let scores: [String: Double]
    let note: String
    let reflection: String

    func score(for dimensionID: String) -> Double {
        scores[dimensionID] ?? 0.5
    }

    var topHighlights: [String] {
        StateDimensionDefinition.catalog
            .map { dimension -> (String, Double) in
                let score = score(for: dimension.id)
                let adjusted = dimension.highIsPositive ? score : (1 - score)
                return (dimension.shortTitle.lowercased(), adjusted)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map(\.0)
    }
}

struct StateSnapshotDraft: Equatable {
    var scores: [String: Double]

    init(scores: [String: Double] = StateDimensionDefinition.catalog.reduce(into: [:]) { partial, dimension in
        partial[dimension.id] = 0.5
    }) {
        self.scores = scores
    }

    static let neutral = StateSnapshotDraft()

    func score(for dimensionID: String) -> Double {
        scores[dimensionID] ?? 0.5
    }

    mutating func setScore(_ score: Double, for dimensionID: String) {
        scores[dimensionID] = max(0, min(1, score))
    }
}

struct StateDimensionDefinition: Identifiable {
    let id: String
    let group: StateDimensionGroup
    let title: String
    let shortTitle: String
    let angleDegrees: Double
    let color: Color
    let lowLabel: String
    let highLabel: String
    let detail: String
    let highIsPositive: Bool
    let lowRangeDescription: String
    let midRangeDescription: String
    let highRangeDescription: String
    let relatedSystems: [String]
    let bodySignals: [String]

    var angleRadians: Double {
        angleDegrees * .pi / 180
    }

    var unitVector: CGVector {
        CGVector(dx: cos(angleRadians), dy: sin(angleRadians))
    }

    func descriptor(for score: Double) -> String {
        switch score {
        case ..<0.2:
            return lowLabel.capitalized
        case ..<0.4:
            return "Low \(title.lowercased())"
        case ..<0.6:
            return "Balanced"
        case ..<0.8:
            return "Strong \(title.lowercased())"
        default:
            return highLabel.capitalized
        }
    }

    static let catalog: [StateDimensionDefinition] = [
        StateDimensionDefinition(
            id: "physical_energy",
            group: .body,
            title: "Physical energy",
            shortTitle: "Physical",
            angleDegrees: -90,
            color: Color(hex: "EA580C"),
            lowLabel: "depleted",
            highLabel: "charged",
            detail: "How much physical fuel feels available in your body right now.",
            highIsPositive: true,
            lowRangeDescription: "The body may feel heavy, underpowered, slow to start, or effortful to move.",
            midRangeDescription: "Enough fuel for basic tasks, but pacing still matters and reserve feels limited.",
            highRangeDescription: "The body feels fueled, mobile, and more willing to initiate effort.",
            relatedSystems: ["dopamine", "orexin", "circadian rhythm"],
            bodySignals: ["heaviness", "slower movement", "yawning", "wanting rest"]
        ),
        StateDimensionDefinition(
            id: "mental_energy",
            group: .mind,
            title: "Mental energy",
            shortTitle: "Mental",
            angleDegrees: -30,
            color: Color(hex: "4F46E5"),
            lowLabel: "foggy",
            highLabel: "engaged",
            detail: "How ready your mind feels for thinking, deciding, and staying with a task.",
            highIsPositive: true,
            lowRangeDescription: "Thinking may feel slow, scattered, or hard to hold onto for long.",
            midRangeDescription: "You can think and respond, but sustained focus may still drift.",
            highRangeDescription: "The mind feels awake, connected, and easier to direct on purpose.",
            relatedSystems: ["acetylcholine", "dopamine", "sleep pressure"],
            bodySignals: ["brain fog", "slowed recall", "easier distraction", "mental fatigue"]
        ),
        StateDimensionDefinition(
            id: "mood",
            group: .mind,
            title: "Mood",
            shortTitle: "Mood",
            angleDegrees: 30,
            color: Color(hex: "059669"),
            lowLabel: "heavy",
            highLabel: "lifted",
            detail: "The emotional tone of the moment, from compressed to more open and steady.",
            highIsPositive: true,
            lowRangeDescription: "The emotional tone may feel tight, flat, low, or harder to carry lightly.",
            midRangeDescription: "Emotionally mixed or neutral, with some steadiness but not much lift.",
            highRangeDescription: "Mood feels lighter, warmer, or more open to connection and movement.",
            relatedSystems: ["serotonin", "dopamine", "social safety"],
            bodySignals: ["facial tension", "tearfulness", "withdrawal", "easier smiling"]
        ),
        StateDimensionDefinition(
            id: "motivation",
            group: .mind,
            title: "Motivation",
            shortTitle: "Drive",
            angleDegrees: 90,
            color: Color(hex: "0F766E"),
            lowLabel: "flat",
            highLabel: "ready",
            detail: "How much momentum you feel to start, continue, or finish something useful.",
            highIsPositive: true,
            lowRangeDescription: "Starting feels hard, effort feels costly, and even simple actions may feel far away.",
            midRangeDescription: "You can get going with structure, but the engine does not run on its own yet.",
            highRangeDescription: "There is a noticeable pull toward doing, finishing, or moving forward.",
            relatedSystems: ["dopamine", "reward expectation", "goal salience"],
            bodySignals: ["procrastination", "stalling", "task avoidance", "urge to begin"]
        ),
        StateDimensionDefinition(
            id: "body_comfort",
            group: .body,
            title: "Body comfort",
            shortTitle: "Body",
            angleDegrees: 150,
            color: Color(hex: "DB2777"),
            lowLabel: "tight",
            highLabel: "settled",
            detail: "How comfortable, grounded, and physically at ease your body feels.",
            highIsPositive: true,
            lowRangeDescription: "The body may feel tense, achy, braced, restless, or difficult to inhabit.",
            midRangeDescription: "Some parts feel okay while others still hold tension or irritation.",
            highRangeDescription: "The body feels more settled, grounded, and less demanding of attention.",
            relatedSystems: ["parasympathetic tone", "muscle tension", "pain load"],
            bodySignals: ["jaw tension", "shoulder tightness", "aches", "easier breathing"]
        ),
        StateDimensionDefinition(
            id: "stress_load",
            group: .body,
            title: "Stress load",
            shortTitle: "Stress",
            angleDegrees: 210,
            color: Color(hex: "7C3AED"),
            lowLabel: "calm",
            highLabel: "maxed",
            detail: "How much internal pressure, urgency, or overload you are carrying.",
            highIsPositive: false,
            lowRangeDescription: "The system feels relatively calm, with more room between stimulus and reaction.",
            midRangeDescription: "Some pressure is present, but it still feels workable and containable.",
            highRangeDescription: "The system feels activated, overloaded, or primed for urgency and threat scanning.",
            relatedSystems: ["cortisol", "adrenaline", "sympathetic activation"],
            bodySignals: ["fast thoughts", "shallow breathing", "clenched body", "urge to rush"]
        )
    ]
}

struct StateOverallDescriptor {
    let title: String
    let tint: Color
}

private struct StateFeelingEntry: Identifiable {
    let level: Int
    let title: String
    let subtitle: String
    let tint: Color

    var id: Int { level }

    static let entries: [StateFeelingEntry] = [
        StateFeelingEntry(level: 0, title: "Awful", subtitle: "Everything feels like too much.", tint: Color(hex: "B91C1C")),
        StateFeelingEntry(level: 1, title: "Drained", subtitle: "Very low energy and little room.", tint: Color(hex: "C2410C")),
        StateFeelingEntry(level: 2, title: "Heavy", subtitle: "The system feels weighed down.", tint: Color(hex: "D97706")),
        StateFeelingEntry(level: 3, title: "Fragile", subtitle: "A bit tender and easy to tip.", tint: Color(hex: "EA580C")),
        StateFeelingEntry(level: 4, title: "Uneven", subtitle: "Some parts are okay, some are not.", tint: Color(hex: "CA8A04")),
        StateFeelingEntry(level: 5, title: "Okay", subtitle: "Neutral, workable, and in the middle.", tint: Color(hex: "0F766E")),
        StateFeelingEntry(level: 6, title: "Steady", subtitle: "Fairly grounded and usable.", tint: Color(hex: "0D9488")),
        StateFeelingEntry(level: 7, title: "Good", subtitle: "There is some lift in the system.", tint: Color(hex: "059669")),
        StateFeelingEntry(level: 8, title: "Light", subtitle: "More openness and less drag.", tint: Color(hex: "10B981")),
        StateFeelingEntry(level: 9, title: "Strong", subtitle: "A lot feels available right now.", tint: Color(hex: "14B8A6")),
        StateFeelingEntry(level: 10, title: "Bright", subtitle: "Open, clear, and resourced.", tint: Color(hex: "06B6D4"))
    ]

    static func entry(for level: Int) -> StateFeelingEntry {
        let clamped = max(0, min(10, level))
        return entries[clamped]
    }
}

private struct StateSignalInference {
    let level: Int
}

private enum StateNoteInferenceEngine {
    static let systemPrompt = """
    You infer how a person feels from a short text or transcribed voice note.
    Return only JSON in this exact shape:
    {"level": 0}
    The level must be an integer from 0 to 10 where 0 is awful and 10 is bright.
    """

    static func prompt(text: String, voiceEnergy: Double?, fallback: StateSignalInference) -> String {
        let energyLine: String
        if let voiceEnergy {
            energyLine = "Voice energy is \(String(format: "%.2f", voiceEnergy)) on a 0-1 scale."
        } else {
            energyLine = "No voice energy was provided."
        }

        return """
        Infer the user's current overall feeling from this note.
        \(energyLine)
        Fallback estimate: \(fallback.level)/10.

        Note:
        \(text)
        """
    }

    static func heuristicInference(text: String, voiceEnergy: Double?) -> StateSignalInference {
        let normalized = text.lowercased()
        if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let voiceEnergy {
            let level = Int(round(2 + (voiceEnergy * 6)))
            return StateSignalInference(level: max(0, min(10, level)))
        }

        var score = 5.0

        let weightedTerms: [(String, Double)] = [
            ("panic", -4.0), ("panicked", -4.0), ("overwhelmed", -3.0), ("stressed", -2.5),
            ("anxious", -2.5), ("sad", -2.5), ("down", -1.5), ("tired", -2.0),
            ("exhausted", -3.0), ("drained", -3.0), ("burned out", -4.0), ("burnt out", -4.0),
            ("foggy", -2.0), ("sick", -2.0), ("pain", -2.0), ("heavy", -2.0),
            ("restless", -1.5), ("angry", -2.5), ("bad", -1.5), ("low", -1.5),
            ("calm", 1.5), ("steady", 1.5), ("okay", 0.5), ("fine", 0.5),
            ("good", 1.5), ("great", 2.0), ("light", 2.0), ("clear", 2.0),
            ("focused", 2.0), ("rested", 2.0), ("energized", 2.5), ("bright", 3.0),
            ("strong", 2.0), ("open", 1.5), ("grateful", 1.0)
        ]

        for (term, delta) in weightedTerms where normalized.contains(term) {
            score += delta
        }

        let highStressTerms = ["panic", "panicked", "anxious", "overwhelmed", "stressed", "angry", "rushed"]
        let containsHighStress = highStressTerms.contains { normalized.contains($0) }

        if let voiceEnergy {
            switch voiceEnergy {
            case ..<0.12:
                score -= 2.0
            case ..<0.24:
                score -= 1.0
            case 0.86...:
                score += containsHighStress ? -1.0 : 1.4
            case 0.68...:
                score += containsHighStress ? -0.5 : 0.9
            case 0.52...:
                score += containsHighStress ? -0.2 : 0.35
            default:
                break
            }
        }

        let clamped = max(0, min(10, Int(round(score))))
        return StateSignalInference(level: clamped)
    }

    static func decode(_ raw: String) -> StateSignalInference? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}") else {
            return nil
        }

        let json = String(raw[start ... end])
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        return StateSignalInference(level: max(0, min(10, payload.level)))
    }

    private struct Payload: Decodable {
        let level: Int
    }
}

final class StateCheckInStore: ObservableObject {
    @Published private(set) var records: [StateCheckInRecord] = []

    private var activeProfileID: UUID?

    func load(for profileID: UUID?) {
        activeProfileID = profileID
        guard let profileID else {
            records = []
            return
        }

        records = (EncryptedStore.load([StateCheckInRecord].self, forKey: storageKey(for: profileID)) ?? [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(draft: StateSnapshotDraft, note: String) -> StateCheckInRecord? {
        guard let profileID = activeProfileID else { return nil }

        let record = StateCheckInRecord(
            id: UUID(),
            createdAt: Date(),
            scores: draft.scores,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            reflection: StateInsightGenerator.describe(draft: draft, note: note)
        )

        records.insert(record, at: 0)
        EncryptedStore.save(records, forKey: storageKey(for: profileID))
        StateActionLearningEngine.resolvePendingInterventions(profileID: profileID, with: record)
        load(for: profileID)
        return records.first(where: { $0.id == record.id }) ?? record
    }

    private func storageKey(for profileID: UUID) -> String {
        "state_check_in_history_\(profileID.uuidString)"
    }
}

private enum StateInsightGenerator {
    static func feelingLevel(for scores: [String: Double]) -> Int {
        let contributions = StateDimensionDefinition.catalog.map { dimension in
            let score = scores[dimension.id] ?? 0.5
            return dimension.highIsPositive ? score : (1 - score)
        }

        let average = contributions.reduce(0, +) / Double(contributions.count)
        return Int(round(average * 10))
    }

    static func overallDescriptor(for draft: StateSnapshotDraft) -> StateOverallDescriptor {
        let score = balancedScore(for: draft)

        switch score {
        case ..<0.33:
            return StateOverallDescriptor(title: "Strained", tint: Color(hex: "B91C1C"))
        case ..<0.55:
            return StateOverallDescriptor(title: "Mixed", tint: Color(hex: "C2410C"))
        case ..<0.75:
            return StateOverallDescriptor(title: "Steady", tint: Color(hex: "0F766E"))
        default:
            return StateOverallDescriptor(title: "Open", tint: Color(hex: "047857"))
        }
    }

    static func overallDescriptor(for record: StateCheckInRecord) -> StateOverallDescriptor {
        overallDescriptor(for: StateSnapshotDraft(scores: record.scores))
    }

    static func describe(draft: StateSnapshotDraft, note: String) -> String {
        let physical = draft.score(for: "physical_energy")
        let mental = draft.score(for: "mental_energy")
        let mood = draft.score(for: "mood")
        let motivation = draft.score(for: "motivation")
        let comfort = draft.score(for: "body_comfort")
        let stress = draft.score(for: "stress_load")

        let opener: String
        if physical < 0.35 && mental < 0.4 {
            opener = "This snapshot leans depleted. Your physical and mental energy both look low, so today probably needs less volume and more protection around recovery."
        } else if stress > 0.72 && mood < 0.52 {
            opener = "Pressure is carrying a lot of the picture right now. The combination of higher stress load and a heavier mood suggests keeping plans tighter and simpler."
        } else if motivation > 0.62 && mental > 0.58 {
            opener = "There is usable momentum here. Your mental energy and motivation look available enough to support one meaningful task without forcing it."
        } else if comfort > 0.66 && mood > 0.6 {
            opener = "Your state looks relatively settled. The body and emotional tone both read more open, which is usually a good base for a steady day."
        } else {
            opener = "Your state looks mixed rather than one-note. A few parts of you are available, but not everything is moving in the same direction."
        }

        let brightest = topAvailableDimensions(for: draft)
        let anchorLine: String
        if brightest.isEmpty {
            anchorLine = "There is not a strong surplus area showing up, so the best move may be to reduce friction and aim for gentle wins."
        } else {
            anchorLine = "What still looks available: \(brightest.joined(separator: " and ")). Use that as the anchor instead of expecting the whole system to feel great."
        }

        let noteLine: String
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteLine = ""
        } else {
            noteLine = " You noted: \(note.trimmingCharacters(in: .whitespacesAndNewlines))."
        }

        return opener + " " + anchorLine + noteLine
    }

    static func highlights(for draft: StateSnapshotDraft) -> [String] {
        let topTwo = topAvailableDimensions(for: draft)
        let pressure = draft.score(for: "stress_load")
        var items = topTwo

        if pressure > 0.7 {
            items.append("high pressure")
        } else if pressure < 0.3 {
            items.append("low pressure")
        }

        return Array(items.prefix(3))
    }

    private static func balancedScore(for draft: StateSnapshotDraft) -> Double {
        let contributions = StateDimensionDefinition.catalog.map { dimension in
            let score = draft.score(for: dimension.id)
            return dimension.highIsPositive ? score : (1 - score)
        }
        return contributions.reduce(0, +) / Double(contributions.count)
    }

    private static func topAvailableDimensions(for draft: StateSnapshotDraft) -> [String] {
        StateDimensionDefinition.catalog
            .map { dimension -> (String, Double) in
                let score = draft.score(for: dimension.id)
                let adjusted = dimension.highIsPositive ? score : (1 - score)
                return (dimension.shortTitle.lowercased(), adjusted)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .filter { $0.1 > 0.55 }
            .map(\.0)
    }
}
