import SwiftUI

struct CategoryBadge: View {
    let category: String

    var body: some View {
        let accent = AppColors.categoryColor(for: category)

        Text(category)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColors.tagBackground(for: accent))
            .foregroundColor(accent)
            .clipShape(Capsule())
    }
}
