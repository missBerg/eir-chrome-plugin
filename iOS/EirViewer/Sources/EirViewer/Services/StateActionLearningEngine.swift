import Foundation

struct StateActionRecommendation: Identifiable, Equatable {
    let id = UUID()
    let actionID: String
    let headline: String
    let summary: String
    let whyItFits: [String]
    let learningLabel: String
    let confidence: Double
    let score: Double
}

struct StateActionLearningSummary: Equatable {
    let resolvedExperiences: Int
    let pendingFollowUps: Int
    let learningLabel: String
    let statusLine: String

    static let empty = StateActionLearningSummary(
        resolvedExperiences: 0,
        pendingFollowUps: 0,
        learningLabel: "Starting",
        statusLine: "Save a state, try an action, then save a follow-up state."
    )
}

private struct StateActionPendingIntervention: Codable, Hashable, Identifiable {
    let id: UUID
    let actionID: String
    let createdAt: Date
    let preStateScores: [String: Double]
}

private struct StateActionLearningExperience: Codable, Hashable, Identifiable {
    let id: UUID
    let actionID: String
    let createdAt: Date
    let resolvedAt: Date
    let reward: Double
    let stateDelta: Double
}

private struct StateActionLearningPayload: Codable {
    var pending: [StateActionPendingIntervention] = []
    var experiences: [StateActionLearningExperience] = []
}

enum StateActionLearningEngine {
    static func recordActionCompletion(profileID: UUID, actionID: String) {
        guard let latestState = loadLatestState(profileID: profileID) else { return }

        var payload = loadPayload(profileID: profileID)
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        let alreadyPending = payload.pending.contains {
            $0.actionID == actionID &&
            calendar.isDate($0.createdAt, inSameDayAs: Date())
        }

        guard !alreadyPending else { return }

        payload.pending.append(
            StateActionPendingIntervention(
                id: UUID(),
                actionID: actionID,
                createdAt: Date(),
                preStateScores: latestState.scores
            )
        )
        payload.pending = Array(payload.pending.sorted { $0.createdAt > $1.createdAt }.prefix(16))
        savePayload(payload, profileID: profileID)
    }

    @discardableResult
    static func resolvePendingInterventions(profileID: UUID, with state: StateCheckInRecord) -> Int {
        var payload = loadPayload(profileID: profileID)
        var resolvedCount = 0
        var remaining: [StateActionPendingIntervention] = []

        for pending in payload.pending {
            guard pending.createdAt < state.createdAt else {
                remaining.append(pending)
                continue
            }

            let interval = state.createdAt.timeIntervalSince(pending.createdAt)
            if interval > 60 * 60 * 48 {
                continue
            }

            let reward = rewardScore(pre: pending.preStateScores, post: state.scores)
            payload.experiences.append(
                StateActionLearningExperience(
                    id: UUID(),
                    actionID: pending.actionID,
                    createdAt: pending.createdAt,
                    resolvedAt: state.createdAt,
                    reward: reward,
                    stateDelta: reward
                )
            )
            resolvedCount += 1
        }

        payload.pending = Array(remaining.sorted { $0.createdAt > $1.createdAt }.prefix(16))
        payload.experiences = Array(payload.experiences.sorted { $0.resolvedAt > $1.resolvedAt }.prefix(160))
        savePayload(payload, profileID: profileID)
        return resolvedCount
    }

    static func summary(profileID: UUID?) -> StateActionLearningSummary {
        guard let profileID else { return .empty }
        let payload = loadPayload(profileID: profileID)
        let label = learningLabel(for: payload.experiences.count)
        let line: String

        if payload.experiences.isEmpty {
            line = "The engine is still exploring what tends to help from each state."
        } else if payload.pending.isEmpty {
            line = "Learned from \(payload.experiences.count) state follow-up\(payload.experiences.count == 1 ? "" : "s") on this device."
        } else {
            line = "\(payload.pending.count) action follow-up\(payload.pending.count == 1 ? "" : "s") waiting for the next saved state."
        }

        return StateActionLearningSummary(
            resolvedExperiences: payload.experiences.count,
            pendingFollowUps: payload.pending.count,
            learningLabel: label,
            statusLine: line
        )
    }

