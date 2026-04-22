package com.eir.viewer.android.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val EirColorScheme = lightColorScheme(
    primary = Primary,
    onPrimary = SurfaceCard,
    primaryContainer = PrimarySoft,
    onPrimaryContainer = PrimaryStrong,
    secondary = Teal,
    onSecondary = TextPrimary,
    secondaryContainer = Teal.copy(alpha = 0.2f),
    onSecondaryContainer = TextPrimary,
    tertiary = Purple,
    onTertiary = SurfaceCard,
    tertiaryContainer = Purple.copy(alpha = 0.2f),
    onTertiaryContainer = TextPrimary,
    background = Background,
    onBackground = TextPrimary,
    surface = SurfaceCard,
    onSurface = TextPrimary,
    onSurfaceVariant = TextSecondary,
    surfaceVariant = SurfaceCard,
    outline = Border,
    outlineVariant = Divider,
    error = Red,
    onError = SurfaceCard,
)

private val EirShapes = Shapes(
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(20.dp),
)

private val EirTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 33.sp,
        lineHeight = 40.sp,
        letterSpacing = (-0.2).sp,
    ),
    displayMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        lineHeight = 34.sp,
    ),
    headlineSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 26.sp,
        lineHeight = 32.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 26.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 18.sp,
        lineHeight = 24.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.1.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 15.sp,
        lineHeight = 22.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 13.sp,
        lineHeight = 18.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 13.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.1.sp,
    ),
)

@Composable
fun EirTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = EirColorScheme,
        typography = EirTypography,
        shapes = EirShapes,
        content = content,
    )
}
