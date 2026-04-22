package com.eir.viewer.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.eir.viewer.android.data.model.HealthAction
import com.eir.viewer.android.data.model.HealthActionState
import com.eir.viewer.android.data.model.EirDocument
import com.eir.viewer.android.data.model.StoredProfile
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
fun ForYouScreen(
    profile: StoredProfile?,
    document: EirDocument?,
    actions: List<HealthAction>,
    actionStates: Map<String, HealthActionState>,
    onTogglePinned: (HealthAction) -> Unit,
    onToggleCompleted: (HealthAction) -> Unit,
) {
    val today = remember { LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE) }
    val entryCount = document?.entries?.size ?: 0
    val providers = document?.entries?.mapNotNull { it.provider?.name }?.distinct() ?: emptyList()
    val totalCompletedToday = remember(actions, actionStates, today) {
        actions.count { isCompletedToday(actionStates[it.id], today) }
    }
    val totalPinned = remember(actions, actionStates) {
        actions.count { isPinned(actionStates[it.id]) }
    }
    val hasRecords = document != null && entryCount > 0
    val latestEntry = document
        ?.entries
        ?.sortedByDescending { it.parsedDate }
        ?.firstOrNull()

    val topCategory = remember(document) {
        document?.entries
            ?.mapNotNull { it.category?.trim()?.lowercase() }
            ?.filter { it.isNotEmpty() }
            ?.groupingBy { it }
            ?.eachCount()
            ?.maxByOrNull { it.value }
            ?.key
            ?.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
            ?: "Not yet detected"
    }

    val prioritizedActions = remember(actions, actionStates, today) {
        actions.sortedWith(
            compareByDescending<HealthAction> { isPinned(actionStates[it.id]) }
                .thenBy { if (isCompletedToday(actionStates[it.id], today)) 0 else 1 }
                .thenBy { it.source.name.lowercase() },
        ).take(4)
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            SummaryCard(
                title = "Profile",
                lines = listOfNotNull(
                    profile?.displayName?.takeIf { it.isNotBlank() } ?: "No profile selected",
                    profile?.birthDate?.let { "Birth date: $it" },
                    profile?.personalNumber?.let { "Personal number: $it" },
                ),
            )
        }

        item {
            SummaryCard(
                title = "Record Snapshot",
                lines = listOf(
                    if (hasRecords) "Entries: $entryCount" else "No records loaded yet",
                    "Providers: ${providers.size}",
                    "Most common category: $topCategory",
                    latestEntry?.content?.summary?.take(120)?.let { "Latest entry: $it" } ?: "Latest entry: none",
                ),
            )
        }

        item {
            SummaryCard(
                title = "Action Loop",
                lines = listOf(
                    "Suggested actions: ${actions.size}",
                    "Completed today: $totalCompletedToday/${actions.size}",
                    "Pinned actions: $totalPinned",
                    if (hasRecords) "Loop source: from record context" else "Loop source: starter recommendations",
                ),
            )
        }

        if (prioritizedActions.isEmpty()) {
            item {
                SummaryCard(
                    title = "Action recommendations",
                    lines = listOf(
                        "No actions available yet.",
                        "Try loading an .eir file or sample data from the menu.",
                    ),
                )
            }
        } else {
            item {
                Text(
                    text = "Action recommendations",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            items(prioritizedActions) { action ->
                val state = actionStates[action.id] ?: HealthActionState()
                val completed = isCompletedToday(state, today)
                val pinned = isPinned(state)

                Card(
                    modifier = Modifier.fillMaxWidth(),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                ) {
                    Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = action.title,
                                style = MaterialTheme.typography.titleMedium,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                text = action.durationLabel,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        Text(
                            text = action.summary,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        enabled = false,
                        selected = true,
                        onClick = { },
                        label = { Text(action.category.name.lowercase().replaceFirstChar { ch -> if (ch.isLowerCase()) ch.titlecase() else ch.toString() }) },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Outlined.Schedule,
                                contentDescription = "Category",
                                modifier = Modifier.size(16.dp),
                            )
                        },
                    )
                    FilterChip(
                        selected = pinned,
                        onClick = { onTogglePinned(action) },
                        label = { Text(if (pinned) "Pinned" else "Pin") },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Outlined.Flag,
                                contentDescription = if (pinned) "Pinned" else "Pin",
                                modifier = Modifier.size(16.dp),
                            )
                        },
                    )
                }

                OutlinedButton(onClick = { onToggleCompleted(action) }) {
                    Icon(
                        imageVector = Icons.Outlined.CheckCircle,
                        contentDescription = if (completed) "Completed" else "Mark completed",
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(if (completed) "Done today" else "Mark done")
                }
            }
        }
            }

            item {
                Text(
                    text = "Tip: complete one action and return here to keep momentum.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SummaryCard(
    title: String,
    lines: List<String>,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.5.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            lines.forEach { line ->
                Text(
                    text = line,
                    modifier = Modifier.padding(top = 10.dp),
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        }
    }
}

private fun isCompletedToday(
    state: HealthActionState?,
    today: String,
): Boolean = state?.completionDayStamps?.contains(today) == true

private fun isPinned(state: HealthActionState?): Boolean = state?.isPinned == true