    static func recommend(
        profileID: UUID?,
        actions: [HealthAction],
        state: StateCheckInRecord?
    ) -> StateActionRecommendation? {
        guard let profileID, let state, !actions.isEmpty else { return nil }

        let payload = loadPayload(profileID: profileID)
        let actionLookup = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        let totalExperienceCount = max(payload.experiences.count, 1)
        let context = TimeAwareRecommendationContext.current()
        let candidateActions = filteredActions(actions, for: context)

        let ranked = candidateActions.map { action -> (HealthAction, Double, [String], Int) in
            let heuristic = heuristicScore(for: action.category, scores: state.scores)
            let actionExperiences = payload.experiences.filter { $0.actionID == action.id }
            let categoryExperiences = payload.experiences.filter { experience in
                guard let learnedAction = actionLookup[experience.actionID] else { return false }
                return learnedAction.category == action.category
            }

            let actionMean = meanReward(for: actionExperiences)
            let categoryMean = meanReward(for: categoryExperiences)
            let exploration = min(
                sqrt(log(Double(totalExperienceCount) + 1) / Double(actionExperiences.count + 1)) * 0.18,
                0.18
            )
            let temporal = temporalAdjustment(for: action, context: context)

            let score =
                (heuristic * 0.62) +
                (normalizeReward(actionMean) * 0.22) +
                (normalizeReward(categoryMean) * 0.08) +
                exploration +
                temporal

            return (
                action,
                score,
                explanation(
                    for: action,
                    state: state,
                    context: context,
                    actionExperienceCount: actionExperiences.count,
                    actionMean: actionMean
                ),
                actionExperiences.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.durationMinutes < rhs.0.durationMinutes
            }
            return lhs.1 > rhs.1
        }

        guard let best = ranked.first else { return nil }
        let confidence = min(0.36 + (Double(best.3) * 0.12), 0.86)

        return StateActionRecommendation(
            actionID: best.0.id,
            headline: best.0.title,
            summary: best.0.summary,
            whyItFits: best.2,
            learningLabel: learningLabel(for: best.3),
            confidence: confidence,
            score: best.1
        )
    }

    private static func heuristicScore(for category: HealthActionCategory, scores: [String: Double]) -> Double {
        let lowPhysical = 1 - (scores["physical_energy"] ?? 0.5)
        let lowMental = 1 - (scores["mental_energy"] ?? 0.5)
        let lowMood = 1 - (scores["mood"] ?? 0.5)
        let lowMotivation = 1 - (scores["motivation"] ?? 0.5)
        let lowComfort = 1 - (scores["body_comfort"] ?? 0.5)
        let highStress = scores["stress_load"] ?? 0.5

        let value: Double
        switch category {
        case .movement:
            value = (0.30 * lowMood) + (0.28 * lowMotivation) + (0.22 * lowPhysical) + (0.12 * highStress) + (0.08 * lowMental)
        case .breath:
            value = (0.52 * highStress) + (0.26 * lowComfort) + (0.14 * lowMental) + (0.08 * lowMood)
        case .recovery:
            value = (0.30 * highStress) + (0.22 * lowPhysical) + (0.22 * lowComfort) + (0.14 * lowMental) + (0.12 * lowMood)
        case .hydration:
            value = (0.38 * lowPhysical) + (0.28 * highStress) + (0.18 * lowComfort) + (0.16 * lowMental)
        case .focus:
            value = (0.42 * lowMental) + (0.26 * lowMotivation) + (0.18 * highStress) + (0.14 * lowMood)
        case .sleep:
            value = (0.32 * lowPhysical) + (0.26 * highStress) + (0.22 * lowMental) + (0.20 * lowMood)
        case .planning:
            value = (0.40 * lowMotivation) + (0.26 * lowMental) + (0.18 * highStress) + (0.16 * lowMood)
        case .nutrition:
            value = (0.38 * lowPhysical) + (0.22 * lowMood) + (0.20 * highStress) + (0.20 * lowMental)
        }

        return min(max(value, 0), 1)
    }

    private static func filteredActions(
        _ actions: [HealthAction],
        for context: TimeAwareRecommendationContext
    ) -> [HealthAction] {
        let filtered = actions.filter { !isStrongTimeMismatch($0, context: context) }
        return filtered.isEmpty ? actions : filtered
    }

    private static func isStrongTimeMismatch(
        _ action: HealthAction,
        context: TimeAwareRecommendationContext
    ) -> Bool {
        if action.id == "starter-daylight-walk" {
            return context.isNight
        }
        return false
    }

