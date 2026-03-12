import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum AppColors {
    static let primary = Color(hex: "1E94A8")
    static let primaryStrong = Color(hex: "197A8E")
    static let primaryDeep = Color(hex: "1C5260")
    static let primaryLight = Color(hex: "D5EFF4")
    static let primarySoft = Color(hex: "F0FAFB")

    static let ai = Color(hex: "D4A76A")
    static let aiStrong = Color(hex: "96703E")
    static let aiSoft = Color(hex: "FFF9F0")

    static let info = Color(hex: "4A8DB4")
    static let infoSoft = Color(hex: "F0F7FB")

    static let success = Color(hex: "22C55E")
    static let successSoft = Color(hex: "F0FDF4")
    static let warning = Color(hex: "F59E0B")
    static let warningSoft = Color(hex: "FFFBEB")
    static let danger = Color(hex: "EF4444")
    static let dangerSoft = Color(hex: "FEF2F2")

    static let background = Color(hex: "FAFAF7")
    static let backgroundElevated = Color.white
    static let backgroundMuted = Color(hex: "F5F4F0")
    static let backgroundStrong = Color(hex: "E8E6E1")
    static let card = Color.white
    static let border = Color(hex: "E8E6E1")
    static let divider = Color(hex: "F5F4F0")
    static let shadow = Color.black.opacity(0.06)
    static let shadowStrong = Color.black.opacity(0.12)

    static let text = Color(hex: "3D3A36")
    static let textSecondary = Color(hex: "7A766F")
    static let textTertiary = Color(hex: "A8A49E")
    static let textOnBrand = Color.white

    static let green = success
    static let orange = warning
    static let red = danger
    static let blue = info
    static let teal = primary
    static let pink = ai
    static let yellow = warning
    static let purple = aiStrong

    static let auraStart = Color(hex: "D4A76A")
    static let auraMidWarm = Color(hex: "C9B88A")
    static let auraMidCool = Color(hex: "A8C5D4")
    static let auraEnd = Color(hex: "8BB8CE")

    static let aura = LinearGradient(
        colors: [auraStart, auraMidWarm, auraMidCool, auraEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let auraVertical = LinearGradient(
        colors: [auraStart, auraMidCool, auraEnd],
        startPoint: .top,
        endPoint: .bottom
    )

    static let auraSubtle = LinearGradient(
        colors: [
            auraStart.opacity(0.14),
            auraMidCool.opacity(0.08),
            auraEnd.opacity(0.12),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pageGlow = RadialGradient(
        colors: [
            auraStart.opacity(0.16),
            auraEnd.opacity(0.10),
            .clear,
        ],
        center: .topLeading,
        startRadius: 40,
        endRadius: 420
    )

    static func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case "lab", "labresultat":
            return info
        case "recept", "lakemedel", "läkemedel":
            return success
        case "diagnoser", "conditions":
            return ai
        case "allergier":
            return danger
        case "halsodata", "hälsodata", "vitaler", "vitals":
            return primary
        case "vaccinationer", "immunizations":
            return Color(hex: "8BC4E3")
        case "vardkontakter", "vårdkontakter", "remisser":
            return primaryStrong
        case "anteckningar":
            return aiStrong
        default:
            return textSecondary
        }
    }

    static func tagBackground(for color: Color) -> Color {
        color.opacity(0.12)
    }
}
