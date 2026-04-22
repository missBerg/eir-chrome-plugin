package com.eir.viewer.android.ui.theme

import androidx.compose.ui.graphics.Color

val Primary = Color(0xFF6366F1)
val PrimaryStrong = Color(0xFF4F46E5)
val PrimarySoft = Color(0xFFEEF2FF)

val Background = Color(0xFFFAFAF9)
val BackgroundMuted = Color(0xFFF5F5F4)
val SurfaceCard = Color(0xFFFFFFFF)
val Border = Color(0xFFE7E5E4)
val Divider = Color(0xFFF5F5F4)

val TextPrimary = Color(0xFF1C1917)
val TextSecondary = Color(0xFF78716C)

val Red = Color(0xFFEF4444)
val Green = Color(0xFF22C55E)
val Purple = Color(0xFFA855F7)
val Orange = Color(0xFFF97316)
val Blue = Color(0xFF3B82F6)
val Teal = Color(0xFF14B8A6)
val Pink = Color(0xFFEC4899)

fun categoryColor(category: String?): Color {
    return when (category?.lowercase()) {
        "vårdkontakter" -> Primary
        "anteckningar" -> Purple
        "diagnoser" -> Red
        "vaccinationer" -> Green
        "recept", "läkemedel" -> Orange
        "lab", "labresultat" -> Blue
        "remisser" -> Teal
        "hälsodata" -> Pink
        else -> TextSecondary
    }
}