    private static func temporalAdjustment(
        for action: HealthAction,
        context: TimeAwareRecommendationContext
    ) -> Double {
        if action.id == "starter-daylight-walk" {
            if context.isNight { return -0.9 }
            if context.isEvening { return -0.25 }
            if context.isMorning || context.isDay { return 0.16 }
        }

        if action.id == "starter-evening-close" || action.id == "records-sleep-runway" {
            if context.isEvening { return 0.24 }
            if context.isNight { return 0.32 }
            if context.isMorning { return -0.22 }
            if context.isDay { return -0.12 }
        }

        switch action.category {
        case .sleep:
            if context.isEvening { return 0.18 }
            if context.isNight { return 0.24 }
            if context.isMorning { return -0.18 }
            return -0.08
        case .movement:
            if context.isMorning || context.isDay { return 0.1 }
            if context.isEvening { return -0.04 }
            return -0.18
        case .focus, .planning:
            if context.isMorning || context.isDay { return 0.08 }
            if context.isNight { return -0.16 }
            return -0.04
        case .breath, .recovery:
            if context.isNight { return 0.1 }
            if context.isEvening { return 0.06 }
            return 0
        case .hydration, .nutrition:
            if context.isNight { return -0.04 }
            return 0.02
        }
    }

    private static func explanation(
        for action: HealthAction,
        state: StateCheckInRecord,
        context: TimeAwareRecommendationContext,
        actionExperienceCount: Int,
        actionMean: Double
    ) -> [String] {
        var reasons: [String] = []
        reasons.append(overallStateReason(for: action, state: state))

        if let noteReason = noteReason(for: action, note: state.note) {
            reasons.append(noteReason)
        }

        if let timeReason = timeOfDayReason(for: action, context: context) {
            reasons.append(timeReason)
        }

        if actionExperienceCount > 0 {
            if actionMean > 0.08 {
                reasons.append("This action has improved later states \(actionExperienceCount) time\(actionExperienceCount == 1 ? "" : "s") on this device.")
            } else if actionMean < -0.08 {
                reasons.append("The engine is still exploring this action because past results have been mixed.")
            } else {
                reasons.append("Past follow-ups for this action are still neutral, so the engine is balancing fit and exploration.")
            }
        } else {
            reasons.append("No direct follow-up history yet, so this is partly an exploration pick.")
        }

        return Array(reasons.prefix(3))
    }

    private static func overallStateReason(
        for action: HealthAction,
        state: StateCheckInRecord
    ) -> String {
        let level = overallFeelingLevel(for: state.scores)
        let title = overallFeelingTitle(for: level).lowercased()

        switch action.category {
        case .breath, .recovery, .sleep:
            if level <= 3 {
                return "You checked in feeling \(title), so this leans gentle and low-friction."
            } else if level <= 6 {
                return "You checked in around the middle, so this helps steady the system before adding more load."
            } else {
                return "You already have some room in the system, so this helps protect that steadier state."
            }
        case .movement, .focus, .planning:
            if level <= 3 {
                return "You checked in feeling \(title), so the recommendation favors a small doable step instead of something demanding."
            } else if level <= 6 {
                return "You checked in with a workable state, so this turns that into one concrete next move."
            } else {
                return "You checked in with more available energy, so this uses that momentum while it is there."
            }
        case .hydration, .nutrition:
            if level <= 3 {
                return "You checked in feeling \(title), so the recommendation starts with basic support before intensity."
            } else {
                return "You checked in with enough room for a simple supportive action right now."
            }
        }
    }

    private static func overallFeelingLevel(for scores: [String: Double]) -> Int {
        let positiveIDs = ["physical_energy", "mental_energy", "mood", "motivation", "body_comfort"]
        let positiveAverage = positiveIDs
            .map { scores[$0] ?? 0.5 }
            .reduce(0, +) / Double(positiveIDs.count)
        let stress = scores["stress_load"] ?? 0.5
        let combined = (positiveAverage * 0.72) + ((1 - stress) * 0.28)
        return max(0, min(10, Int(round(combined * 10))))
    }

    private static func overallFeelingTitle(for level: Int) -> String {
        switch max(0, min(10, level)) {
        case 0: return "Awful"
        case 1: return "Drained"
        case 2: return "Heavy"
        case 3: return "Fragile"
        case 4: return "Uneven"
        case 5: return "Okay"
        case 6: return "Steady"
        case 7: return "Good"
        case 8: return "Light"
        case 9: return "Strong"
        default: return "Bright"
        }
    }

