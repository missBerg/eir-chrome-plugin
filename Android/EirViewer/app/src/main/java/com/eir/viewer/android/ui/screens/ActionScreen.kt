package com.eir.viewer.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AssistChip
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Icon
import com.eir.viewer.android.data.model.HealthAction
import com.eir.viewer.android.data.model.HealthActionState
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
fun ActionScreen(
    actions: List<HealthAction>,
    actionStates: Map<String, HealthActionState>,
    onTogglePinned: (HealthAction) -> Unit,
    onToggleCompleted: (HealthAction) -> Unit,
) {
    var selectedFilter by rememberSaveable { mutableStateOf(ActionFilter.All) }
    var searchQuery by rememberSaveable { mutableStateOf("") }

    val completedToday = remember(actions, actionStates) {
        actions.count { isCompletedToday(actionStates[it.id]) }
    }
    val pinnedCount = actions.count { isPinned(actionStates[it.id]) }
    val completionRatio = if (actions.isEmpty()) 0f else completedToday.toFloat() / actions.size.toFloat()
    val visibleActions = remember(actions, actionStates, selectedFilter) {
        actions.filter { action ->
            when (selectedFilter) {
                ActionFilter.All -> true
                ActionFilter.Pinned -> isPinned(actionStates[action.id])
                ActionFilter.Pending -> !isCompletedToday(actionStates[action.id])
                ActionFilter.Completed -> isCompletedToday(actionStates[action.id])
            }
        }
    }

    val searchedActions = remember(actions, visibleActions, searchQuery) {
        val query = searchQuery.trim().lowercase()
        if (query.isBlank()) {
            visibleActions
        } else {
            visibleActions.filter { action ->
                action.title.lowercase().contains(query)
                    || action.summary.lowercase().contains(query)
                    || action.durationLabel.lowercase().contains(query)
            }
        }
    }

    val visibleCount = searchedActions.size

    val visibleAndPinned = remember(searchedActions, actionStates) {
        searchedActions.sortedWith(
            compareByDescending<HealthAction> { isPinned(actionStates[it.id]) }
                .thenBy { it.source.name.lowercase() },
        )
    }

    if (actions.isEmpty()) {
        EmptyActionState()
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        HeaderCard(
            completedCount = completedToday,
            plannedCount = pinnedCount,
            actions = actions,
            completionRatio = completionRatio,
        )

        OutlinedTextField(
            value = searchQuery,
            onValueChange = { query ->
                searchQuery = query
            },
            modifier = Modifier.fillMaxWidth(),
            leadingIcon = {
                Icon(
                    imageVector = Icons.Outlined.Search,
                    contentDescription = "Search actions",
                )
            },
            placeholder = { Text("Search actions") },
            label = { Text("Search") },
            singleLine = true,
        )

        ActionFilterRow(
            selectedFilter = selectedFilter,
            onSelectFilter = { selectedFilter = it },
            visibleCount = visibleCount,
            totalCount = actions.size,
        )

        if (searchedActions.isEmpty()) {
            Text(
                text = "No actions match these filters.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 10.dp),
            )
            return
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(visibleAndPinned, key = { it.id }) { action ->
                ActionCard(
                    action = action,
                    state = actionStates[action.id] ?: HealthActionState(),
                    onTogglePinned = { onTogglePinned(action) },
                    onToggleCompleted = { onToggleCompleted(action) },
                )
            }
        }
    }
}

@Composable
private fun HeaderCard(
    completedCount: Int,
    plannedCount: Int,
    actions: List<HealthAction>,
    completionRatio: Float,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Action plan",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                text = "Use these practical next steps to keep your health loop active.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp),
            )
            Text(
                text = "Done today: $completedCount • Actions: ${actions.size} • Pinned: $plannedCount",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 10.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(12.dp))
            LinearProgressIndicator(
                progress = { completionRatio },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun ActionCard(
    action: HealthAction,
    state: HealthActionState,
    onTogglePinned: () -> Unit,
    onToggleCompleted: () -> Unit,
) {
    val completed = isCompletedToday(state)
    val pinned = state.isPinned

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = action.title,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                AssistChip(
                    onClick = onTogglePinned,
                    label = { Text(if (pinned) "Pinned" else "Pin") },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Flag,
                            contentDescription = if (pinned) "Pinned" else "Pin",
                            modifier = Modifier.size(14.dp),
                        )
                    },
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    enabled = false,
                    selected = true,
                    onClick = {},
                    label = { Text(action.durationLabel) },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Schedule,
                            contentDescription = "Duration",
                            modifier = Modifier.size(16.dp),
                        )
                    },
                )
                FilterChip(
                    enabled = false,
                    selected = true,
                    onClick = {},
                    label = {
                        Text(action.source.name.lowercase().replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() })
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Checklist,
                            contentDescription = "Source",
                            modifier = Modifier.size(16.dp),
                        )
                    },
                )
            }

            Text(
                text = action.summary,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Text(
                text = "Why this: ${action.insight}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
            )

            if (action.steps.isNotEmpty()) {
                Text(
                    text = "Quick steps",
                    style = MaterialTheme.typography.labelLarge,
                )
                action.steps.forEachIndexed { index, step ->
                    Row(
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            text = "${index + 1}.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(text = step, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                TextButton(onClick = onToggleCompleted) {
                    Icon(
                        imageVector = Icons.Outlined.CheckCircle,
                        contentDescription = if (completed) "Completed" else "Mark complete",
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(if (completed) "Completed today" else "Mark done today")
                }
                if (action.benefits.isNotEmpty()) {
                    Text(
                        text = "Benefit: ${action.benefits.joinToString(", ")}",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun ActionFilterRow(
    selectedFilter: ActionFilter,
    onSelectFilter: (ActionFilter) -> Unit,
    visibleCount: Int,
    totalCount: Int,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionFilter.values().forEach { filter ->
                FilterChip(
                    selected = selectedFilter == filter,
                    onClick = { onSelectFilter(filter) },
                    label = { Text(filter.label) },
                )
            }
        }

        Text(
            text = "Showing $visibleCount of $totalCount actions",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private enum class ActionFilter(val label: String) {
    All("All"),
    Pinned("Pinned"),
    Pending("Open"),
    Completed("Done today"),
}

private fun isCompletedToday(state: HealthActionState?): Boolean {
    if (state == null) return false
    val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
    return state.completionDayStamps.contains(today)
}

private fun isPinned(state: HealthActionState?): Boolean = state?.isPinned == true

@Composable
private fun EmptyActionState() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
    ) {
        Card(elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "Action list will appear once records load.",
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    text = "Add a profile or load sample data and we will generate practical next steps.",
                    modifier = Modifier.padding(top = 10.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
