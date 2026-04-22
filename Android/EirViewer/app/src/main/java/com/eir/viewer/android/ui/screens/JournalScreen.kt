package com.eir.viewer.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.eir.viewer.android.data.model.EirDocument
import com.eir.viewer.android.data.model.EirEntry
import com.eir.viewer.android.ui.theme.Divider
import com.eir.viewer.android.ui.theme.TextSecondary
import com.eir.viewer.android.ui.theme.categoryColor

@Composable
fun JournalScreen(
    document: EirDocument?,
    searchText: String,
    selectedCategory: String?,
    selectedProvider: String?,
    onSearchChange: (String) -> Unit,
    onCategoryChange: (String?) -> Unit,
    onProviderChange: (String?) -> Unit,
    onClearFilters: () -> Unit,
    onOpenEntry: (String) -> Unit,
) {
    val entries = document?.entries.orEmpty()
    val filteredEntries = remember(entries, searchText, selectedCategory, selectedProvider) {
        entries.filter { entry ->
            val matchesSearch = searchText.isBlank() || listOfNotNull(
                entry.content?.summary,
                entry.content?.details,
                entry.category,
                entry.provider?.name,
                entry.type,
            ).any { it.contains(searchText, ignoreCase = true) } ||
                entry.content?.notes?.any { it.contains(searchText, ignoreCase = true) } == true

            val matchesCategory = selectedCategory == null || entry.category == selectedCategory
            val matchesProvider = selectedProvider == null || entry.provider?.name == selectedProvider
            matchesSearch && matchesCategory && matchesProvider
        }.sortedByDescending { it.parsedDate }
    }

    val groupedEntries = remember(filteredEntries) {
        filteredEntries.groupBy { it.dateGroupKey }.toList()
    }

    val categories = remember(entries) {
        entries.mapNotNull { it.category }.distinct().sorted()
    }
    val providers = remember(entries) {
        entries.mapNotNull { it.provider?.name }.distinct().sorted()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
    ) {
        Text(
            text = "Journal",
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(top = 16.dp, bottom = 10.dp),
        )
        OutlinedTextField(
            value = searchText,
            onValueChange = onSearchChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Search entries") },
            singleLine = true,
        )

        FilterRow(
            title = "Categories",
            values = categories,
            selectedValue = selectedCategory,
            onSelected = onCategoryChange,
        )

        FilterRow(
            title = "Providers",
            values = providers,
            selectedValue = selectedProvider,
            onSelected = onProviderChange,
        )

        if (selectedCategory != null || selectedProvider != null) {
            Text(
                text = "Clear filters",
                modifier = Modifier
                    .padding(top = 8.dp)
                    .clickable(onClick = onClearFilters),
                color = MaterialTheme.colorScheme.primary,
                style = MaterialTheme.typography.labelLarge,
            )
        }

        if (filteredEntries.isEmpty()) {
            EmptyJournalState()
            return
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            groupedEntries.forEach { (group, groupEntries) ->
                item(key = group) {
                    Text(
                        text = group.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }

                items(groupEntries, key = { it.id }) { entry ->
                    EntryCard(
                        entry = entry,
                        onOpenEntry = { onOpenEntry(entry.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun FilterRow(
    title: String,
    values: List<String>,
    selectedValue: String?,
    onSelected: (String?) -> Unit,
) {
    val scrollState = rememberScrollState()

    Column(modifier = Modifier.padding(top = 12.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            modifier = Modifier
                .horizontalScroll(scrollState)
                .padding(top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterChip(
                selectedValue == null,
                onClick = { onSelected(null) },
                label = { Text("All") },
            )
            values.forEach { value ->
                FilterChip(
                    selectedValue == value,
                    onClick = { onSelected(value) },
                    label = { Text(value) },
                )
            }
        }
    }
}

@Composable
private fun EntryCard(
    entry: EirEntry,
    onOpenEntry: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenEntry),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                CategoryBadge(category = entry.category ?: "Övrigt")
                Text(
                    text = listOfNotNull(entry.date, entry.time).joinToString(" "),
                    style = MaterialTheme.typography.bodySmall,
                    color = TextSecondary,
                )
            }

            Text(
                text = entry.content?.summary ?: entry.type ?: "Untitled entry",
                modifier = Modifier.padding(top = 12.dp),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )

            entry.type?.takeUnless { it == entry.content?.summary }?.let { type ->
                Text(
                    text = type,
                    modifier = Modifier.padding(top = 4.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = TextSecondary,
                )
            }

            entry.provider?.name?.let { providerName ->
                Text(
                    text = providerName,
                    modifier = Modifier.padding(top = 8.dp),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            val previewText = entry.notePreviewText
                ?: entry.content?.notes?.firstOrNull()
                ?: entry.content?.details

            previewText?.let { preview ->
                Text(
                    text = preview,
                    modifier = Modifier.padding(top = 10.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = TextSecondary,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun CategoryBadge(category: String) {
    val tint = categoryColor(category)
    Text(
        text = category,
        modifier = Modifier
            .clip(MaterialTheme.shapes.small)
            .background(tint.copy(alpha = 0.12f))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        color = tint,
        style = MaterialTheme.typography.labelMedium,
    )
}

@Composable
private fun EmptyJournalState() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "No matching entries",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "Try clearing a filter or importing another file.",
            modifier = Modifier.padding(top = 8.dp),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
fun EntryDetailScreen(
    entry: EirEntry,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        CategoryBadge(category = entry.category ?: "Övrigt")
                        Text(
                            text = listOfNotNull(entry.date, entry.time).joinToString(" "),
                            color = TextSecondary,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }

                    Text(
                        text = entry.content?.summary ?: entry.type ?: "Untitled entry",
                        modifier = Modifier.padding(top = 12.dp),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )

                    entry.type?.let { type ->
                        Text(
                            text = type,
                            modifier = Modifier.padding(top = 6.dp),
                            style = MaterialTheme.typography.bodyLarge,
                            color = TextSecondary,
                        )
                    }
                }
            }
        }

        entry.provider?.let { provider ->
            item {
                DetailSection(
                    title = "Vårdgivare",
                    lines = listOfNotNull(provider.name, provider.region, provider.location),
                )
            }
        }

        entry.responsiblePerson?.let { person ->
            item {
                DetailSection(
                    title = "Ansvarig",
                    lines = listOfNotNull(person.name, person.role),
                )
            }
        }

        entry.content?.details?.takeUnless { it.isBlank() }?.let { details ->
            item {
                DetailSection(
                    title = entry.detailSectionTitle,
                    body = details,
                )
            }
        }

        entry.content?.notes?.takeIf { it.isNotEmpty() }?.let { notes ->
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = entry.notesSectionTitle,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        notes.forEach { note ->
                            Text(
                                text = note,
                                modifier = Modifier.padding(top = 10.dp),
                                style = MaterialTheme.typography.bodyLarge,
                            )
                        }
                    }
                }
            }
        }

        entry.tags?.takeIf { it.isNotEmpty() }?.let { tags ->
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "Tags",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Row(
                            modifier = Modifier.padding(top = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            tags.forEach { tag ->
                                Text(
                                    text = "#$tag",
                                    modifier = Modifier
                                        .clip(MaterialTheme.shapes.small)
                                        .background(Divider)
                                        .padding(horizontal = 10.dp, vertical = 6.dp),
                                    style = MaterialTheme.typography.labelMedium,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailSection(
    title: String,
    lines: List<String> = emptyList(),
    body: String? = null,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )

            lines.forEach { line ->
                Text(
                    text = line,
                    modifier = Modifier.padding(top = 8.dp),
                    style = MaterialTheme.typography.bodyLarge,
                )
            }

            body?.let {
                Text(
                    text = it,
                    modifier = Modifier.padding(top = 10.dp),
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        }
    }
}
