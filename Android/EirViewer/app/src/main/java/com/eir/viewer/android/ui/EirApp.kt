package com.eir.viewer.android.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts.OpenDocument
import androidx.activity.result.contract.ActivityResultContracts.RequestPermission
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.platform.LocalContext
import com.eir.viewer.android.ui.screens.ActionScreen
import com.eir.viewer.android.ui.screens.ChatScreen
import com.eir.viewer.android.ui.screens.EntryDetailScreen
import com.eir.viewer.android.ui.screens.FindCareScreen
import com.eir.viewer.android.ui.screens.ForYouScreen
import com.eir.viewer.android.ui.screens.JournalScreen
import com.eir.viewer.android.ui.screens.WelcomeScreen
import com.eir.viewer.android.ui.theme.Background
import com.eir.viewer.android.ui.theme.BackgroundMuted
import com.eir.viewer.android.ui.theme.Primary
import androidx.core.content.ContextCompat

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EirApp(
    viewModel: MainViewModel,
) {
    val uiState = viewModel.uiState
    val snackbarHostState = remember { SnackbarHostState() }
    var menuExpanded by remember { mutableStateOf(false) }
    var showChatSettings by remember { mutableStateOf(false) }
    val context = LocalContext.current
    var chatConfigBaseUrl by rememberSaveable(uiState.chatConfig.providerBaseUrl) { mutableStateOf(uiState.chatConfig.providerBaseUrl) }
    var chatConfigModel by rememberSaveable(uiState.chatConfig.model) { mutableStateOf(uiState.chatConfig.model) }
    var chatConfigApiKey by rememberSaveable(uiState.chatConfig.apiKey) { mutableStateOf(uiState.chatConfig.apiKey) }
    var chatConfigIncludeContext by rememberSaveable(uiState.chatConfig.includeRecordContext) { mutableStateOf(uiState.chatConfig.includeRecordContext) }

    val requestFindCareLocationPermission = rememberLauncherForActivityResult(
        contract = RequestPermission(),
    ) { granted ->
        if (granted) {
            viewModel.requestFindCareLocation()
        } else {
            viewModel.setFindCareError("Location permission denied. Search by municipality or clinic name instead.")
        }
    }

    val ensureFindCareLocation = {
        val hasCoarsePermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val hasFinePermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        if (hasCoarsePermission || hasFinePermission) {
            viewModel.requestFindCareLocation()
        } else {
            requestFindCareLocationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }

    val openDocumentLauncher = rememberLauncherForActivityResult(OpenDocument()) { uri ->
        if (uri != null) {
            viewModel.importFromUri(uri)
        }
    }

    LaunchedEffect(uiState.userMessage) {
        uiState.userMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.dismissMessage()
        }
    }

    val currentProfile = viewModel.currentProfile()
    val selectedEntry = viewModel.selectedEntry()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when {
                            selectedEntry != null -> selectedEntry.content?.summary ?: "Entry details"
                            currentProfile != null -> currentProfile.displayName
                            else -> "Eir Viewer"
                        },
                    )
                },
                navigationIcon = {
                    if (selectedEntry != null) {
                        IconButton(onClick = viewModel::closeEntry) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Back to entries",
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    scrolledContainerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    actionIconContentColor = MaterialTheme.colorScheme.primary,
                    navigationIconContentColor = MaterialTheme.colorScheme.primary,
                ),
                actions = {
                    IconButton(onClick = { openDocumentLauncher.launch(arrayOf("*/*")) }) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = "Import .eir file",
                        )
                    }

                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(
                            imageVector = Icons.Default.MoreVert,
                            contentDescription = "Open app menu",
                        )
                    }

                    DropdownMenu(
                        expanded = menuExpanded,
                        onDismissRequest = { menuExpanded = false },
                    ) {
                        DropdownMenuItem(
                            text = { Text("Load sample data") },
                            onClick = {
                                menuExpanded = false
                                viewModel.loadSampleData()
                            },
                        )

                        DropdownMenuItem(
                            text = { Text("Chat settings") },
                            onClick = {
                                menuExpanded = false
                                chatConfigBaseUrl = uiState.chatConfig.providerBaseUrl
                                chatConfigModel = uiState.chatConfig.model
                                chatConfigApiKey = uiState.chatConfig.apiKey
                                chatConfigIncludeContext = uiState.chatConfig.includeRecordContext
                                showChatSettings = true
                            },
                        )

                        if (uiState.profiles.isNotEmpty()) {
                            uiState.profiles.forEach { profile ->
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            if (profile.id == uiState.selectedProfileId) {
                                                "• ${profile.displayName}"
                                            } else {
                                                profile.displayName
                                            },
                                        )
                                    },
                                    onClick = {
                                        menuExpanded = false
                                        viewModel.selectProfile(profile.id)
                                    },
                                )
                            }
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
        bottomBar = {
            if (uiState.profiles.isNotEmpty()) {
                NavigationBar(
                    containerColor = MaterialTheme.colorScheme.surface,
                ) {
                    RootTab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = uiState.selectedTab == tab,
                            onClick = { viewModel.selectTab(tab) },
                            icon = {
                                Icon(
                                    imageVector = tab.icon(),
                                    contentDescription = tab.label,
                                )
                            },
                            label = { Text(tab.label) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            ),
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        val shellBrush = Brush.verticalGradient(
            colors = listOf(
                Primary.copy(alpha = 0.15f),
                BackgroundMuted,
                Background,
            ),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(shellBrush)
                .padding(innerPadding),
        ) {
            if (uiState.profiles.isEmpty()) {
                WelcomeScreen(
                    isLoading = uiState.isLoading,
                    onChooseFile = { openDocumentLauncher.launch(arrayOf("*/*")) },
                    onLoadSample = viewModel::loadSampleData,
                )
            } else {
                when (uiState.selectedTab) {
                    RootTab.FOR_YOU -> ForYouScreen(
                        profile = currentProfile,
                        document = uiState.document,
                        actions = uiState.actions,
                        actionStates = uiState.actionStates,
                        onTogglePinned = viewModel::toggleActionPinned,
                        onToggleCompleted = viewModel::toggleActionCompleted,
                    )

                    RootTab.ACTION -> ActionScreen(
                        actions = uiState.actions,
                        actionStates = uiState.actionStates,
                        onTogglePinned = viewModel::toggleActionPinned,
                        onToggleCompleted = viewModel::toggleActionCompleted,
                    )

                    RootTab.STATE -> {
                        if (selectedEntry != null) {
                            EntryDetailScreen(entry = selectedEntry)
                        } else {
                            JournalScreen(
                                document = uiState.document,
                                searchText = uiState.searchText,
                                selectedCategory = uiState.selectedCategory,
                                selectedProvider = uiState.selectedProvider,
                                onSearchChange = viewModel::updateSearch,
                                onCategoryChange = viewModel::updateCategory,
                                onProviderChange = viewModel::updateProvider,
                                onClearFilters = viewModel::clearFilters,
                                onOpenEntry = viewModel::openEntry,
                            )
                        }
                    }

                    RootTab.FIND_CARE -> FindCareScreen(
                        query = uiState.findCareQuery,
                        issueText = uiState.findCareIssueText,
                        issueAnalysis = uiState.findCareIssueAnalysis,
                        selectedTypes = uiState.findCareSelectedTypes,
                        results = uiState.findCareResults,
                        isLoading = uiState.isFindCareLoading,
                        isLocating = uiState.isFindCareLocating,
                        hasLocation = uiState.findCareLatitude != null && uiState.findCareLongitude != null,
                        error = uiState.findCareError,
                        isAnalyzing = uiState.isAnalyzingIssue,
                        onQueryChange = viewModel::updateFindCareQuery,
                        onIssueTextChange = viewModel::updateFindCareIssueText,
                        onAnalyzeIssue = viewModel::analyzeFindCareIssue,
                        onToggleType = viewModel::toggleFindCareType,
                        onRunSearch = viewModel::runFindCareSearch,
                        onUseMyLocation = ensureFindCareLocation,
                        onClearLocation = viewModel::clearFindCareLocation,
                    )
                    RootTab.CHAT -> ChatScreen(
                        profile = currentProfile,
                        threads = uiState.chatThreads,
                        selectedThreadId = uiState.selectedChatThreadId,
                        messages = uiState.chatMessages,
                        chatInput = uiState.chatInput,
                        isSending = uiState.isSending,
                        error = uiState.chatError,
                        onInputChange = viewModel::updateChatInput,
                        onSend = viewModel::sendChatMessage,
                        onNewThread = viewModel::createNewChatThread,
                        onSelectThread = viewModel::selectChatThread,
                        onPromptSelected = { prompt ->
                            viewModel.updateChatInput(prompt)
                            viewModel.sendChatMessage()
                        },
                        onOpenSettings = { showChatSettings = true },
                        onClearError = viewModel::clearChatError,
                    )
                }
            }

            if (uiState.isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }

    if (showChatSettings) {
        AlertDialog(
            onDismissRequest = { showChatSettings = false },
            title = { Text("Chat settings") },
            text = {
                Column(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    OutlinedTextField(
                        value = chatConfigBaseUrl,
                        onValueChange = { chatConfigBaseUrl = it },
                        label = { Text("OpenAI-compatible base URL") },
                        modifier = Modifier.fillMaxWidth(),
                    )

                    OutlinedTextField(
                        value = chatConfigModel,
                        onValueChange = { chatConfigModel = it },
                        label = { Text("Model") },
                        modifier = Modifier.fillMaxWidth(),
                    )

                    OutlinedTextField(
                        value = chatConfigApiKey,
                        onValueChange = { chatConfigApiKey = it },
                        label = { Text("API key") },
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Column(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("Record context")
                        Switch(
                            checked = chatConfigIncludeContext,
                            onCheckedChange = { chatConfigIncludeContext = it },
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showChatSettings = false
                        viewModel.updateChatConfiguration(
                            baseUrl = chatConfigBaseUrl,
                            model = chatConfigModel,
                            apiKey = chatConfigApiKey,
                            includeRecordContext = chatConfigIncludeContext,
                        )
                    },
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showChatSettings = false },
                ) {
                    Text("Cancel")
                }
            },
        )
    }
}

private fun RootTab.icon() = when (this) {
    RootTab.FOR_YOU -> Icons.Default.Home
    RootTab.ACTION -> Icons.AutoMirrored.Filled.List
    RootTab.STATE -> Icons.Default.Favorite
    RootTab.FIND_CARE -> Icons.Default.Search
    RootTab.CHAT -> Icons.AutoMirrored.Filled.Send
}
