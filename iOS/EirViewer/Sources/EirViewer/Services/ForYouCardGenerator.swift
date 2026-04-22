import Foundation

enum ForYouCardGenerator {
    static func generate(
        document: EirDocument?,
        actions: [HealthAction],
        assessmentRecords: [AssessmentRecord] = [],
        stateRecords: [StateCheckInRecord] = [],
        now: Date = Date()
    ) -> [ForYouCard] {
        let primaryAction = actions.first
        let additionalActions = Array(actions.dropFirst().prefix(4))
        let context = buildContext(
            from: document,
            assessmentRecords: assessmentRecords,
            stateRecords: stateRecords,
            now: now
        )

        var cards: [ForYouCard] = []

        cards.append(checkInCard(sortOrder: -20, context: context))
        cards.append(doingNothingCard(sortOrder: -9, context: context))
        cards.append(soundSessionCard(sortOrder: -8, context: context))
        cards.append(patternRecallCard(sortOrder: -7, context: context))

        cards.append(assessmentPromptCard(sortOrder: -6, context: context))

        if let primaryAction {
            cards.append(actionCard(primaryAction, sortOrder: 0, theme: .ember, eyebrow: "Best next step"))
        } else {
            cards.append(
                ForYouCard(
                    id: "loop-start",
                    sortOrder: 0,
                    kind: .reading,
                    theme: .meadow,
                    eyebrow: "Start here",
                    title: "Begin the State -> Action -> Reward loop",
                    summary: "Notice how you feel, try one small action, and let Eir learn what helps.",
                    durationLabel: "1 min",
                    symbolName: "arrow.trianglehead.clockwise",
                    action: nil,
                    quiz: nil,
                    reading: ForYouReading(
                        kicker: "You do not need a full history to get started.",
                        paragraphs: [
                            "Begin with one honest snapshot of how you feel today, even if it is brief or incomplete.",
                            "Then try one small action you can finish today. The first useful loop matters more than perfect tracking.",
                            "As you add check-ins, actions, and signals, Eir gets better at showing what improves your health."
                        ]
                    ),
                    reflection: nil,
                    breathing: nil
                )
            )
        }

        cards.append(
            ForYouCard(
                id: "meditation-reset",
                sortOrder: 1,
                kind: .meditation,
                theme: .tide,
                eyebrow: "Reset",
                title: context.hasStressSignals ? "One-minute reset" : (context.hasRecords ? "Slow your pace" : "Start with one calm minute"),
                summary: context.hasRecords
                    ? "A guided breathing minute to steady your body before the next thing."
                    : "A guided breathing minute to help you settle before choosing your next step.",
                durationLabel: "1 min",
                symbolName: "wind",
                action: nil,
                quiz: nil,
                reading: nil,
                reflection: nil,
                breathing: ForYouBreathing(inhaleSeconds: 4, exhaleSeconds: 6, rounds: 6)
            )
        )

        if context.shouldSuggestSocial,
           let socialAction = actions.first(where: { $0.category == .social }),
           socialAction.id != primaryAction?.id {
            cards.append(actionCard(socialAction, sortOrder: 3, theme: .coral, eyebrow: "Social"))
        }

        cards.append(
            ForYouCard(
                id: "quiz-cue",
                sortOrder: 2,
                kind: .quiz,
                theme: .aurora,
                eyebrow: "Tiny quiz",
                title: "What makes a small habit stick?",
                summary: "A 10-second behavior nudge grounded in habit research.",
                durationLabel: "10 sec",
                symbolName: "sparkles",
                action: nil,
                quiz: ForYouQuiz(
                    question: "What makes a five-minute health action most likely to happen?",
                    options: [
                        ForYouQuizOption(
                            id: "motivation",
                            title: "Waiting until you feel motivated",
                            feedback: "Motivation helps, but it is unreliable when life is crowded.",
                            isCorrect: false
                        ),
                        ForYouQuizOption(
                            id: "cue",
                            title: "Attaching it to an existing cue",
                            feedback: "Yes. Existing cues lower friction and make repetition more automatic.",
                            isCorrect: true
                        ),
                        ForYouQuizOption(
                            id: "willpower",
                            title: "Trying to do more at once",
                            feedback: "More ambition usually means more friction, which lowers follow-through.",
                            isCorrect: false
                        )
                    ],
                    successTitle: "Better odds"
                ),
                reading: nil,
                reflection: nil,
                breathing: nil
            )
        )

        cards.append(
            ForYouCard(
                id: "reading-questions",
                sortOrder: 3,
                kind: .reading,
                theme: .coral,
                eyebrow: "2-minute read",
                title: context.hasAppointments ? "Take one better question to care" : (context.hasRecords ? "Use small questions well" : "Ask one useful question"),
                summary: context.hasRecords
                    ? "A short piece on how one prepared question can improve a visit or follow-up."
                    : "A short piece on using one simple question to understand your state better.",
                durationLabel: "2 min",
                symbolName: "book.pages.fill",
                action: nil,
                quiz: nil,
                reading: ForYouReading(
                    kicker: "Good visits often start before the visit itself.",
                    paragraphs: [
                        "A useful health question is specific enough to answer in one conversation and concrete enough to reduce uncertainty.",
                        "Instead of 'What does this mean?', try 'What should I watch for over the next two weeks?'",
                        "If you only prepare one line, you are far more likely to remember it when the visit starts."
                    ]
                ),
                reflection: nil,
                breathing: nil
            )
        )

        cards.append(
            ForYouCard(
                id: "reflection-prompt",
                sortOrder: 4,
                kind: .reflection,
                theme: .velvet,
                eyebrow: "Writing prompt",
                title: "Write one honest line",
                summary: "A short prompt to turn body signals into something you can actually use.",
                durationLabel: "1 min",
                symbolName: "square.and.pencil",
                action: nil,
                quiz: nil,
                reading: nil,
                reflection: ForYouReflection(
                    prompt: context.hasRecords
                        ? "What would make your body feel 5% easier today?"
                        : "What is the smallest thing that would help you feel more steady today?",
                    placeholder: "Write one honest line..."
                ),
                breathing: nil
            )
        )

        let themes: [ForYouCardTheme] = [.meadow, .ember, .tide, .aurora]
        for (offset, action) in additionalActions.enumerated() {
            cards.append(
                actionCard(
                    action,
                    sortOrder: 5 + offset,
                    theme: themes[offset % themes.count],
                    eyebrow: action.source.title
                )
            )
        }

        return cards
    }

