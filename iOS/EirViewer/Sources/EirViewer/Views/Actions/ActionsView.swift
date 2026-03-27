import SwiftUI
import UIKit

struct ForYouView: View {
    @EnvironmentObject var actionsVM: ActionsViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var forYouVM: ForYouViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var localModelManager: LocalModelManager

    @State private var selectedCard: ForYouCard?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVStack(spacing: 16) {
                    ForEach(Array(forYouVM.cards.enumerated()), id: \.element.id) { index, card in
                        ForYouFeedCard(
                            card: card,
                            prominence: prominence(for: index),
                            isFavorite: forYouVM.isFavorite(card),
                            actionState: actionState(for: card)
                        )
                        .gesture(cardGesture(for: card))
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: forYouVM.favoriteIDs)
                    }

                    loadMoreSentinel
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(feedBackground.ignoresSafeArea())
        .navigationTitle("For You")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedCard) { card in
            ForYouSheet(card: card)
                .environmentObject(actionsVM)
                .environmentObject(forYouVM)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            syncFeed()
        }
        .alert(
            "Share Data with \(forYouVM.pendingCloudConsent?.displayName ?? "Cloud Provider")?",
            isPresented: Binding(
                get: { forYouVM.pendingCloudConsent != nil },
                set: { if !$0 { forYouVM.consentDenied() } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                forYouVM.consentDenied()
            }
            Button("I Agree") {
                Task {
                    await forYouVM.consentGrantedAndLoadMore(
                        settingsVM: settingsVM,
                        localModelManager: localModelManager
                    )
                }
            }
        } message: {
            Text("Your records will be sent to \(forYouVM.pendingCloudConsent?.displayName ?? "the selected provider") to generate more cards for For You. This data may include health information. On-device models keep everything on your phone.")
        }
        .onChange(of: profileStore.selectedProfileID) {
            syncFeed()
        }
        .onChange(of: documentSignature) {
            syncFeed()
        }
        .onChange(of: actionsSignature) {
            syncFeed()
        }
    }

    @ViewBuilder
    private var loadMoreSentinel: some View {
        if forYouVM.isLoadingMore {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppColors.text)
                Text("Bringing in five more")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if let error = forYouVM.loadMoreError {
            Button {
                Task {
                    await forYouVM.retryLoadMore(
                        settingsVM: settingsVM,
                        localModelManager: localModelManager
                    )
                }
            } label: {
                VStack(spacing: 6) {
                    Text("Try again")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColors.text)
                    Text(error)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task {
                        await forYouVM.loadMoreIfNeeded(
                            settingsVM: settingsVM,
                            localModelManager: localModelManager
                        )
                    }
                }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 10) {
                    feedMetric(value: "\(actionsVM.completedTodayCount)", label: "Done")
                    feedMetric(value: "\(actionsVM.scheduledActions.count)", label: "Later")
                }
            }

            Spacer()

            if !forYouVM.favoriteIDs.isEmpty {
                Label("\(forYouVM.favoriteIDs.count)", systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.78))
                    .clipShape(Capsule())
            }
        }
    }

    private var feedBackground: some View {
        ZStack {
            AppColors.background
            LinearGradient(
                colors: [
                    Color(hex: "FFF4E8").opacity(0.55),
                    Color.clear,
                    Color(hex: "EEF2FF").opacity(0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: Date())
    }

    private var documentSignature: String {
        guard let document = documentVM.document else { return "none" }
        return "\(document.entries.count)-\(document.entries.first?.id ?? "none")"
    }

    private var actionsSignature: String {
        actionsVM.actions.map(\.id).joined(separator: "|")
    }

    private func syncFeed() {
        actionsVM.sync(profileID: profileStore.selectedProfileID, document: documentVM.document)
        forYouVM.sync(
            profileID: profileStore.selectedProfileID,
            document: documentVM.document,
            actions: actionsVM.actions
        )
    }

    private func feedMetric(value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.78))
        .clipShape(Capsule())
    }

    private func cardGesture(for card: ForYouCard) -> some Gesture {
        ExclusiveGesture(TapGesture(count: 2), TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        forYouVM.toggleFavorite(card)
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                case .second:
                    selectedCard = card
                }
            }
    }

    private func prominence(for index: Int) -> ForYouCardProminence {
        if index == 0 { return .hero }
        if index < 4 { return .feature }
        return .compact
    }

    private func actionState(for card: ForYouCard) -> ForYouActionCardState? {
        guard let action = card.action else { return nil }
        let state = actionsVM.state(for: action)
        return ForYouActionCardState(
            isCompletedToday: actionsVM.isCompletedToday(action),
            isScheduled: state.schedule != nil,
            statusLine: state.schedule.map(scheduleLine)
        )
    }

    private func scheduleLine(_ schedule: HealthActionSchedule) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = schedule.cadence == .once ? .medium : .none
        return "\(schedule.cadence.title) • \(formatter.string(from: schedule.date))"
    }
}

