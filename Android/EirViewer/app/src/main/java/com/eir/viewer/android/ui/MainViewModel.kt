package com.eir.viewer.android.ui

import android.Manifest
import android.annotation.SuppressLint
import android.app.Application
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.eir.viewer.android.data.model.EirDocument
import com.eir.viewer.android.data.model.EirEntry
import com.eir.viewer.android.data.model.ChatConfiguration
import com.eir.viewer.android.data.model.ChatMessage
import com.eir.viewer.android.data.model.ChatProfileState
import com.eir.viewer.android.data.model.ChatRole
import com.eir.viewer.android.data.model.ChatThread
import com.eir.viewer.android.data.model.FindCareClinicMatch
import com.eir.viewer.android.data.model.FindCareIssueAnalysis
import com.eir.viewer.android.data.model.FindCareSuggestedType
import com.eir.viewer.android.data.model.HealthAction
import com.eir.viewer.android.data.model.HealthActionState
import com.eir.viewer.android.data.model.StoredProfile
import com.eir.viewer.android.data.repo.ActionsRepository
import com.eir.viewer.android.data.repo.ChatRepository
import com.eir.viewer.android.data.repo.FindCareRepository
import com.eir.viewer.android.data.repo.ProfilesRepository
import com.eir.viewer.android.data.service.FindCareIssueAnalyzer
import com.eir.viewer.android.data.service.FindCareMatcher
import com.eir.viewer.android.data.service.ChatService
import com.eir.viewer.android.data.service.HealthActionGenerator
import kotlinx.coroutines.launch
import androidx.core.content.ContextCompat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlin.coroutines.cancellation.CancellationException

enum class RootTab(val label: String) {
    FOR_YOU("For You"),
    ACTION("Action"),
    STATE("State"),
    FIND_CARE("Find Care"),
    CHAT("Chat"),
}

data class EirUiState(
    val profiles: List<StoredProfile> = emptyList(),
    val selectedProfileId: String? = null,
    val document: EirDocument? = null,
    val selectedTab: RootTab = RootTab.FOR_YOU,
    val selectedEntryId: String? = null,
    val searchText: String = "",
    val selectedCategory: String? = null,
    val selectedProvider: String? = null,
    val isLoading: Boolean = false,
    val userMessage: String? = null,
    val chatThreads: List<ChatThread> = emptyList(),
    val selectedChatThreadId: String? = null,
    val chatMessages: List<ChatMessage> = emptyList(),
    val chatInput: String = "",
    val isSending: Boolean = false,
    val chatError: String? = null,
    val chatConfig: ChatConfiguration = ChatConfiguration(),
    val actions: List<HealthAction> = emptyList(),
    val actionStates: Map<String, HealthActionState> = emptyMap(),
    val findCareQuery: String = "",
    val findCareIssueText: String = "",
    val findCareIssueAnalysis: FindCareIssueAnalysis? = null,
    val findCareSelectedTypes: Set<FindCareSuggestedType> = emptySet(),
    val findCareResults: List<FindCareClinicMatch> = emptyList(),
    val findCareError: String? = null,
    val isFindCareLoading: Boolean = false,
    val isFindCareLocating: Boolean = false,
    val findCareLatitude: Double? = null,
    val findCareLongitude: Double? = null,
    val isAnalyzingIssue: Boolean = false,
)