    private static func checkInCard(sortOrder: Int, context: ForYouContext) -> ForYouCard {
        if let latestState = context.latestStateRecord,
           context.hoursSinceLatestState < 6 {
            let descriptor = currentStateDescriptor(for: latestState)
            return ForYouCard(
                id: "current-state-\(latestState.id.uuidString)",
                sortOrder: sortOrder,
                kind: .checkIn,
                theme: descriptor.theme,
                eyebrow: "Current state",
                title: "Current state: \(descriptor.title)",
                summary: "Checked in \(relativeAgeLabel(hours: context.hoursSinceLatestState)) ago. Tap to retake whenever your state shifts.",
                durationLabel: "Retake",
                symbolName: "waveform.path.ecg",
                action: nil,
                quiz: nil,
                reading: nil,
                reflection: nil,
                breathing: nil,
                callToAction: "Retake check-in"
            )
        }

        return ForYouCard(
            id: "check-in-\(context.dayPart.rawValue)",
            sortOrder: sortOrder,
            kind: .checkIn,
            theme: .meadow,
            eyebrow: context.dayPart.checkInEyebrow,
            title: "How are you feeling?",
            summary: context.dayPart.checkInSummary,
            durationLabel: "1 min",
            symbolName: "waveform.path.ecg",
            action: nil,
            quiz: nil,
            reading: nil,
            reflection: nil,
            breathing: nil,
            callToAction: "Check in"
        )
    }

    private static func doingNothingCard(sortOrder: Int, context: ForYouContext) -> ForYouCard {
        ForYouCard(
            id: "digital-doing-nothing",
            sortOrder: sortOrder,
            kind: .digital,
            theme: .tide,
            eyebrow: context.hasFreshState ? "Recovery signal" : "Digital",
            title: "Do nothing for five minutes",
            summary: context.hasFreshState
                ? "Turn the current state into a quiet reward loop and earn Nothing Points."
                : "Open Digital and start a quiet session. Real downtime counts as a signal.",
            durationLabel: "5 min",
            symbolName: "sparkles.rectangle.stack",
            action: nil,
            quiz: nil,
            reading: nil,
            reflection: nil,
            breathing: nil,
            callToAction: "Open Digital"
        )
    }

    private static func soundSessionCard(sortOrder: Int, context: ForYouContext) -> ForYouCard {
        let recommendation = context.soundRecommendation
        return ForYouCard(
            id: "sound-\(recommendation.collectionID)-\(context.dayPart.rawValue)",
            sortOrder: sortOrder,
            kind: .soundscape,
            theme: recommendation.theme,
            eyebrow: "Sound",
            title: recommendation.title,
            summary: recommendation.summary,
            durationLabel: recommendation.durationLabel,
            symbolName: recommendation.symbolName,
            action: nil,
            quiz: nil,
            reading: nil,
            reflection: nil,
            breathing: nil,
            soundCollectionID: recommendation.collectionID,
            callToAction: "Start sound"
        )
    }