    private static func noteReason(for action: HealthAction, note: String) -> String? {
        let normalized = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let stressedTerms = ["stress", "stressed", "overwhelmed", "panic", "panicked", "anxious", "rushed", "too much"]
        let lowEnergyTerms = ["tired", "drained", "exhausted", "foggy", "heavy", "flat", "burned out", "burnt out"]
        let positiveTerms = ["good", "clear", "steady", "light", "strong", "ready", "focused", "motivated"]

        if stressedTerms.contains(where: normalized.contains) {
            switch action.category {
            case .breath, .recovery, .sleep:
                return "Your note sounds pressured, so this aims to lower load before anything else."
            default:
                return "Your note sounds pressured, so this is framed as one contained next step rather than something bigger."
            }
        }

        if lowEnergyTerms.contains(where: normalized.contains) {
            switch action.category {
            case .movement:
                return "Your note sounds low-energy, so this keeps the activation light instead of pushing hard."
            default:
                return "Your note sounds low-energy, so this favors support over intensity."
            }
        }

        if positiveTerms.contains(where: normalized.contains) {
            switch action.category {
            case .focus, .planning, .movement:
                return "Your note sounds more available, so this uses that momentum in a directed way."
            default:
                return "Your note sounds fairly steady, so this helps consolidate that state."
            }
        }

        return nil
    }

    private static func timeOfDayReason(
        for action: HealthAction,
        context: TimeAwareRecommendationContext
    ) -> String? {
        if action.id == "starter-daylight-walk", context.isMorning || context.isDay {
            return "It fits the current local time, so the recommendation can safely lean on daylight and activation."
        }

        if (action.id == "starter-evening-close" || action.id == "records-sleep-runway"),
           context.isEvening || context.isNight {
            return "It matches the current local time, so the recommendation leans toward a softer evening landing."
        }

        switch action.category {
        case .sleep where context.isEvening || context.isNight:
            return "It suits the current local time, so winding down makes more sense than activating."
        case .movement where context.isMorning || context.isDay:
            return "It suits the current local time, so a little activation is more likely to help than late-night stimulation."
        default:
            return nil
        }
    }

    private static func rewardScore(pre: [String: Double], post: [String: Double]) -> Double {
        let positiveIDs = ["physical_energy", "mental_energy", "mood", "motivation", "body_comfort"]
        let positiveDelta = positiveIDs
            .map { (post[$0] ?? 0.5) - (pre[$0] ?? 0.5) }
            .reduce(0, +) / Double(positiveIDs.count)

        let stressDelta = (pre["stress_load"] ?? 0.5) - (post["stress_load"] ?? 0.5)
        return min(max((positiveDelta * 0.72) + (stressDelta * 0.28), -1), 1)
    }

    private static func meanReward(for experiences: [StateActionLearningExperience]) -> Double {
        guard !experiences.isEmpty else { return 0 }
        return experiences.map(\.reward).reduce(0, +) / Double(experiences.count)
    }

    private static func normalizeReward(_ reward: Double) -> Double {
        min(max((reward + 1) / 2, 0), 1)
    }

    private static func learningLabel(for experienceCount: Int) -> String {
        switch experienceCount {
        case 0:
            return "Exploring"
        case 1 ... 3:
            return "Learning"
        case 4 ... 8:
            return "Adapting"
        default:
            return "Personalized"
        }
    }

    private static func loadPayload(profileID: UUID) -> StateActionLearningPayload {
        EncryptedStore.load(StateActionLearningPayload.self, forKey: storageKey(for: profileID)) ?? StateActionLearningPayload()
    }

    private static func savePayload(_ payload: StateActionLearningPayload, profileID: UUID) {
        EncryptedStore.save(payload, forKey: storageKey(for: profileID))
    }

    private static func loadLatestState(profileID: UUID) -> StateCheckInRecord? {
        (EncryptedStore.load([StateCheckInRecord].self, forKey: stateStorageKey(for: profileID)) ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private static func storageKey(for profileID: UUID) -> String {
        "eir_state_action_learning_\(profileID.uuidString)"
    }

    private static func stateStorageKey(for profileID: UUID) -> String {
        "state_check_in_history_\(profileID.uuidString)"
    }
}

private struct TimeAwareRecommendationContext {
    let hour: Int
    let timeZone: TimeZone

    var isMorning: Bool { (6...10).contains(hour) }
    var isDay: Bool { (11...16).contains(hour) }
    var isEvening: Bool { (17...21).contains(hour) }
    var isNight: Bool { hour >= 22 || hour <= 5 }

    static func current(now: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> TimeAwareRecommendationContext {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: now)
        return TimeAwareRecommendationContext(hour: hour, timeZone: timeZone)
    }
}

@MainActor
final class StateActionRecommendationViewModel: ObservableObject {
    @Published private(set) var recommendation: StateActionRecommendation?
    @Published private(set) var summary: StateActionLearningSummary = .empty

    func sync(profileID: UUID?, actions: [HealthAction], state: StateCheckInRecord?) {
        recommendation = StateActionLearningEngine.recommend(
            profileID: profileID,
            actions: actions,
            state: state
        )
        summary = StateActionLearningEngine.summary(profileID: profileID)
    }
}