class MainViewModel(
    application: Application,
) : AndroidViewModel(application) {
    private val repository = ProfilesRepository(application)
    private val chatRepository = ChatRepository(application)
    private val actionsRepository = ActionsRepository(application)
    private val findCareRepository = FindCareRepository(application)
    private val chatService = ChatService()
    private val findCareMatcher = FindCareMatcher()
    private var activeFindCareSearchId = 0

    var uiState by mutableStateOf(EirUiState())
        private set

    fun setFindCareError(message: String?) {
        uiState = uiState.copy(
            findCareError = message,
            isFindCareLocating = if (message != null) false else uiState.isFindCareLocating,
        )
    }

    init {
        refresh()
    }

    fun importFromUri(uri: Uri) {
        uiState = uiState.copy(isLoading = true)
        viewModelScope.launch {
        runCatching { repository.importFromUri(uri) }
                .onSuccess {
                    refresh(
                        selectedTab = RootTab.STATE,
                        message = "Imported ${it.displayName}",
                    )
                }
                .onFailure { error ->
                    uiState = uiState.copy(
                        isLoading = false,
                        userMessage = error.message ?: "Could not import the selected file.",
                    )
                }
        }
    }

    fun loadSampleData() {
        uiState = uiState.copy(isLoading = true)
        viewModelScope.launch {
        runCatching { repository.importBundledSample() }
                .onSuccess {
                    refresh(
                        selectedTab = RootTab.STATE,
                        message = "Loaded sample profile",
                    )
                }
                .onFailure { error ->
                    uiState = uiState.copy(
                        isLoading = false,
                        userMessage = error.message ?: "Could not load sample data.",
                    )
                }
        }
    }

    fun selectProfile(profileId: String) {
        uiState = uiState.copy(isLoading = true, selectedEntryId = null)
        viewModelScope.launch {
            runCatching {
                repository.selectProfile(profileId)
                refresh()
            }.onFailure { error ->
                uiState = uiState.copy(
                    isLoading = false,
                    userMessage = error.message ?: "Could not switch profile.",
                )
            }
        }
    }

    fun selectTab(tab: RootTab) {
        uiState = uiState.copy(
            selectedTab = tab,
            selectedEntryId = if (tab == RootTab.STATE) uiState.selectedEntryId else null,
        )

        if (tab == RootTab.FIND_CARE && uiState.findCareResults.isEmpty()) {
            runFindCareSearch()
        }
    }

    fun openEntry(entryId: String) {
        uiState = uiState.copy(selectedEntryId = entryId, selectedTab = RootTab.STATE)
    }

    fun closeEntry() {
        uiState = uiState.copy(selectedEntryId = null)
    }

    fun updateSearch(text: String) {
        uiState = uiState.copy(searchText = text)
    }

    fun updateCategory(category: String?) {
        uiState = uiState.copy(selectedCategory = category)
    }

    fun updateProvider(provider: String?) {
        uiState = uiState.copy(selectedProvider = provider)
    }

    fun clearFilters() {
        uiState = uiState.copy(
            searchText = "",
            selectedCategory = null,
            selectedProvider = null,
        )
    }

    fun updateFindCareQuery(text: String) {
        uiState = uiState.copy(findCareQuery = text)
    }

    fun updateFindCareIssueText(text: String) {
        uiState = uiState.copy(findCareIssueText = text)
    }

    fun toggleFindCareType(type: FindCareSuggestedType) {
        val nextTypes = if (uiState.findCareSelectedTypes.contains(type)) {
            uiState.findCareSelectedTypes - type
        } else {
            uiState.findCareSelectedTypes + type
        }
        uiState = uiState.copy(findCareSelectedTypes = nextTypes)
        if (uiState.selectedTab == RootTab.FIND_CARE) {
            runFindCareSearch(uiState.findCareQuery, nextTypes)
        }
    }

    fun analyzeFindCareIssue() {
        val issueText = uiState.findCareIssueText.trim()
        val selectedTypes = uiState.findCareSelectedTypes
        if (issueText.isBlank()) {
            return
        }

        uiState = uiState.copy(isAnalyzingIssue = true, findCareError = null)
        viewModelScope.launch {
            runCatching { FindCareIssueAnalyzer.analyze(issueText) }
                .onSuccess { analysis ->
                    val derivedQuery = analysis.query.takeIf { it.isNotBlank() } ?: issueText
                    val effectiveTypes = if (analysis.suggestedTypes.isNotEmpty()) {
                        analysis.suggestedTypes
                    } else {
                        selectedTypes
                    }

                    uiState = uiState.copy(
                        findCareIssueAnalysis = analysis,
                        findCareQuery = derivedQuery,
                        findCareSelectedTypes = effectiveTypes,
                        isAnalyzingIssue = false,
                    )

                    runFindCareSearch(derivedQuery, effectiveTypes)
                }
                .onFailure { error ->
                    uiState = uiState.copy(
                        isAnalyzingIssue = false,
                        findCareError = error.message ?: "Could not analyze the issue description.",
                    )
                }
        }
    }

    fun requestFindCareLocation() {
        if (!hasFindCareLocationPermission()) {
            uiState = uiState.copy(
                isFindCareLocating = false,
                findCareError = "Location permission is not enabled. Grant it first.",
            )
            return
        }

        uiState = uiState.copy(
            isFindCareLocating = true,
            findCareError = null,
        )

        viewModelScope.launch {
            val location = readCurrentLocation()
            if (location != null) {
                val (latitude, longitude) = location
                uiState = uiState.copy(
                    findCareLatitude = latitude,
                    findCareLongitude = longitude,
                    isFindCareLocating = false,
                    findCareError = null,
                )
                runFindCareSearch(uiState.findCareQuery, uiState.findCareSelectedTypes)
            } else {
                uiState = uiState.copy(
                    isFindCareLocating = false,
                    findCareError = "Unable to read your location yet. Try again or search manually.",
                )
            }
        }
    }

    fun clearFindCareLocation() {
        uiState = uiState.copy(
            findCareLatitude = null,
            findCareLongitude = null,
            findCareError = null,
        )
        runFindCareSearch(uiState.findCareQuery, uiState.findCareSelectedTypes)
    }

    fun runFindCareSearch() {
        runFindCareSearch(uiState.findCareQuery, uiState.findCareSelectedTypes)
    }

    fun toggleActionPinned(action: HealthAction) {
        val existing = uiState.actionStates[action.id] ?: HealthActionState()
        val updated = existing.copy(isPinned = !existing.isPinned)
        val nextStates = uiState.actionStates.toMutableMap().apply {
            this[action.id] = updated
        }
        uiState = uiState.copy(actionStates = nextStates)

        viewModelScope.launch {
            actionsRepository.saveProfileState(uiState.selectedProfileId, nextStates)
        }
    }

    fun toggleActionCompleted(action: HealthAction) {
        val existing = uiState.actionStates[action.id] ?: HealthActionState()
        val today = completionDayStamp()
        val updated = if (existing.completionDayStamps.contains(today)) {
            existing.copy(completionDayStamps = existing.completionDayStamps.filterNot { it == today })
        } else {
            val next = existing.completionDayStamps + today
            existing.copy(completionDayStamps = next.takeLast(21))
        }
        val nextStates = uiState.actionStates.toMutableMap().apply {
            this[action.id] = updated
        }
        uiState = uiState.copy(actionStates = nextStates)

        viewModelScope.launch {
            actionsRepository.saveProfileState(uiState.selectedProfileId, nextStates)
        }
    }

    fun updateChatInput(text: String) {
        uiState = uiState.copy(chatInput = text)
    }

    fun clearChatError() {
        uiState = uiState.copy(chatError = null)
    }

    fun updateChatConfiguration(
        baseUrl: String,
        model: String,
        apiKey: String,
        includeRecordContext: Boolean,
    ) {
        val updated = ChatConfiguration(
            providerBaseUrl = baseUrl.ifBlank { "https://api.openai.com/v1" },
            model = model.ifBlank { "gpt-4o-mini" },
            apiKey = apiKey,
            includeRecordContext = includeRecordContext,
        )
        uiState = uiState.copy(chatConfig = updated)
        viewModelScope.launch {
            chatRepository.saveConfiguration(updated)
        }
    }

    fun selectChatThread(threadId: String?) {
        val profileId = uiState.selectedProfileId ?: return
        viewModelScope.launch {
            runCatching {
                chatRepository.setSelectedThread(profileId, threadId)
                val state = chatRepository.loadProfileState(profileId)
                val messages = threadId?.let { chatRepository.loadMessages(it) } ?: emptyList()
                uiState = uiState.copy(
                    selectedChatThreadId = threadId,
                    chatMessages = messages,
                    chatThreads = state.threads,
                    chatError = null,
                )
            }.onFailure { error ->
                uiState = uiState.copy(chatError = error.message)
            }
        }
    }

    fun createNewChatThread() {
        val profileId = uiState.selectedProfileId ?: return
        val profile = currentProfile() ?: return
        viewModelScope.launch {
            runCatching {
                val thread = chatRepository.createThread(profileId, "New conversation for ${profile.displayName}")
                val state = chatRepository.loadProfileState(profileId)
                uiState = uiState.copy(
                    selectedChatThreadId = thread.id,
                    chatMessages = emptyList(),
                    chatThreads = state.threads,
                    chatError = null,
                )
            }.onFailure { error ->
                uiState = uiState.copy(chatError = error.message)
            }
        }
    }

    fun sendChatMessage() {
        val profileId = uiState.selectedProfileId
        val trimmedInput = uiState.chatInput.trim()
        if (profileId == null || trimmedInput.isBlank() || uiState.isSending) {
            return
        }

        val config = uiState.chatConfig
        if (config.apiKey.isBlank()) {
            uiState = uiState.copy(userMessage = "Add a chat provider API key in Chat settings.")
            return
        }

        val priorThreadId = uiState.selectedChatThreadId
        val existingMessages = uiState.chatMessages
        val priorDocument = uiState.document
        var activeThreadId: String? = priorThreadId
        uiState = uiState.copy(chatInput = "", isSending = true, chatError = null, selectedTab = RootTab.CHAT)

        viewModelScope.launch {
            try {
                val state = chatRepository.loadProfileState(profileId)
                val activeThread = state.threads.firstOrNull { it.id == priorThreadId }
                    ?: chatRepository.createThread(profileId, buildThreadTitle(trimmedInput))
                activeThreadId = activeThread.id
                chatRepository.setSelectedThread(profileId, activeThread.id)

                val userMessage = ChatMessage(role = ChatRole.USER, content = trimmedInput)
                val assistantMessage = ChatMessage(role = ChatRole.ASSISTANT, content = "")
                val stagedMessages = existingMessages + userMessage + assistantMessage
                chatRepository.saveMessages(activeThread.id, stagedMessages)
                val systemContextEnabled = config.includeRecordContext
                val requestMessages = buildPromptMessages(
                    messages = stagedMessages.dropLast(1),
                    document = if (systemContextEnabled) priorDocument else null,
                    includeContext = systemContextEnabled,
                )

                uiState = uiState.copy(
                    selectedChatThreadId = activeThread.id,
                    chatMessages = stagedMessages,
                    chatThreads = state.threads
                        .toMutableList()
                        .apply {
                            if (none { it.id == activeThread.id }) {
                                add(0, activeThread.copy(updatedAt = System.currentTimeMillis()))
                            }
                        }
                        .sortedByDescending { it.updatedAt },
                )

                val reply = chatService.completeChat(config, requestMessages)
                val assistantIndex = stagedMessages.lastIndex
                val finalMessages = stagedMessages.toMutableList().also {
                    it[assistantIndex] = it[assistantIndex].copy(
                        content = reply.ifBlank { "I could not generate a response with the current inputs." },
                    )
                }

                chatRepository.saveMessages(activeThread.id, finalMessages)
                chatRepository.updateThreadTitle(profileId, activeThread.id, buildThreadTitle(trimmedInput))
                val refreshedThreadState = chatRepository.loadProfileState(profileId)

                uiState = uiState.copy(
                    chatMessages = finalMessages,
                    chatThreads = refreshedThreadState.threads,
                    selectedChatThreadId = activeThread.id,
                    isSending = false,
                )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                Log.w("MainViewModel", "Chat request failed", error)
                val fallbackMessages = existingMessages + ChatMessage(role = ChatRole.USER, content = trimmedInput)
                activeThreadId?.let { chatRepository.saveMessages(it, fallbackMessages) }
                uiState = uiState.copy(
                    chatMessages = fallbackMessages,
                    isSending = false,
                    chatError = error.message ?: "Could not send chat message.",
                )
            }
        }
    }

    fun dismissMessage() {
        uiState = uiState.copy(userMessage = null)
    }

    fun currentChatThread(): ChatThread? =
        uiState.chatThreads.firstOrNull { it.id == uiState.selectedChatThreadId }

    fun currentProfile(): StoredProfile? =
        uiState.profiles.firstOrNull { it.id == uiState.selectedProfileId }

    fun selectedEntry(): EirEntry? =
        uiState.document?.entries?.firstOrNull { it.id == uiState.selectedEntryId }

    private fun refresh(
        selectedTab: RootTab = uiState.selectedTab,
        message: String? = null,
    ) {
        viewModelScope.launch {
            val storedState = repository.loadState()
            val document = storedState.profiles
                .firstOrNull { it.id == storedState.selectedProfileId }
                ?.let { runCatching { repository.loadDocument(it) }.getOrNull() }
            val profileId = storedState.selectedProfileId
            val chatState = profileId?.let { chatRepository.loadProfileState(it) } ?: ChatProfileState()
            val messages = chatState.selectedThreadId?.let { chatRepository.loadMessages(it) } ?: emptyList()
            val chatConfig = chatRepository.loadConfiguration()
            val actions = HealthActionGenerator.generate(document)
            val actionStates = actionsRepository.loadProfileState(profileId)

            uiState = uiState.copy(
                profiles = storedState.profiles,
                selectedProfileId = storedState.selectedProfileId,
                document = document,
                selectedTab = selectedTab,
                selectedEntryId = null,
                chatThreads = chatState.threads,
                selectedChatThreadId = chatState.selectedThreadId,
                chatMessages = messages,
                chatConfig = chatConfig,
                actions = actions,
                actionStates = actionStates,
                isLoading = false,
                userMessage = message ?: uiState.userMessage,
            )
        }
    }

    private fun runFindCareSearch(
        query: String,
        selectedTypes: Set<FindCareSuggestedType>,
    ) {
        val trimmedQuery = query.trim()
        val token = ++activeFindCareSearchId
        uiState = uiState.copy(
            findCareQuery = trimmedQuery,
            isFindCareLoading = true,
            findCareError = null,
        )

        viewModelScope.launch {
            runCatching {
                val clinics = findCareRepository.loadClinics()
                findCareMatcher.rankedClinics(
                    clinics = clinics,
                    query = trimmedQuery,
                    selectedTypes = selectedTypes,
                    userLatitude = uiState.findCareLatitude,
                    userLongitude = uiState.findCareLongitude,
                )
            }.onSuccess { results ->
                if (token == activeFindCareSearchId) {
                    uiState = uiState.copy(
                        findCareResults = results,
                        isFindCareLoading = false,
                    )
                }
            }.onFailure { error ->
                if (token == activeFindCareSearchId) {
                    uiState = uiState.copy(
                        findCareResults = emptyList(),
                        isFindCareLoading = false,
                        findCareError = error.message ?: "Could not search care options.",
                    )
                }
            }
        }
    }

    private fun hasFindCareLocationPermission(): Boolean {
        val context = getApplication<Application>().applicationContext
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    private fun readCurrentLocation(): Pair<Double, Double>? {
        val context = getApplication<Application>().applicationContext
        val locationManager = context.getSystemService(LocationManager::class.java)

        if (!hasFindCareLocationPermission()) {
            return null
        }

        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        )
            .mapNotNull { provider ->
                runCatching {
                    locationManager.getLastKnownLocation(provider)
                }.getOrNull()
            }
            .sortedByDescending { it.time }
            .toList()

        val best = providers.firstOrNull() ?: return null
        return Pair(best.latitude, best.longitude)
    }

    private fun completionDayStamp(): String {
        return LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
    }

    private fun buildThreadTitle(text: String): String =
        text.trim().ifBlank { "New conversation" }.take(44)

    private fun buildPromptMessages(
        messages: List<ChatMessage>,
        document: EirDocument?,
        includeContext: Boolean,
    ): List<ChatMessage> {
        val trimmedMessages = messages.takeLast(24)
        if (!includeContext || document == null) {
            return trimmedMessages
        }

        return mutableListOf<ChatMessage>().apply {
            add(ChatMessage(role = ChatRole.SYSTEM, content = buildRecordSystemPrompt(document)))
            addAll(trimmedMessages)
        }
    }

    private fun buildRecordSystemPrompt(document: EirDocument): String {
        val patient = document.metadata.patient
        val patientText = buildString {
            append("You are a medical assistant helping with a Swedish healthcare summary.")
            append(" Use concise and safe guidance.")
            append(" Only rely on the provided record data.")
            append(" If clinical decisions are required, advise the user to contact medical staff.")
            patient?.let {
                append(" Patient name: ").append(it.name ?: "Unknown")
                it.birthDate?.let { birth -> append(", born ").append(birth) }
                it.personalNumber?.let { number -> append(", personal number ").append(number) }
            }
        }

        val latest = document.entries
            .mapNotNull { entry ->
                val label = entry.date ?: return@mapNotNull null
                val summary = entry.content?.summary ?: entry.type
                val provider = entry.provider?.name ?: "Unknown provider"
                "$label — $provider: ${summary.orEmpty()}"
            }.takeLast(8)

        val top = buildString {
            append("Recent records:\n")
            if (latest.isEmpty()) {
                append("- No records available.")
            } else {
                latest.forEach { append("• ").append(it).append('\n') }
            }
        }

        val summary = document.metadata.exportInfo?.totalEntries
            ?.let { "Total entries in import: $it." } ?: "Total entries in import: unknown."

        return buildString {
            append(patientText)
            append('\n')
            append("You can reference these records, but do not claim certainty beyond them.\n")
            append(summary)
            append('\n')
            append(top)
        }
    }
}