    private static func assessmentPromptCard(sortOrder: Int, context: ForYouContext) -> ForYouCard {
        if let latest = context.latestAssessment {
            let assessmentName = latest.assessmentID.displayAssessmentName
            let result = latest.overall.map { " Result: \($0.band.label)." } ?? ""
            return ForYouCard(
                id: "assessment-recent-\(latest.assessmentID)",
                sortOrder: sortOrder,
                kind: .assessment,
                theme: .aurora,
                eyebrow: "Assessment",
                title: "Latest: \(assessmentName)",
                summary: "\(assessmentName) was your last self-check.\(result) Browse the library to sample a different signal next.",
                durationLabel: "2-5 min",
                symbolName: "checklist",
                action: nil,
                quiz: nil,
                reading: nil,
                reflection: nil,
                breathing: nil,
                assessmentID: latest.assessmentID,
                callToAction: "Browse assessments"
            )
        }

        return ForYouCard(
            id: "assessment-starter",
            sortOrder: sortOrder,
            kind: .assessment,
            theme: .coral,
            eyebrow: "Structured signal",
            title: "Take one self-check",
            summary: "A short assessment gives Eir a clearer signal than a freeform note alone.",
            durationLabel: "2-5 min",
            symbolName: "checklist",
            action: nil,
            quiz: nil,
            reading: nil,
            reflection: nil,
            breathing: nil,
            assessmentID: nil,
            callToAction: "Choose assessment"
        )
    }

    private static func patternRecallCard(sortOrder: Int, context: ForYouContext) -> ForYouCard {
        ForYouCard(
            id: "trainer-pattern-recall-\(context.dayPart.rawValue)",
            sortOrder: sortOrder,
            kind: .trainer,
            theme: .tide,
            eyebrow: "Brain training",
            title: "Pattern Recall",
            summary: "A short spatial memory round for the part of the day where focus work tends to fit.",
            durationLabel: "4-8 min",
            symbolName: "square.grid.3x3.fill",
            action: nil,
            quiz: nil,
            reading: nil,
            reflection: nil,
            breathing: nil,
            trainerID: "spatial-working-memory",
            callToAction: "Start trainer"
        )
    }

    private static func actionCard(
        _ action: HealthAction,
        sortOrder: Int,
        theme: ForYouCardTheme,
        eyebrow: String
    ) -> ForYouCard {
        ForYouCard(
            id: "action-\(action.id)",
            sortOrder: sortOrder,
            kind: .action,
            theme: theme,
            eyebrow: eyebrow,
            title: action.title,
            summary: action.summary,
            durationLabel: action.durationLabel,
            symbolName: action.category.systemImage,
            action: action,
            quiz: nil,
            reading: nil,
            reflection: nil,
            breathing: nil
        )
    }