private struct ForYouActionCardState {
    let isCompletedToday: Bool
    let isScheduled: Bool
    let statusLine: String?
}

private enum ForYouCardProminence {
    case hero
    case feature
    case compact

    var minHeight: CGFloat {
        switch self {
        case .hero: return 330
        case .feature: return 270
        case .compact: return 220
        }
    }

    var titleFont: Font {
        switch self {
        case .hero: return .system(size: 31, weight: .bold, design: .rounded)
        case .feature: return .system(size: 25, weight: .bold, design: .rounded)
        case .compact: return .system(size: 21, weight: .bold, design: .rounded)
        }
    }

    var summaryLimit: Int {
        switch self {
        case .hero: return 3
        case .feature: return 3
        case .compact: return 2
        }
    }
}

private struct ForYouFeedCard: View {
    let card: ForYouCard
    let prominence: ForYouCardProminence
    let isFavorite: Bool
    let actionState: ForYouActionCardState?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardBackground

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text(card.eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(card.theme.accent)

                    Spacer()

                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(card.theme.accent)
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 12) {
                    Text(card.title)
                        .font(prominence.titleFont)
                        .foregroundStyle(card.theme.textColor)
                        .multilineTextAlignment(.leading)

                    Text(card.summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(card.theme.textColor.opacity(0.82))
                        .lineLimit(prominence.summaryLimit)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        metaChip(card.kind.label)
                        if let durationLabel = card.durationLabel {
                            metaChip(durationLabel)
                        }
                        if let actionState, actionState.isCompletedToday {
                            metaChip("Done")
                        } else if let actionState, actionState.isScheduled {
                            metaChip("Later")
                        }
                    }

                    if let actionState, let statusLine = actionState.statusLine, prominence != .compact {
                        Text(statusLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(card.theme.textColor.opacity(0.72))
                    }
                }
            }
            .padding(22)
        }
        .frame(minHeight: prominence.minHeight)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: card.theme.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(card.theme.accent.opacity(0.30))
                .frame(width: prominence == .hero ? 240 : 180, height: prominence == .hero ? 240 : 180)
                .blur(radius: 32)
                .offset(x: 110, y: -100)

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: prominence == .hero ? 190 : 140, height: prominence == .hero ? 190 : 140)
                .blur(radius: 18)
                .offset(x: -120, y: -80)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: prominence == .hero ? 300 : 220, height: 120)
                .rotationEffect(.degrees(-18))
                .offset(x: 140, y: 70)

            Image(systemName: card.symbolName)
                .font(.system(size: prominence == .hero ? 120 : 88, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.09))
                .offset(x: prominence == .hero ? 126 : 106, y: -10)
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(card.theme.textColor.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ForYouSheet: View {
    let card: ForYouCard
    @EnvironmentObject var actionsVM: ActionsViewModel
    @EnvironmentObject var forYouVM: ForYouViewModel

    var body: some View {
        switch card.kind {
        case .action:
            ForYouActionSheet(card: card)
                .environmentObject(actionsVM)
        case .meditation:
            BreathingCardSheet(card: card)
        case .quiz:
            QuizCardSheet(card: card)
        case .reading:
            ReadingCardSheet(card: card)
        case .reflection:
            ReflectionCardSheet(card: card)
                .environmentObject(forYouVM)
        case .soundscape:
            ReadingCardSheet(card: card)
        }
    }
}

private struct ForYouActionSheet: View {
    let card: ForYouCard
    @EnvironmentObject var actionsVM: ActionsViewModel
    @State private var showSchedule = false

    var body: some View {
        if let action = card.action {
            ActionDetailSheet(
                theme: card.theme,
                action: action,
                state: actionsVM.state(for: action),
                isCompletedToday: actionsVM.isCompletedToday(action),
                onToggleComplete: { actionsVM.toggleCompletedToday(action) },
                onTogglePin: { actionsVM.togglePinned(action) },
                onSchedule: { showSchedule = true },
                onClearSchedule: {
                    Task { await actionsVM.clearSchedule(for: action) }
                }
            )
            .sheet(isPresented: $showSchedule) {
                ActionScheduleSheet(
                    theme: card.theme,
                    action: action,
                    existingSchedule: actionsVM.state(for: action).schedule
                ) { date, cadence, notificationsEnabled, calendarEnabled in
                    Task {
                        await actionsVM.applySchedule(
                            for: action,
                            date: date,
                            cadence: cadence,
                            notificationsEnabled: notificationsEnabled,
                            calendarEnabled: calendarEnabled
                        )
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct ActionDetailSheet: View {
    let theme: ForYouCardTheme
    let action: HealthAction
    let state: HealthActionState
    let isCompletedToday: Bool
    let onToggleComplete: () -> Void
    let onTogglePin: () -> Void
    let onSchedule: () -> Void
    let onClearSchedule: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHero(
                        eyebrow: action.category.title,
                        title: action.title,
                        summary: action.summary,
                        accent: theme.accent,
                        durationLabel: action.durationLabel,
                        symbolName: action.category.systemImage,
                        gradient: theme.gradient
                    )

                    FloatingSheetSection(theme: theme) {
                        VStack(alignment: .leading, spacing: 10) {
                        Text("Why")
                            .font(.headline)
                        ForEach(action.benefits, id: \.self) { benefit in
                            Label(benefit, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.text)
                        }
                    }
                    }

                    FloatingSheetSection(theme: theme) {
                        VStack(alignment: .leading, spacing: 12) {
                        Text("Steps")
                            .font(.headline)
                        ForEach(Array(action.steps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(theme.deepTone)
                                    .clipShape(Circle())
                                Text(step)
                                    .foregroundStyle(AppColors.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    }

                    FloatingSheetSection(theme: theme) {
                        VStack(spacing: 12) {
                        actionButton(
                            title: isCompletedToday ? "Done today" : "Done",
                            systemImage: "checkmark.circle.fill",
                            fill: theme.deepTone,
                            foreground: .white,
                            action: onToggleComplete
                        )
                        actionButton(
                            title: state.schedule == nil ? "Later" : "Edit time",
                            systemImage: "calendar.badge.plus",
                            fill: Color.white,
                            foreground: AppColors.text,
                            action: onSchedule
                        )
                        actionButton(
                            title: state.isPinned ? "Unpin" : "Pin",
                            systemImage: state.isPinned ? "pin.slash" : "pin.fill",
                            fill: Color.white,
                            foreground: AppColors.text,
                            action: onTogglePin
                        )
                        if state.schedule != nil {
                            actionButton(
                                title: "Remove schedule",
                                systemImage: "bell.slash",
                                fill: Color.white,
                                foreground: AppColors.red,
                                action: onClearSchedule
                            )
                        }
                    }
                    }
                }
                .padding(20)
            }
            .background(sheetBackground(theme: theme))
            .navigationTitle("Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func actionButton(title: String, systemImage: String, fill: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.border, lineWidth: fill == .white ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct BreathingCardSheet: View {
    let card: ForYouCard
    @Environment(\.dismiss) private var dismiss
    @State private var isRunning = false
    @State private var remaining = 0
    @State private var phaseLabel = "Ready"
    @State private var phaseInstruction = "Let the circle set the pace."
    @State private var orbScale: CGFloat = 0.78
    @State private var ringProgress: Double = 0
    @State private var glowOpacity = 0.34
    @State private var currentRound = 0
    @State private var sessionTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    SheetHero(
                        eyebrow: card.eyebrow,
                        title: card.title,
                        summary: card.summary,
                        accent: card.theme.accent,
                        durationLabel: card.durationLabel,
                        symbolName: card.symbolName,
                        gradient: card.theme.gradient
                    )

                    FloatingSheetSection(theme: card.theme) {
                        VStack(spacing: 20) {
                            breathingOrb
                                .padding(.top, 4)

                            VStack(spacing: 6) {
                                Text(phaseLabel)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(card.theme.deepTone)
                                Text(phaseInstruction)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                Text(remaining > 0 ? "\(remaining)s left" : "\(breathing.totalSeconds)s total")
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.text)
                            }

                            HStack(spacing: 10) {
                                phaseChip("In", value: "\(breathing.inhaleSeconds)s")
                                phaseChip("Out", value: "\(breathing.exhaleSeconds)s")
                                phaseChip("Rounds", value: "\(breathing.rounds)")
                            }

                            Button(isRunning ? "Pause" : (remaining == breathing.totalSeconds ? "Start" : "Start over")) {
                                if isRunning {
                                    pause()
                                } else {
                                    start()
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(card.theme.deepTone)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
            .background(sheetBackground(theme: card.theme))
            .navigationTitle("Reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                remaining = breathing.totalSeconds
            }
            .onDisappear {
                stopSession()
            }
        }
    }

    private var breathing: ForYouBreathing {
        card.breathing ?? ForYouBreathing(inhaleSeconds: 4, exhaleSeconds: 6, rounds: 6)
    }

    private var breathingOrb: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.48), lineWidth: 14)
                .frame(width: 250, height: 250)

            Circle()
                .trim(from: 0, to: max(ringProgress, 0.01))
                .stroke(
                    LinearGradient(
                        colors: [card.theme.accent, card.theme.deepTone],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 250, height: 250)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(card.theme.accent.opacity(glowOpacity))
                .frame(width: 210, height: 210)
                .blur(radius: 18)
                .scaleEffect(orbScale)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            card.theme.accent.opacity(0.18)
                        ],
                        center: .center,
                        startRadius: 12,
                        endRadius: 100
                    )
                )
                .frame(width: 174, height: 174)
                .scaleEffect(orbScale)

            VStack(spacing: 6) {
                Text(isRunning ? phaseLabel : "Ready")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColors.text)
                Text(currentRound > 0 ? "Round \(currentRound) of \(breathing.rounds)" : "Find an easy seat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func phaseChip(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppColors.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(card.theme.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var phaseSequence: [BreathingPhase] {
        (0..<breathing.rounds).flatMap { round in
            [
                BreathingPhase(
                    kind: .inhale,
                    seconds: breathing.inhaleSeconds,
                    round: round + 1
                ),
                BreathingPhase(
                    kind: .exhale,
                    seconds: breathing.exhaleSeconds,
                    round: round + 1
                )
            ]
        }
    }

    private func start() {
        stopSession()
        isRunning = true
        remaining = breathing.totalSeconds
        ringProgress = 0
        currentRound = 1
        sessionTask = Task {
            let phases = phaseSequence
            let totalTicks = max(breathing.totalSeconds * 10, 1)
            var elapsedTicks = 0

            for phase in phases {
                if Task.isCancelled { return }

                await MainActor.run {
                    currentRound = phase.round
                    phaseLabel = phase.kind.title
                    phaseInstruction = phase.kind.instruction
                    withAnimation(.easeInOut(duration: Double(phase.seconds))) {
                        orbScale = phase.kind.scale
                        glowOpacity = phase.kind.glowOpacity
                    }
                }

                let phaseTicks = max(phase.seconds * 10, 1)
                for _ in 0..<phaseTicks {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    elapsedTicks += 1
                    await MainActor.run {
                        ringProgress = min(Double(elapsedTicks) / Double(totalTicks), 1)
                        remaining = max(
                            breathing.totalSeconds - Int((Double(elapsedTicks) / 10.0).rounded(.toNearestOrAwayFromZero)),
                            0
                        )
                    }
                }
            }

            await MainActor.run {
                finish()
            }
        }
    }

    private func pause() {
        stopSession()
        phaseLabel = "Paused"
        phaseInstruction = "Take a moment, then start again when you want."
    }

    private func finish() {
        stopSession()
        remaining = 0
        ringProgress = 1
        phaseLabel = "Complete"
        phaseInstruction = "Nice. Keep that slower pace for the next few minutes."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func stopSession() {
        sessionTask?.cancel()
        sessionTask = nil
        isRunning = false
    }

    private struct BreathingPhase {
        let kind: BreathingPhaseKind
        let seconds: Int
        let round: Int
    }

    private enum BreathingPhaseKind {
        case inhale
        case exhale

        var title: String {
            switch self {
            case .inhale: return "Inhale"
            case .exhale: return "Exhale"
            }
        }

        var instruction: String {
            switch self {
            case .inhale: return "Draw the breath in slowly through the nose."
            case .exhale: return "Let the exhale be long and unforced."
            }
        }

        var scale: CGFloat {
            switch self {
            case .inhale: return 1.06
            case .exhale: return 0.8
            }
        }

        var glowOpacity: Double {
            switch self {
            case .inhale: return 0.42
            case .exhale: return 0.24
            }
        }
    }
}

private struct QuizCardSheet: View {
    let card: ForYouCard
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOptionID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHero(
                        eyebrow: card.eyebrow,
                        title: card.title,
                        summary: card.summary,
                        accent: card.theme.accent,
                        durationLabel: card.durationLabel,
                        symbolName: card.symbolName,
                        gradient: card.theme.gradient
                    )

                    FloatingSheetSection(theme: card.theme) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(quiz.question)
                                .font(.headline)
                                .foregroundStyle(AppColors.text)

                            VStack(spacing: 12) {
                                ForEach(quiz.options) { option in
                                    Button {
                                        selectedOptionID = option.id
                                    } label: {
                                        HStack {
                                            Text(option.title)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if selectedOptionID == option.id {
                                                Image(systemName: option.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            }
                                        }
                                        .font(.headline)
                                        .foregroundStyle(AppColors.text)
                                        .padding(18)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(card.theme.accent.opacity(selectedOptionID == option.id ? 0.16 : 0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(
                                                    card.theme.accent.opacity(selectedOptionID == option.id ? 0.55 : 0.14),
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if let selected = quiz.options.first(where: { $0.id == selectedOptionID }) {
                        FloatingSheetSection(theme: card.theme) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(selected.isCorrect ? quiz.successTitle : "Try again")
                                    .font(.headline)
                                Text(selected.feedback)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(sheetBackground(theme: card.theme))
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var quiz: ForYouQuiz {
        card.quiz ?? ForYouQuiz(question: "", options: [], successTitle: "")
    }
}

private struct ReadingCardSheet: View {
    let card: ForYouCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHero(
                        eyebrow: card.eyebrow,
                        title: card.title,
                        summary: card.summary,
                        accent: card.theme.accent,
                        durationLabel: card.durationLabel,
                        symbolName: card.symbolName,
                        gradient: card.theme.gradient
                    )

                    FloatingSheetSection(theme: card.theme) {
                        VStack(alignment: .leading, spacing: 14) {
                            if let kicker = card.reading?.kicker {
                                Text(kicker)
                                    .font(.headline)
                                    .foregroundStyle(AppColors.text)
                            }

                            ForEach(card.reading?.paragraphs ?? [], id: \.self) { paragraph in
                                Text(paragraph)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(sheetBackground(theme: card.theme))
            .navigationTitle("Read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ReflectionCardSheet: View {
    let card: ForYouCard
    @EnvironmentObject var forYouVM: ForYouViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHero(
                        eyebrow: card.eyebrow,
                        title: card.title,
                        summary: card.summary,
                        accent: card.theme.accent,
                        durationLabel: card.durationLabel,
                        symbolName: card.symbolName,
                        gradient: card.theme.gradient
                    )

                    FloatingSheetSection(theme: card.theme) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(reflection.prompt)
                                .font(.headline)
                                .foregroundStyle(AppColors.text)

                            TextEditor(text: $draft)
                                .padding(14)
                                .frame(minHeight: 220)
                                .background(card.theme.accent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(card.theme.accent.opacity(0.18), lineWidth: 1)
                                )

                            Button("Save") {
                                forYouVM.saveReflection(draft, for: card.id)
                                dismiss()
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(card.theme.deepTone)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
            .background(sheetBackground(theme: card.theme))
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                draft = forYouVM.reflectionText(for: card.id)
            }
        }
    }

    private var reflection: ForYouReflection {
        card.reflection ?? ForYouReflection(prompt: "", placeholder: "")
    }
}

private struct ActionScheduleSheet: View {
    let theme: ForYouCardTheme
    let action: HealthAction
    let existingSchedule: HealthActionSchedule?
    let onSave: (Date, HealthActionCadence, Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var cadence: HealthActionCadence
    @State private var notificationsEnabled: Bool
    @State private var calendarEnabled: Bool

    init(
        theme: ForYouCardTheme,
        action: HealthAction,
        existingSchedule: HealthActionSchedule?,
        onSave: @escaping (Date, HealthActionCadence, Bool, Bool) -> Void
    ) {
        self.theme = theme
        self.action = action
        self.existingSchedule = existingSchedule
        self.onSave = onSave
        _date = State(initialValue: existingSchedule?.date ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date())
        _cadence = State(initialValue: existingSchedule?.cadence ?? .daily)
        _notificationsEnabled = State(initialValue: existingSchedule?.notificationsEnabled ?? true)
        _calendarEnabled = State(initialValue: existingSchedule?.calendarEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHero(
                        eyebrow: "Later",
                        title: action.title,
                        summary: "Choose when this should come back into your day.",
                        accent: theme.accent,
                        durationLabel: action.durationLabel,
                        symbolName: "calendar.badge.clock",
                        gradient: theme.gradient
                    )

                    FloatingSheetSection(theme: theme) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("When")
                                .font(.headline)
                            DatePicker("Start", selection: $date)
                            Picker("Repeat", selection: $cadence) {
                                ForEach(HealthActionCadence.allCases) { cadence in
                                    Text(cadence.title).tag(cadence)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    FloatingSheetSection(theme: theme) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Remind me")
                                .font(.headline)
                            Toggle("Notification", isOn: $notificationsEnabled)
                            Toggle("Calendar", isOn: $calendarEnabled)
                        }
                    }

                    Button("Save") {
                        onSave(date, cadence, notificationsEnabled, calendarEnabled)
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.deepTone)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
            }
            .background(sheetBackground(theme: theme))
            .navigationTitle("Later")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct SheetHero: View {
    let eyebrow: String
    let title: String
    let summary: String
    let accent: Color
    let durationLabel: String?
    let symbolName: String
    var gradient: [Color]? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradient ?? [
                            accent.opacity(0.92),
                            accent.opacity(0.54),
                            Color.white
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 12)
                .offset(x: 120, y: -70)

            Image(systemName: symbolName)
                .font(.system(size: 96, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.08))
                .offset(x: 120, y: -20)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.84))
                    Spacer()
                    if let durationLabel {
                        Text(durationLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .frame(minHeight: 220)
    }
}

private struct FloatingSheetSection<Content: View>: View {
    var theme: ForYouCardTheme? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke((theme?.accent ?? Color.white).opacity(0.14), lineWidth: 1)
        )
    }
}

private func sheetBackground(theme: ForYouCardTheme) -> some View {
    ZStack {
        AppColors.background
        LinearGradient(
            colors: [
                theme.gradient[0].opacity(0.30),
                theme.gradient[1].opacity(0.14),
                Color.white.opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        Circle()
            .fill(theme.accent.opacity(0.16))
            .frame(width: 320, height: 320)
            .blur(radius: 60)
            .offset(x: 150, y: -170)
    }
}
