const STORAGE_KEY = "eir.nothing.session.v1";
const POINT_INTERVAL_SECONDS = 5 * 60;

const stage = document.getElementById("stage");
const timerValue = document.getElementById("timerValue");
const timerStatus = document.getElementById("timerStatus");
const progressLabel = document.getElementById("progressLabel");
const progressValue = document.getElementById("progressValue");
const progressFill = document.getElementById("progressFill");
const pendingValue = document.getElementById("pendingValue");
const sessionButton = document.getElementById("sessionButton");
const sessionButtonLabel = document.getElementById("sessionButtonLabel");
const sessionButtonIcon = document.getElementById("sessionButtonIcon");
const liveBadge = document.getElementById("liveBadge");
const pointsValue = document.getElementById("pointsValue");
const summaryPoints = document.getElementById("summaryPoints");
const summarySessions = document.getElementById("summarySessions");
const summaryQuiet = document.getElementById("summaryQuiet");

const state = {
    sessionCount: 0,
    nothingPoints: 0,
    quietMinutes: 0,
    isTracking: false,
    startedAt: null,
    elapsedSeconds: 0,
    timerId: 0
};

function loadState() {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (!raw) {
            return;
        }

        const parsed = JSON.parse(raw);
        state.sessionCount = parsed.sessionCount ?? 0;
        state.nothingPoints = parsed.nothingPoints ?? 0;
        state.quietMinutes = parsed.quietMinutes ?? 0;
        state.isTracking = Boolean(parsed.isTracking);
        state.startedAt = parsed.startedAt ?? null;
    } catch {
        localStorage.removeItem(STORAGE_KEY);
    }
}

function saveState() {
    localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({
            sessionCount: state.sessionCount,
            nothingPoints: state.nothingPoints,
            quietMinutes: state.quietMinutes,
            isTracking: state.isTracking,
            startedAt: state.startedAt
        })
    );
}

function formatElapsed(totalSeconds) {
    const safe = Math.max(0, Math.floor(totalSeconds));
    const hours = Math.floor(safe / 3600);
    const minutes = Math.floor((safe % 3600) / 60);
    const seconds = safe % 60;

    if (hours > 0) {
        return [hours, minutes, seconds].map((part) => String(part).padStart(2, "0")).join(":");
    }

    return [minutes, seconds].map((part) => String(part).padStart(2, "0")).join(":");
}

function shortDurationLabel(totalSeconds) {
    const safe = Math.max(1, Math.ceil(totalSeconds));
    const minutes = Math.floor(safe / 60);
    const seconds = safe % 60;
    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function progressToNextPoint() {
    if (!state.isTracking) {
        return 0.02;
    }

    const remainder = state.elapsedSeconds % POINT_INTERVAL_SECONDS;
    return Math.max(0.02, remainder / POINT_INTERVAL_SECONDS);
}

function currentSessionPendingPoints() {
    if (!state.isTracking) {
        return 0;
    }

    return Math.floor(state.elapsedSeconds / POINT_INTERVAL_SECONDS);
}

function nextPointCountdownLabel() {
    if (!state.isTracking) {
        return "Start a session";
    }

    const remainder = state.elapsedSeconds % POINT_INTERVAL_SECONDS;
    const remaining = remainder === 0 && state.elapsedSeconds >= POINT_INTERVAL_SECONDS
        ? POINT_INTERVAL_SECONDS
        : POINT_INTERVAL_SECONDS - remainder;
    return `Next point in ${shortDurationLabel(remaining)}`;
}

function updateSummary() {
    pointsValue.textContent = String(state.nothingPoints);
    summaryPoints.textContent = String(state.nothingPoints);
    summarySessions.textContent = String(state.sessionCount);
    summaryQuiet.textContent = `${Math.round(state.quietMinutes)}m`;
}

function updateSessionUi() {
    stage.dataset.state = state.isTracking ? "running" : "idle";
    timerValue.textContent = state.isTracking ? formatElapsed(state.elapsedSeconds) : "00:00";
    timerStatus.textContent = state.isTracking ? "Breathe." : "Ready.";
    progressLabel.textContent = state.isTracking ? "Next point" : "Rate";
    progressValue.textContent = state.isTracking ? nextPointCountdownLabel() : "1 point / 5m";
    progressFill.style.width = `${progressToNextPoint() * 100}%`;
    pendingValue.textContent = String(currentSessionPendingPoints());
    sessionButtonLabel.textContent = state.isTracking ? "End session" : "Start session";
    sessionButtonIcon.textContent = state.isTracking ? "❚❚" : "▶";
    sessionButton.dataset.state = state.isTracking ? "running" : "idle";
    liveBadge.hidden = !state.isTracking;
    updateSummary();
}

function stopTicker() {
    if (state.timerId) {
        window.clearInterval(state.timerId);
        state.timerId = 0;
    }
}

function tick() {
    if (!state.isTracking || !state.startedAt) {
        return;
    }

    state.elapsedSeconds = Math.max(0, Math.floor((Date.now() - state.startedAt) / 1000));
    updateSessionUi();
}

function startTicker() {
    stopTicker();
    tick();
    state.timerId = window.setInterval(tick, 1000);
}

function startSession() {
    state.isTracking = true;
    state.startedAt = Date.now();
    state.elapsedSeconds = 0;
    saveState();
    startTicker();
}

function stopSession() {
    if (!state.startedAt) {
        return;
    }

    const durationSeconds = Math.max(0, Math.floor((Date.now() - state.startedAt) / 1000));
    const minutes = Math.max(1, durationSeconds / 60);
    const awardedPoints = Math.floor(durationSeconds / POINT_INTERVAL_SECONDS);

    state.quietMinutes += minutes;
    state.sessionCount += 1;
    state.nothingPoints += awardedPoints;
    state.isTracking = false;
    state.startedAt = null;
    state.elapsedSeconds = 0;

    stopTicker();
    saveState();
    updateSessionUi();
}

sessionButton.addEventListener("click", () => {
    if (state.isTracking) {
        stopSession();
        return;
    }

    startSession();
});

loadState();

if (state.isTracking && state.startedAt) {
    startTicker();
} else {
    state.isTracking = false;
    state.startedAt = null;
    state.elapsedSeconds = 0;
    updateSessionUi();
}