    private static func buildContext(
        from document: EirDocument?,
        assessmentRecords: [AssessmentRecord],
        stateRecords: [StateCheckInRecord],
        now: Date
    ) -> ForYouContext {
        let hour = Calendar.current.component(.hour, from: now)
        let latestAssessment = assessmentRecords.sorted { $0.completedAt > $1.completedAt }.first
        let latestStateRecord = stateRecords.sorted { $0.createdAt > $1.createdAt }.first
        let hoursSinceLatestState = latestStateRecord.map {
            max(0, now.timeIntervalSince($0.createdAt) / 3600)
        } ?? Double.greatestFiniteMagnitude

        guard let document else {
            return ForYouContext(
                hasRecords: false,
                hasStressSignals: false,
                hasAppointments: false,
                latestAssessment: latestAssessment,
                latestStateRecord: latestStateRecord,
                hoursSinceLatestState: hoursSinceLatestState,
                dayPart: DayPart(hour: hour)
            )
        }

        let text = document.entries
            .prefix(20)
            .map {
                [
                    $0.category,
                    $0.type,
                    $0.content?.summary,
                    $0.content?.details,
                    $0.content?.notes?.joined(separator: " ")
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            .joined(separator: "\n")
            .lowercased()

        return ForYouContext(
            hasRecords: true,
            hasStressSignals: containsAny(in: text, keywords: ["stress", "oro", "ångest", "hjärtklappning", "utmatt"]),
            hasAppointments: containsAny(in: text, keywords: ["besök", "remiss", "uppfölj", "mottagning", "provtagning"]),
            latestAssessment: latestAssessment,
            latestStateRecord: latestStateRecord,
            hoursSinceLatestState: hoursSinceLatestState,
            dayPart: DayPart(hour: hour)
        )
    }

    private static func containsAny(in text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private struct ForYouContext {
        let hasRecords: Bool
        let hasStressSignals: Bool
        let hasAppointments: Bool
        let latestAssessment: AssessmentRecord?
        let latestStateRecord: StateCheckInRecord?
        let hoursSinceLatestState: Double
        let dayPart: DayPart

        var hasFreshState: Bool {
            latestStateRecord != nil && hoursSinceLatestState < 6
        }

        var shouldSuggestSocial: Bool {
            dayPart == .afternoon || dayPart == .evening || hasStressSignals
        }

        var soundRecommendation: SoundRecommendation {
            switch dayPart {
            case .morning:
                return SoundRecommendation(
                    collectionID: "colored-noise",
                    title: "Set a steady sound backdrop",
                    summary: "Start with colored noise to make the room feel less jagged before the first real task.",
                    durationLabel: "5-20 min",
                    symbolName: "speaker.wave.3.fill",
                    theme: .coral
                )
            case .midday:
                return SoundRecommendation(
                    collectionID: "isochronic-tones",
                    title: "Use a focus pulse",
                    summary: "A short isochronic tone session can mark the beginning of a focused work block.",
                    durationLabel: "5-20 min",
                    symbolName: "dot.radiowaves.left.and.right",
                    theme: .tide
                )
            case .afternoon:
                return SoundRecommendation(
                    collectionID: hasStressSignals ? "colored-noise" : "isochronic-tones",
                    title: hasStressSignals ? "Soften the room for a reset" : "Give attention a clear start",
                    summary: hasStressSignals
                        ? "Colored noise can reduce sharp sensory edges while you downshift."
                        : "A pulse-based sound session can help you begin the next block deliberately.",
                    durationLabel: "5-20 min",
                    symbolName: hasStressSignals ? "speaker.wave.3.fill" : "dot.radiowaves.left.and.right",
                    theme: hasStressSignals ? .coral : .tide
                )
            case .evening:
                return SoundRecommendation(
                    collectionID: "binaural-beats",
                    title: "Wind down with sound",
                    summary: "Open a slower sound session when silence feels too abrupt at the end of the day.",
                    durationLabel: "5-30 min",
                    symbolName: "waveform.path.ecg",
                    theme: .aurora
                )
            }
        }
    }

    private struct SoundRecommendation {
        let collectionID: String
        let title: String
        let summary: String
        let durationLabel: String
        let symbolName: String
        let theme: ForYouCardTheme
    }

    private static func currentStateDescriptor(for record: StateCheckInRecord) -> (title: String, theme: ForYouCardTheme) {
        let positiveIDs = ["physical_energy", "mental_energy", "mood", "motivation", "body_comfort"]
        let positiveAverage = positiveIDs
            .map { record.scores[$0] ?? 0.5 }
            .reduce(0, +) / Double(positiveIDs.count)
        let stressEase = 1 - (record.scores["stress_load"] ?? 0.5)
        let score = (positiveAverage + stressEase) / 2

        switch score {
        case ..<0.33:
            return ("Strained", .coral)
        case ..<0.55:
            return ("Mixed", .ember)
        case ..<0.75:
            return ("Steady", .meadow)
        default:
            return ("Open", .tide)
        }
    }

    private static func relativeAgeLabel(hours: Double) -> String {
        if hours < 1 {
            let minutes = max(1, Int((hours * 60).rounded()))
            return "\(minutes)m"
        }
        let rounded = Int(hours.rounded())
        return "\(rounded)h"
    }

    private enum DayPart: String {
        case morning
        case midday
        case afternoon
        case evening

        init(hour: Int) {
            switch hour {
            case 5..<11:
                self = .morning
            case 11..<15:
                self = .midday
            case 15..<19:
                self = .afternoon
            default:
                self = .evening
            }
        }

        var checkInEyebrow: String {
            switch self {
            case .morning: return "Start here"
            case .midday: return "Midday check"
            case .afternoon: return "Quick signal"
            case .evening: return "Evening check"
            }
        }

        var checkInSummary: String {
            switch self {
            case .morning:
                return "Capture one honest state snapshot before the day gets noisy."
            case .midday:
                return "A quick state check can help Eir choose a better next action."
            case .afternoon:
                return "Notice what your body is asking for before the next block."
            case .evening:
                return "Close the loop with a short note on how the day landed."
            }
        }
    }
}

private extension String {
    var displayAssessmentName: String {
        split(separator: "-")
            .map { word in
                word.prefix(1).uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }
}
