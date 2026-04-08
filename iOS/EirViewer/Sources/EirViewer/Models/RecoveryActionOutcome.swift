import Foundation

struct RecoveryActionOutcome: Identifiable, Codable, Hashable {
    let id: UUID
    let actionID: String
    let date: Date
    var completed: Bool
    var helpfulnessRating: Int?
    var followUpStressRating: Int?
    var notes: String?

    init(
        id: UUID = UUID(),
        actionID: String,
        date: Date = Date(),
        completed: Bool,
        helpfulnessRating: Int? = nil,
        followUpStressRating: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.actionID = actionID
        self.date = date
        self.completed = completed
        self.helpfulnessRating = helpfulnessRating.map { min(max($0, 1), 5) }
        self.followUpStressRating = followUpStressRating.map { min(max($0, 1), 5) }
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
