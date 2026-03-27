const API_BASE = (() => {
    const { protocol, hostname, port } = window.location;
    if ((hostname === "127.0.0.1" || hostname === "localhost") && port && port !== "4181") {
        return `${protocol}//127.0.0.1:4181`;
    }
    return "";
})();

const viewerRoot = document.getElementById("viewerRoot");
const emptyState = document.getElementById("emptyState");
const titleInput = document.getElementById("storyTitleInput");
const bodyInput = document.getElementById("storyBodyInput");
const previewTitle = document.getElementById("previewTitle");
const previewBody = document.getElementById("previewBody");
const recordList = document.getElementById("recordList");
const saveBox = document.getElementById("saveBox");
const storySourcePill = document.getElementById("storySourcePill");
const saveDraftButton = document.getElementById("saveDraftButton");
const publishStoryButton = document.getElementById("publishStoryButton");

const noteModalBackdrop = document.getElementById("noteModalBackdrop");
const noteModalMeta = document.getElementById("noteModalMeta");
const noteModalTitle = document.getElementById("noteModalTitle");
const noteModalBody = document.getElementById("noteModalBody");
const noteModalClose = document.getElementById("noteModalClose");

let currentUser = null;
let draft = null;
let authMode = null;
let renderedNotes = [];

function escapeHtml(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function draftIdFromPath() {
    const match = window.location.pathname.match(/\/site\/drafts\/([^/]+)\/?$/);
    return match ? decodeURIComponent(match[1]) : null;
}

function loadDraft() {
    const draftId = draftIdFromPath();
    if (!draftId) {
        return null;
    }
    try {
        const raw = sessionStorage.getItem(`eirStoriesDraft:${draftId}`);
        if (!raw) {
            return null;
        }
        const parsed = JSON.parse(raw);
        return {
            storyTitle: "",
            storyText: "",
            ...parsed,
        };
    } catch {
        return null;
    }
}

function saveDraftState() {
    if (!draft?.id) {
        return;
    }
    sessionStorage.setItem(`eirStoriesDraft:${draft.id}`, JSON.stringify(draft));
}

async function api(url, options = {}) {
    const endpoint = API_BASE ? new URL(url, API_BASE).toString() : url;
    const response = await fetch(endpoint, {
        credentials: "same-origin",
        ...options,
        headers: {
            ...(options.body instanceof FormData ? {} : { "content-type": "application/json" }),
            ...(options.headers || {}),
        },
    });
    const text = await response.text();
    let payload = {};
    if (text) {
        payload = JSON.parse(text);
    }
    if (!response.ok) {
        throw new Error(payload.error || "Request failed");
    }
    return payload;
}

async function loadSession() {
    try {
        const payload = await api("/api/me");
        currentUser = payload.user;
    } catch {
        currentUser = null;
    }
}

function renderEmptyState() {
    viewerRoot.classList.add("hidden");
    emptyState.classList.remove("hidden");
}

function summarize(text, maxLength = 140) {
    const cleaned = String(text || "").replace(/\s+/g, " ").trim();
    if (cleaned.length <= maxLength) {
        return cleaned;
    }
    return `${cleaned.slice(0, maxLength).trim()}...`;
}

function parseStoryText(text) {
    const notes = [];
    const paragraphs = [];
    const lines = String(text || "").split(/\n{2,}/).map((part) => part.trim()).filter(Boolean);
    for (const part of lines) {
        const noteMatch = part.match(/^\/note\s+([^|]+)\|\s*(.+)$/is);
        if (noteMatch) {
            const note = {
                id: `note-${notes.length + 1}`,
                title: noteMatch[1].trim(),
                body: noteMatch[2].trim(),
                visibility: "private",
            };
            notes.push(note);
            paragraphs.push({ type: "note", noteId: note.id, title: note.title });
        } else {
            paragraphs.push({ type: "paragraph", text: part });
        }
    }
    return { notes, paragraphs };
}

function renderPreview() {
    const parsed = parseStoryText(draft.storyText);
    renderedNotes = parsed.notes;
    previewTitle.textContent = draft.storyTitle.trim() || "Untitled story";
    previewBody.innerHTML = parsed.paragraphs.length
        ? parsed.paragraphs.map((block) => {
            if (block.type === "note") {
                const note = parsed.notes.find((entry) => entry.id === block.noteId);
                return `
                    <div class="inline-note-card">
                        <div class="inline-note-card__top">
                            <div class="inline-note-card__meta">
                                <span class="inline-note-card__eyebrow">Inline note</span>
                                <span class="visibility-pill visibility-pill--private">private</span>
                            </div>
                            <button class="inline-note-card__action" type="button" data-note-id="${escapeHtml(block.noteId)}">Open note</button>
                        </div>
                        <h3 class="inline-note-card__title">${escapeHtml(block.title)}</h3>
                        <p class="inline-note-card__text">${escapeHtml(summarize(note?.body || "", 180))}</p>
                    </div>
                `;
            }
            return `<p>${escapeHtml(block.text)}</p>`;
        }).join("")
        : `<p>Start writing. This preview will read like the public story page once you decide what to publish.</p>`;

    previewBody.querySelectorAll("[data-note-id]").forEach((node) => {
        node.addEventListener("click", () => {
            const note = renderedNotes.find((entry) => entry.id === node.getAttribute("data-note-id"));
            if (note) {
                openNoteModal(note);
            }
        });
    });
}

function insertNoteCommand(example) {
    const noteTitle = example.summary || example.category || "Record note";
    const noteBody = example.details || [example.provider, example.entry_date].filter(Boolean).join(" • ") || "Add the relevant detail here.";
    const command = `/note ${noteTitle} | ${noteBody}`;
    const current = bodyInput.value.trim();
    draft.storyText = current ? `${current}\n\n${command}` : command;
    bodyInput.value = draft.storyText;
    saveDraftState();
    renderPreview();
}

function renderRecordList() {
    const examples = (draft.preview?.examples || []).slice(0, 6);
    recordList.innerHTML = examples.length
        ? examples.map((example, index) => `
            <div class="record-item">
                <div class="record-item__body">
                    <h3 class="record-item__title">${escapeHtml(example.summary)}</h3>
                    <div class="record-item__meta">
                        <span class="visibility-pill visibility-pill--private">private</span>
                        <span class="story-tool-pill">${escapeHtml(example.entry_date || example.public_date || "Undated")}</span>
                        <span class="story-tool-pill">${escapeHtml(example.category)}</span>
                    </div>
                </div>
                <button class="record-action" type="button" data-record-index="${index}">Insert /note</button>
            </div>
        `).join("")
        : `<div class="record-item"><div class="record-item__body"><h3 class="record-item__title">No medical notes attached</h3><div class="field-note">This story can stand on its own. Add a record later if you want supporting notes or references.</div></div></div>`;

    recordList.querySelectorAll("[data-record-index]").forEach((node) => {
        node.addEventListener("click", () => {
            const index = Number(node.getAttribute("data-record-index"));
            const example = (draft.preview?.examples || [])[index];
            if (example) {
                insertNoteCommand(example);
            }
        });
    });
}

function openNoteModal(note) {
    noteModalMeta.innerHTML = `
        <span class="visibility-pill visibility-pill--private">private note</span>
        <span class="story-tool-pill">inline reference</span>
    `;
    noteModalTitle.textContent = note.title;
    noteModalBody.innerHTML = `
        <p>${escapeHtml(note.body)}</p>
        <p class="field-note">This note is embedded in the story as supporting context. It stays private unless you choose to expose notes later.</p>
    `;
    noteModalBackdrop.classList.remove("hidden");
    noteModalBackdrop.setAttribute("aria-hidden", "false");
}

function closeNoteModal() {
    noteModalBackdrop.classList.add("hidden");
    noteModalBackdrop.setAttribute("aria-hidden", "true");
}

async function persistDraftImport() {
    if (!draft.rawText) {
        return null;
    }
    const formData = new FormData();
    const fileName = draft.preview?.filename || "health-record.eir";
    formData.append("file", new Blob([draft.rawText], { type: "text/plain" }), fileName);
    const payload = await api("/api/health/imports", { method: "POST", body: formData });
    return payload.import;
}

async function createStory(status) {
    const title = draft.storyTitle.trim() || "Untitled story";
    const storyText = draft.storyText.trim();
    if (!storyText) {
        throw new Error("Write some of your story first.");
    }
    return api("/api/stories", {
        method: "POST",
        body: JSON.stringify({
            title,
            story_text: storyText,
            status,
            evidence_level: draft.preview ? "Record-supported" : "Narrative-only",
        }),
    });
}

function renderAuthFields() {
    if (!authMode) {
        return "";
    }
    if (authMode === "login") {
        return `
            <div class="auth-fields">
                <input id="loginEmail" type="email" placeholder="Email">
                <input id="loginPassword" type="password" placeholder="Password">
                <button class="button button--primary" id="loginButton" type="button">Log in</button>
            </div>
        `;
    }
    return `
        <div class="auth-fields">
            <input id="signupEmail" type="email" placeholder="Email">
            <input id="signupPassword" type="password" placeholder="Password">
            <input id="signupDisplayName" type="text" placeholder="Display name">
            <input id="signupCountry" type="text" placeholder="Country">
            <input id="signupConcern" type="text" placeholder="Primary condition or concern">
            <button class="button button--primary" id="signupButton" type="button">Create account</button>
        </div>
    `;
}

function renderSaveBox() {
    if (currentUser) {
        saveBox.innerHTML = `
            <div class="field-note">Signed in as <strong>${escapeHtml(currentUser.display_name)}</strong>. New stories start private.</div>
            <div id="saveMessage" class="field-note"></div>
        `;
        saveDraftButton.textContent = "Save draft";
        publishStoryButton.textContent = "Publish story";
        saveDraftButton.disabled = false;
        publishStoryButton.disabled = false;
        return;
    }

    saveBox.innerHTML = `
        <div class="field-note">This draft stays on this device unless you save it.</div>
        <div class="story-tools">
            <button class="button button--secondary" id="showLoginButton" type="button">Log in</button>
            <button class="button button--secondary" id="showSignupButton" type="button">Create account</button>
        </div>
        ${renderAuthFields()}
        <div id="authMessage" class="field-note"></div>
    `;

    document.getElementById("showLoginButton").addEventListener("click", () => {
        authMode = "login";
        renderSaveBox();
    });
    document.getElementById("showSignupButton").addEventListener("click", () => {
        authMode = "signup";
        renderSaveBox();
    });

    if (authMode === "login") {
        document.getElementById("loginButton").addEventListener("click", async () => {
            const authMessage = document.getElementById("authMessage");
            try {
                await api("/api/auth/login", {
                    method: "POST",
                    body: JSON.stringify({
                        email: document.getElementById("loginEmail").value,
                        password: document.getElementById("loginPassword").value,
                    }),
                });
                await loadSession();
                renderSaveBox();
            } catch (error) {
                authMessage.textContent = error.message;
            }
        });
    }

    if (authMode === "signup") {
        document.getElementById("signupButton").addEventListener("click", async () => {
            const authMessage = document.getElementById("authMessage");
            try {
                await api("/api/auth/signup", {
                    method: "POST",
                    body: JSON.stringify({
                        email: document.getElementById("signupEmail").value,
                        password: document.getElementById("signupPassword").value,
                        display_name: document.getElementById("signupDisplayName").value,
                        country: document.getElementById("signupCountry").value,
                        primary_concern: document.getElementById("signupConcern").value,
                    }),
                });
                await loadSession();
                renderSaveBox();
            } catch (error) {
                authMessage.textContent = error.message;
            }
        });
    }
}

async function handleSave(status) {
    if (!currentUser) {
        authMode = "login";
        renderSaveBox();
        const authMessage = document.getElementById("authMessage");
        if (authMessage) {
            authMessage.textContent = status === "public"
                ? "Log in or create an account before publishing."
                : "Log in or create an account before saving this draft.";
        }
        const loginEmail = document.getElementById("loginEmail");
        if (loginEmail) {
            loginEmail.focus();
        }
        return;
    }
    const message = document.getElementById("saveMessage");
    const clickedButton = status === "public" ? publishStoryButton : saveDraftButton;
    const idleLabel = status === "public" ? "Publish story" : "Save draft";
    if (message) {
        message.textContent = status === "public" ? "Publishing..." : "Saving draft...";
    }
    clickedButton.disabled = true;
    clickedButton.textContent = status === "public" ? "Publishing..." : "Saving...";
    try {
        await persistDraftImport();
        const payload = await createStory(status);
        if (message) {
            message.textContent = status === "public"
                ? "Story published."
                : "Draft saved privately.";
        }
        sessionStorage.removeItem(`eirStoriesDraft:${draft.id}`);
        if (status === "private") {
            clickedButton.textContent = "Saved";
            window.setTimeout(() => {
                clickedButton.disabled = false;
                clickedButton.textContent = idleLabel;
            }, 1200);
            return;
        }
        if (status === "public" && payload.story?.slug) {
            window.setTimeout(() => {
                window.location.href = `${API_BASE || ""}/site/stories/`;
            }, 800);
        }
    } catch (error) {
        if (message) {
            message.textContent = error.message;
        }
        clickedButton.disabled = false;
        clickedButton.textContent = idleLabel;
    }
}

function bindEditor() {
    titleInput.value = draft.storyTitle || "";
    bodyInput.value = draft.storyText || "";
    titleInput.addEventListener("input", (event) => {
        draft.storyTitle = event.currentTarget.value;
        saveDraftState();
        renderPreview();
    });
    bodyInput.addEventListener("input", (event) => {
        draft.storyText = event.currentTarget.value;
        saveDraftState();
        renderPreview();
    });
}

function render() {
    if (!draft) {
        renderEmptyState();
        return;
    }
    viewerRoot.classList.remove("hidden");
    emptyState.classList.add("hidden");
    storySourcePill.textContent = draft.preview?.source || "Story only";
    bindEditor();
    renderPreview();
    renderRecordList();
    renderSaveBox();
}

noteModalClose.addEventListener("click", closeNoteModal);
noteModalBackdrop.addEventListener("click", (event) => {
    if (event.target === noteModalBackdrop) {
        closeNoteModal();
    }
});
document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
        closeNoteModal();
    }
});

saveDraftButton.addEventListener("click", () => handleSave("private"));
publishStoryButton.addEventListener("click", () => handleSave("public"));

async function init() {
    draft = loadDraft();
    await loadSession();
    render();
}

init();
