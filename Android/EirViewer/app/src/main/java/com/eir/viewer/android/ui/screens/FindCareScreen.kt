@file:OptIn(ExperimentalLayoutApi::class)
package com.eir.viewer.android.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.FindInPage
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.outlined.Navigation
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.eir.viewer.android.data.model.FindCareClinicMatch
import com.eir.viewer.android.data.model.FindCareIssueAnalysis
import com.eir.viewer.android.data.model.FindCareSuggestedType
import com.eir.viewer.android.data.model.title
import kotlin.math.max
import kotlin.math.roundToInt
import java.util.Locale

@Composable
fun FindCareScreen(
    query: String,
    issueText: String,
    issueAnalysis: FindCareIssueAnalysis?,
    selectedTypes: Set<FindCareSuggestedType>,
    results: List<FindCareClinicMatch>,
    isLoading: Boolean,
    error: String?,
    isAnalyzing: Boolean,
    onQueryChange: (String) -> Unit,
    onIssueTextChange: (String) -> Unit,
    onAnalyzeIssue: () -> Unit,
    onToggleType: (FindCareSuggestedType) -> Unit,
    onRunSearch: () -> Unit,
    isLocating: Boolean,
    hasLocation: Boolean,
    onUseMyLocation: () -> Unit,
    onClearLocation: () -> Unit,
) {
    val context = LocalContext.current
    val clipboardManager = LocalClipboardManager.current
    val copyToClipboard: (String) -> Unit = { text ->
        clipboardManager.setText(AnnotatedString(text))
    }
    var selectedMatch by remember { mutableStateOf<FindCareClinicMatch?>(null) }

    val hasScope = query.isNotBlank() || hasLocation || selectedTypes.isNotEmpty() || issueAnalysis != null
    val locationStatusText = when {
        isLocating -> "Locating your position..."
        hasLocation -> "Nearby results are ranked by distance."
        else -> "Search by clinic/city/county or tap Near me."
    }
    val topMatch = if (issueAnalysis != null) results.firstOrNull() else null
    val listedResults = if (topMatch != null) results.drop(1) else results

    val openUrl: (String?) -> Unit = { url ->
        val safeUrl = url?.trim()?.ifBlank { null }
        if (safeUrl != null) {
            val normalizedUrl = safeUrl.takeIf { it.startsWith("http") } ?: "https://$safeUrl"
            val uri = Uri.parse(normalizedUrl)
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
        }
    }

    val callPhone: (String?) -> Unit = { number ->
        val normalized = number?.trim()
        if (normalized != null) {
            val clean = normalized.filter { it.isDigit() || it == '+' }
            if (clean.any { it.isDigit() }) {
                val uri = Uri.parse("tel:$clean")
                val intent = Intent(Intent.ACTION_DIAL, uri)
                runCatching { context.startActivity(intent) }
            }
        }
    }

    val shareText: (String, String) -> Unit = { text, label ->
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, label)
            putExtra(Intent.EXTRA_TEXT, text)
        }
        runCatching {
            context.startActivity(Intent.createChooser(shareIntent, "Share draft"))
        }
    }

    val openMap: (FindCareClinicMatch) -> Unit = { match ->
        val latitude = match.clinic.location.lat
        val longitude = match.clinic.location.lng
        if (latitude != null && longitude != null) {
            val geoIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encode(match.clinic.name)})"),
            )
            runCatching { context.startActivity(geoIntent) }.onFailure {
                val fallbackIntent = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://www.google.com/maps/search/?api=1&query=$latitude,$longitude"),
                )
                runCatching { context.startActivity(fallbackIntent) }
            }
        } else {
            val fallbackQuery = match.clinic.displayLocationLine
            if (fallbackQuery.isNotBlank()) {
                val fallbackIntent = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encode(fallbackQuery)}"),
                )
                runCatching { context.startActivity(fallbackIntent) }
            }
        }
    }

    val openDirections: (FindCareClinicMatch) -> Unit = { match ->
        val latitude = match.clinic.location.lat
        val longitude = match.clinic.location.lng
        if (latitude != null && longitude != null) {
            val navIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("google.navigation:q=$latitude,$longitude"),
            )
            runCatching { context.startActivity(navIntent) }.onFailure {
                openMap(match)
            }
        } else {
            openMap(match)
        }
    }

    val heroBrush = listOf(
        MaterialTheme.colorScheme.primary.copy(alpha = 0.11f),
        MaterialTheme.colorScheme.background,
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(colors = heroBrush))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface,
            ),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(text = "Find care", style = MaterialTheme.typography.headlineSmall)
                Text(
                    text = "Describe your concern and quickly move into verified clinic contact paths.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )

                OutlinedTextField(
                    value = issueText,
                    onValueChange = onIssueTextChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 6.dp),
                    placeholder = { Text("Describe what you need help with") },
                    label = { Text("Issue description") },
                    singleLine = false,
                    trailingIcon = {
                        TextButton(onClick = onAnalyzeIssue, enabled = issueText.isNotBlank() && !isAnalyzing) {
                            if (isAnalyzing) {
                                CircularProgressIndicator(modifier = Modifier, strokeWidth = 2.dp)
                            } else {
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null)
                                    Text("Analyze")
                                }
                            }
                        }
                    },
                )

                issueAnalysis?.let { analysis ->
                    IssueSummaryCard(
                        issueSummary = analysis.suggestionSummary,
                        selectedTypes = selectedTypes,
                        specialtyKeywords = analysis.specialtyKeywords,
                        recommendedQuestion = analysis.recommendedQuestion,
                        onToggleType = onToggleType,
                    )
                }
            }
        }

        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface,
            ),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        ) {
            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(text = "Search", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Clinic, city, county, or symptom keyword") },
                    label = { Text("Search clinics") },
                    trailingIcon = {
                        Button(onClick = onRunSearch) {
                            Text("Search")
                        }
                    },
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = locationStatusText,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedButton(onClick = onUseMyLocation, enabled = !isLocating) {
                        Icon(Icons.Outlined.Place, contentDescription = null)
                        Text("Use my location")
                    }
                    if (hasLocation) {
                        TextButton(onClick = onClearLocation) {
                            Text("Clear")
                        }
                    }
                }

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FindCareSuggestedType.values().forEach { type ->
                        FilterChip(
                            selected = selectedTypes.contains(type),
                            onClick = { onToggleType(type) },
                            label = { Text(type.title) },
                        )
                    }
                    if (selectedTypes.isNotEmpty()) {
                        FilterChip(
                            selected = false,
                            onClick = { selectedTypes.forEach(onToggleType) },
                            label = { Text("Clear filters") },
                        )
                    }
                }

                if (error != null) {
                    Text(text = error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }

                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                } else {
                    when {
                        !hasScope -> {
                            ScopeStateCard(
                                title = "Narrow the search first",
                                body = "Use your location, add a municipality/county or clinic keyword, and include issue-based filters to get ranked verified results.",
                            )
                        }
                        results.isEmpty() -> {
                            ScopeStateCard(
                                title = if (hasLocation) {
                                    "No clinics matched this search"
                                } else {
                                    "No verified clinics matched yet"
                                },
                                body = if (hasLocation) {
                                    "Try broader terms, a different county, or different care types."
                                } else {
                                    "Try location search, broader terms, or run issue analysis again."
                                },
                            )
                        }
                        else -> {
                            if (topMatch != null) {
                                TopMatchCard(match = topMatch) { selectedMatch = topMatch }
                            }

                            LazyColumn(
                                modifier = Modifier.weight(1f),
                                contentPadding = PaddingValues(bottom = 12.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                items(listedResults, key = { it.id }) { result ->
                                    FindCareResultCard(
                                        match = result,
                                        onOpenDetails = { selectedMatch = result },
                                        onOpenMap = { openMap(result) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    selectedMatch?.let { match ->
        FindCareClinicDetailDialog(
            match = match,
            issueAnalysis = issueAnalysis,
            onDismiss = { selectedMatch = null },
            onOpenProfile = { openUrl(match.clinic.links.profile1177) },
            onOpenSelfReferral = {
                issueAnalysis
                    ?.selfReferralDraft
                    ?.takeIf { it.isNotBlank() }
                    ?.let(copyToClipboard)
                openUrl(match.clinic.selfReferralEvidenceUrl)
            },
            onCopySelfReferral = copyToClipboard,
            onShareSelfReferral = { draft ->
                shareText(draft, "AI draft for egen vårdbegäran")
            },
            onOpenBooking = { openUrl(match.clinic.links.website) },
            onCall = { callPhone(match.clinic.contact.phone) },
            onOpenMap = { openMap(match) },
            onOpenDirections = { openDirections(match) },
        )
    }
}

@Composable
private fun IssueSummaryCard(
    issueSummary: String,
    selectedTypes: Set<FindCareSuggestedType>,
    specialtyKeywords: Set<String>,
    recommendedQuestion: String,
    onToggleType: (FindCareSuggestedType) -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text = "Analysis", style = MaterialTheme.typography.labelLarge)
            Text(text = issueSummary, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)

            if (recommendedQuestion.isNotBlank()) {
                Text(
                    text = "Question to bring: $recommendedQuestion",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            if (specialtyKeywords.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    specialtyKeywords.forEach { keyword ->
                        FilterChip(
                            selected = false,
                            onClick = {},
                            label = { Text(keyword) },
                        )
                    }
                }
            }

            if (selectedTypes.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    selectedTypes.forEach { type ->
                        FilterChip(selected = true, onClick = { onToggleType(type) }, label = { Text(type.title) })
                    }
                }
            }
        }
    }
}

@Composable
private fun ScopeStateCard(title: String, body: String) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(text = title, style = MaterialTheme.typography.labelLarge)
            Text(text = body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun FindCareResultCard(
    match: FindCareClinicMatch,
    onOpenDetails: () -> Unit,
    onOpenMap: () -> Unit,
) {
    val selfReferralLabel = match.clinic.firstActionLabel
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenDetails),
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.LocalHospital, contentDescription = null)
                Text(
                    text = match.clinic.name,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                match.distanceKm?.let { distance ->
                    Text(text = formatDistance(distance), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            Text(text = match.clinic.displayTypeLabel, style = MaterialTheme.typography.labelLarge)
            Text(text = match.clinic.displayLocationLine, color = MaterialTheme.colorScheme.onSurfaceVariant)

            if (match.clinic.summary.isNotBlank()) {
                Text(
                    text = match.clinic.summary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }

            val extras = buildList {
                if (match.clinic.access.has1177EServices) add("Self-referral")
                if (match.clinic.hasBookingAction) add("Booking")
                if (match.clinic.access.videoConsultation) add("Video")
                if (match.clinic.hasSelfReferral && selfReferralLabel != null) {
                    add(selfReferralLabel)
                }
            }
            if (extras.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    extras.forEach { label ->
                        FilterChip(
                            selected = false,
                            onClick = {},
                            label = { Text(label) },
                        )
                    }
                }
            }

            HorizontalDivider()
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onOpenDetails) {
                    Icon(Icons.Outlined.FindInPage, contentDescription = null)
                    Text("Open details")
                }
                val hasMapAction = (match.clinic.location.lat != null && match.clinic.location.lng != null) ||
                    !match.clinic.location.address.isNullOrBlank() ||
                    !match.clinic.location.municipality.isNullOrBlank() ||
                    !match.clinic.location.county.isNullOrBlank()
                if (hasMapAction) {
                    TextButton(onClick = onOpenMap) {
                        Icon(Icons.Outlined.Place, contentDescription = null)
                        Text("Open map")
                    }
                }
            }
        }
    }
}

@Composable
private fun TopMatchCard(
    match: FindCareClinicMatch,
    onOpenDetails: () -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = "Best match right now",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = match.clinic.name,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = match.clinic.displayLocationLine,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (match.clinic.summary.isNotBlank()) {
                Text(
                    text = match.clinic.summary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            ElevatedActionButton(
                icon = Icons.Outlined.FindInPage,
                text = "Open best match now",
                onClick = onOpenDetails,
            )
        }
    }
}

@Composable
private fun FindCareClinicDetailDialog(
    match: FindCareClinicMatch,
    issueAnalysis: FindCareIssueAnalysis?,
    onDismiss: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenSelfReferral: () -> Unit,
    onCopySelfReferral: (String) -> Unit,
    onShareSelfReferral: (String) -> Unit,
    onOpenBooking: () -> Unit,
    onCall: () -> Unit,
    onOpenMap: () -> Unit,
    onOpenDirections: () -> Unit,
) {
    var copiedDraft by remember { mutableStateOf(false) }
    var copiedQuestion by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(text = match.clinic.name, style = MaterialTheme.typography.titleLarge)
                Text(text = match.clinic.displayLocationLine, style = MaterialTheme.typography.bodySmall)
            }
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (match.clinic.contact.phone != null) {
                    InfoPill(
                        icon = Icons.Outlined.Call,
                        text = match.clinic.contact.phone,
                    )
                }

                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOfNotNull(
                        "Type: ${match.clinic.displayTypeLabel}",
                        match.distanceKm?.let { formatDistance(it) }?.let { "Distance: $it" },
                    ).forEach { value ->
                        FilterChip(
                            selected = false,
                            onClick = {},
                            label = { Text(value) },
                        )
                    }
                }

                InfoSection(
                    title = "Why this clinic is included",
                    body = if (match.clinic.selfReferral.evidence.isEmpty()) {
                        "This clinic has verified 1177 self-referral support."
                    } else {
                        match.clinic.selfReferral.evidence
                            .take(3)
                            .joinToString("\n\n") { evidence ->
                                if (evidence.excerpt.isNullOrBlank()) {
                                    evidence.text
                                } else {
                                    "${evidence.text}\n${evidence.excerpt}"
                                }
                            }
                    },
                )

                if (!match.clinic.summary.isBlank()) {
                    InfoSection(title = "About this clinic", body = match.clinic.summary)
                }

                if (!match.clinic.firstActionLabel.isNullOrBlank()) {
                    InfoSection(
                        title = "Next step",
                        body = "${match.clinic.firstActionLabel}: use this clinic's self-referral or booking flow as the first contact point.",
                    )
                }

                if (issueAnalysis?.recommendedQuestion?.isNotBlank() == true) {
                    ActionBlock(title = "Question to bring") {
                        Text(
                            text = issueAnalysis.recommendedQuestion,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        if (copiedQuestion) {
                            Text(text = "Copied question", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        }
                        TextButton(
                            onClick = {
                                onCopySelfReferral(issueAnalysis.recommendedQuestion)
                                copiedQuestion = true
                            },
                        ) {
                            Icon(Icons.Outlined.ContentCopy, contentDescription = null)
                            Text("Copy question")
                        }
                    }
                }

                if (issueAnalysis?.selfReferralDraft?.isNotBlank() == true) {
                    ActionBlock(title = "AI draft for egen vårdbegäran") {
                        Text(
                            text = issueAnalysis.selfReferralDraft,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        if (copiedDraft) {
                            Text(text = "Copied draft", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(
                                onClick = {
                                    onCopySelfReferral(issueAnalysis.selfReferralDraft)
                                    copiedDraft = true
                                },
                            ) {
                                Icon(Icons.Outlined.ContentCopy, contentDescription = null)
                                Text("Copy draft")
                            }
                            TextButton(
                                onClick = {
                                    onShareSelfReferral(issueAnalysis.selfReferralDraft)
                                },
                            ) {
                                Text("Share draft")
                            }
                        }
                    }
                }
                FlowBlock(
                    stepOne = "Open the clinic on 1177 and confirm this is right for your care path.",
                    stepTwo = match.clinic.firstActionLabel?.takeIf { it.isNotBlank() }
                        ?: "Start the clinic's verified self-referral flow.",
                    stepThree = "Paste your drafted text in the 1177 self-referral form and use it as a starting point.",
                )

                ActionSection(
                    title = "Clinic actions",
                    onPrimary = onOpenProfile,
                    onSelfReferral = onOpenSelfReferral,
                    onWebsite = onOpenBooking,
                    onCall = onCall,
                    onMap = onOpenMap,
                    onDirections = onOpenDirections,
                    hasSelfReferral = match.clinic.selfReferralEvidenceUrl != null,
                    hasBooking = match.clinic.links.website != null,
                    hasDirections = match.clinic.location.lat != null && match.clinic.location.lng != null,
                )
            }
        },
        confirmButton = {
            Button(onClick = onDismiss) {
                Text("Done")
            }
        },
    )
}

@Composable
private fun FlowBlock(
    stepOne: String,
    stepTwo: String,
    stepThree: String,
) {
    ActionBlock(title = "Egenremiss flow") {
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(text = stepOne, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(text = stepTwo, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(text = stepThree, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ActionBlock(
    title: String,
    content: @Composable () -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(text = title, style = MaterialTheme.typography.titleSmall)
            content()
        }
    }
}

@Composable
private fun ActionSection(
    title: String,
    onPrimary: () -> Unit,
    onSelfReferral: () -> Unit,
    onWebsite: () -> Unit,
    onCall: () -> Unit,
    onMap: () -> Unit,
    onDirections: () -> Unit,
    hasSelfReferral: Boolean,
    hasBooking: Boolean,
    hasDirections: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = title, style = MaterialTheme.typography.titleSmall)
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ElevatedActionButton(
                icon = Icons.Outlined.FindInPage,
                text = "Open 1177",
                onClick = onPrimary,
            )
            if (hasSelfReferral) {
                ElevatedActionButton(
                    icon = Icons.AutoMirrored.Filled.Send,
                    text = "Self-referral",
                    onClick = onSelfReferral,
                )
            }
            if (hasBooking) {
                ElevatedActionButton(
                    icon = Icons.Outlined.Navigation,
                    text = "Website",
                    onClick = onWebsite,
                )
            }
            ElevatedActionButton(
                icon = Icons.Outlined.Call,
                text = "Call",
                onClick = onCall,
            )
            if (hasDirections) {
                ElevatedActionButton(
                    icon = Icons.Outlined.Place,
                    text = "Directions",
                    onClick = onDirections,
                )
            } else {
                ElevatedActionButton(
                    icon = Icons.Outlined.Place,
                    text = "Map",
                    onClick = onMap,
                )
            }
        }
    }
}

@Composable
private fun ElevatedActionButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    onClick: () -> Unit,
) {
    Button(onClick = onClick) {
        Icon(icon, contentDescription = null)
        Text(text)
    }
}

@Composable
private fun InfoSection(
    title: String,
    body: String,
) {
    ActionBlock(title = title) {
        Text(text = body, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun InfoPill(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null)
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

private fun formatDistance(distanceKm: Double): String {
    return if (distanceKm < 1.0) {
        val meters = max((distanceKm * 1000).roundToInt(), 0)
        "$meters m"
    } else {
        String.format(Locale.US, "%.1f km", distanceKm)
    }
}
