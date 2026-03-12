import SwiftUI

struct PersonRow: View {
    let profile: PersonProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? AnyShapeStyle(AppColors.aura) : AnyShapeStyle(AppColors.backgroundMuted))
                    .frame(width: 38, height: 38)

                Text(profile.initials)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? .white : AppColors.primaryDeep)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(AppColors.text)
                    .lineLimit(1)

                if let count = profile.totalEntries {
                    Text("\(count) entries")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(AppColors.primaryStrong)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? AppColors.primarySoft : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
