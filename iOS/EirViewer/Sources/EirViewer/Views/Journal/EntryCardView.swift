import SwiftUI

struct EntryCardView: View {
    let entry: EirEntry
    let isSelected: Bool

    var body: some View {
        let accent = AppColors.categoryColor(for: entry.category ?? "Övrigt")

        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        CategoryBadge(category: entry.category ?? "Övrigt")

                        if let summary = entry.content?.summary {
                            Text(summary)
                                .font(.body.weight(.semibold))
                                .foregroundColor(AppColors.text)
                                .lineLimit(3)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        if let time = entry.time {
                            Text(time)
                                .font(.caption.weight(.semibold))
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

                if let type = entry.type, !type.isEmpty {
                    Text(type)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    if let provider = entry.provider?.name {
                        metaPill(text: provider, systemImage: "building.2")
                    }

                    if let person = entry.responsiblePerson?.name {
                        metaPill(text: person, systemImage: "person")
                    }
                }
            }
            .padding(16)
        }
        .background(isSelected ? AppColors.primarySoft : AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? AppColors.primary.opacity(0.28) : AppColors.border, lineWidth: 1)
        )
        .shadow(color: AppColors.shadow, radius: 8, y: 4)
    }

    private func metaPill(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundColor(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppColors.backgroundMuted)
            .clipShape(Capsule())
    }
}
