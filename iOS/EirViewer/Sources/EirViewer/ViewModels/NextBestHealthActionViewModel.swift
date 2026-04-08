import Foundation

@MainActor
final class NextBestHealthActionViewModel: ObservableObject {
    @Published private(set) var recentOutcomes: [RecoveryActionOutcome] = []

    private var currentProfileID: UUID?

    func sync(profileID: UUID?) {
        currentProfileID = profileID
        recentOutcomes = loadOutcomes(for: profileID)
    }

    func saveOutcome(_ outcome: RecoveryActionOutcome, document: EirDocument?, actions: [HealthAction]) async {
        let profileID = currentProfileID
        if recentOutcomes.isEmpty && currentProfileID == nil {
            sync(profileID: profileID)
        }

        var next = recentOutcomes.filter {
            !Calendar.current.isDate($0.date, inSameDayAs: outcome.date) || $0.actionID != outcome.actionID
        }
        next.append(outcome)
        next.sort { $0.date > $1.date }
        recentOutcomes = Array(next.prefix(120))
        saveOutcomes(recentOutcomes, for: profileID)
    }

    private func loadOutcomes(for profileID: UUID?) -> [RecoveryActionOutcome] {
        EncryptedStore.load([RecoveryActionOutcome].self, forKey: storageKey(for: profileID)) ?? []
    }

    private func saveOutcomes(_ outcomes: [RecoveryActionOutcome], for profileID: UUID?) {
        EncryptedStore.save(outcomes, forKey: storageKey(for: profileID))
    }

    private func storageKey(for profileID: UUID?) -> String {
        "eir_next_action_outcomes_\(profileID?.uuidString ?? "global")"
    }
}
