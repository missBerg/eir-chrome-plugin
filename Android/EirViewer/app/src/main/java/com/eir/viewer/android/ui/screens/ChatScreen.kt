package com.eir.viewer.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import com.eir.viewer.android.data.model.ChatMessage
import com.eir.viewer.android.data.model.ChatRole
import com.eir.viewer.android.data.model.ChatThread
import com.eir.viewer.android.data.model.StoredProfile
import com.eir.viewer.android.ui.theme.BackgroundMuted
import com.eir.viewer.android.ui.theme.Primary
import com.eir.viewer.android.ui.theme.Red
import com.eir.viewer.android.ui.theme.TextSecondary
import java.text.DateFormat
import java.util.Date

@Composable
fun ChatScreen(
    profile: StoredProfile?,
    threads: List<ChatThread>,
    selectedThreadId: String?,
    messages: List<ChatMessage>,
    chatInput: String,
    isSending: Boolean,
    error: String?,
    onInputChange: (String) -> Unit,
    onSend: () -> Unit,
    onNewThread: () -> Unit,
    onSelectThread: (String?) -> Unit,
    onPromptSelected: (String) -> Unit,
    onOpenSettings: () -> Unit,
    onClearError: () -> Unit,
) {
    val listState: LazyListState = rememberLazyListState()
    val quickPrompts = remember(profile?.displayName) {
        if (profile == null) {
            emptyList()
        } else {
            listOf(
                "Summarize ${profile.displayName}'s recent timeline.",
                "What should I discuss at my next appointment?",
                "Flag anything urgent to call about.",
            )
        }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.lastIndex)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "Chat",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.width(8.dp))
            FilledTonalButton(onClick = onNewThread, enabled = !isSending) {
                Text("New")
            }
            Spacer(modifier = Modifier.weight(1f))
            Button(onClick = onOpenSettings) {
                Text("Settings")
            }
        }

        if (threads.isNotEmpty()) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(threads.size) { index ->
                    val thread = threads[index]
                    FilterChip(
                        selected = thread.id == selectedThreadId,
                        onClick = { onSelectThread(thread.id) },
                        enabled = !isSending,
                        label = {
                            Text(
                                text = thread.title,
                                maxLines = 1,
                            )
                        },
                    )
                }
            }
        } else {
            Text(
                text = "Tap New to start a conversation and ask about the profile.",
                style = MaterialTheme.typography.bodyLarge,
                color = TextSecondary,
            )
        }

        error?.let {
            Card(
                colors = CardDefaults.cardColors(containerColor = Red.copy(alpha = 0.08f)),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Warning,
                        contentDescription = "Chat error",
                        tint = Red,
                    )
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = Red,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = onClearError) {
                        Text("Dismiss")
                    }
                }
            }
        }

        if (messages.isEmpty()) {
            ChatHint(
                modifier = Modifier.weight(1f),
                profile = profile,
                quickPrompts = quickPrompts,
                onPromptSelected = onPromptSelected,
            )
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(messages, key = { it.id }) { message ->
                    ChatBubble(message = message)
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = chatInput,
                onValueChange = onInputChange,
                modifier = Modifier.weight(1f),
                label = { Text("Ask a question") },
                maxLines = 6,
                enabled = !isSending,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(
                    onSend = {
                        if (chatInput.isNotBlank()) {
                            onSend()
                        }
                    },
                ),
            )

            Spacer(modifier = Modifier.width(8.dp))

            if (isSending) {
                CircularProgressIndicator(modifier = Modifier.size(42.dp))
            } else {
                FilledIconButton(
                    onClick = onSend,
                    enabled = chatInput.isNotBlank(),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Send,
                        contentDescription = "Send",
                    )
                }
            }
        }

        Text(
            text = if (profile == null) {
                "Select a profile and configure chat to start."
            } else {
                "Messages are stored locally in your app and sent to the configured model for replies."
            },
            style = MaterialTheme.typography.bodySmall,
            color = TextSecondary,
        )
    }
}

@Composable
private fun ChatHint(
    modifier: Modifier,
    profile: StoredProfile?,
    quickPrompts: List<String>,
    onPromptSelected: (String) -> Unit,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.height(24.dp))
        Card(
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = if (profile == null) {
                        "Choose a profile to begin."
                    } else {
                        "Ask a first question about ${profile.displayName}'s record."
                    },
                    style = MaterialTheme.typography.titleMedium,
                )
                if (quickPrompts.isNotEmpty()) {
                    Text(
                        text = "Try a starter prompt",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextSecondary,
                    )
                }
            }
        }

        if (quickPrompts.isNotEmpty()) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(top = 14.dp),
            ) {
                items(quickPrompts) { prompt ->
                    FilterChip(
                        selected = false,
                        onClick = { onPromptSelected(prompt) },
                        label = { Text(prompt) },
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(18.dp))
        HorizontalDivider(modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun ChatBubble(message: ChatMessage) {
    val isUser = message.role == ChatRole.USER
    val alignment = if (isUser) Arrangement.End else Arrangement.Start
    val background = if (isUser) Primary else BackgroundMuted
    val prefix = if (isUser) "You" else "Assistant"
    val sentAt = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(message.timestampMillis))
    val clipboardManager = LocalClipboardManager.current

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = alignment,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 330.dp)
                .background(background, RoundedCornerShape(16.dp))
                .padding(12.dp),
        ) {
            Text(
                text = prefix,
                style = MaterialTheme.typography.labelMedium,
                color = TextSecondary,
            )
            Text(
                text = message.content.ifBlank { "…writing" },
                style = MaterialTheme.typography.bodyMedium,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = sentAt,
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                )
                Text(
                    text = "Copy",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    modifier = Modifier.clickable {
                        clipboardManager.setText(AnnotatedString(message.content))
                    },
                )
            }
        }
    }
}
