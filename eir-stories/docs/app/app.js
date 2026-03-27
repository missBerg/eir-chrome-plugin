const state = { me: null, imports: [], profile: null };

const authPanel = document.getElementById("authPanel");
const profilePanel = document.getElementById("profilePanel");
const importsPanel = document.getElementById("importsPanel");
const publicPreviewPanel = document.getElementById("publicPreviewPanel");
const messageBox = document.getElementById("messageBox");
const uploadButton = document.getElementById("uploadButton");
const logoutButton = document.getElementById("logoutButton");
const eirFileInput = document.getElementById("eirFile");
const selectedFileName = document.getElementById("selectedFileName");
const filePickerButton = document.getElementById("filePickerButton");
const storyOnlyButton = document.getElementById("storyOnlyButton");
const continueWritingButton = document.getElementById("continueWritingButton");
const storySeedTitle = document.getElementById("storySeedTitle");
const storySeedBody = document.getElementById("storySeedBody");
let uploadInFlight = false;

const API_BASE = (() => {
    const { protocol, hostname, port } = window.location;
    if ((hostname === "127.0.0.1" || hostname === "localhost") && port && port !== "4181") {
        return `${protocol}//127.0.0.1:4181`;
    }
    return "";
})();

function buildSiteUrl(path) {
    if (API_BASE) {
        return new URL(path, API_BASE).toString();
    }
    return path;
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
        try {
            payload = JSON.parse(text);
        } catch {
            throw new Error(response.ok ? "The server returned an unreadable response." : "The preview service could not be reached.");
        }
    }
    if (!response.ok) {
        throw new Error(payload.error || "Request failed");
    }
    return payload;
}

function escapeHtml(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function setMessage(message, isError = false) {
    messageBox.textContent = message || "";
    messageBox.style.color = isError ? "#b42318" : "var(--muted)";
}

function updateFileSelectionUi(file) {
    selectedFileName.textContent = file ? `${file.name} selected` : "No file selected yet.";
    uploadButton.disabled = !file || uploadInFlight;
}

function toggleAuthenticated(isAuthenticated) {
    authPanel.classList.add("hidden");
    profilePanel.classList.toggle("hidden", !isAuthenticated);
    importsPanel.classList.toggle("hidden", !isAuthenticated);
    publicPreviewPanel.classList.toggle("hidden", !isAuthenticated);
    logoutButton.classList.toggle("hidden", !isAuthenticated);
}

async function loadSession() {
    try {
        const payload = await api("/api/me");
        state.me = payload.user;
        toggleAuthenticated(true);
        await Promise.all([loadImports(), loadProfile()]);
    } catch {
        state.me = null;
        state.imports = [];
        state.profile = null;
        toggleAuthenticated(false);
        renderProfileSummary();
        renderImports();
        renderPublicPreview();
    }
}

async function loadImports() {
    state.imports = await api("/api/health/imports");
    renderImports();
}

async function loadProfile() {
    if (!state.me) {
        return;
    }
    state.profile = await api(`/api/profiles/${state.me.slug}`);
    renderProfileSummary();
    renderPublicPreview();
}

function renderProfileSummary() {
    const profile = state.profile?.profile;
    const profileSummary = document.getElementById("profileSummary");
    const prompts = document.getElementById("storyPrompts");
    if (!profile) {
        profileSummary.textContent = "";
        prompts.innerHTML = "";
        return;
    }

    profileSummary.innerHTML = `
        <strong>${escapeHtml(profile.display_name)}</strong><br>
        ${escapeHtml(profile.primary_concern || "Health journey")} • ${escapeHtml(profile.country || "Global")}<br>
        ${profile.conditions?.length ? escapeHtml(profile.conditions.join(", ")) : "No imported health themes yet."}
    `;

    const promptItems = state.imports.flatMap((entry) => entry.story_prompts || []).slice(0, 6);
    prompts.innerHTML = promptItems.length
        ? promptItems.map((prompt) => `<div class="prompt-item">${escapeHtml(prompt)}</div>`).join("")
        : `<div class="prompt-item">Add your health information to generate story prompts from the moments and patterns in your care journey.</div>`;
}

function renderImports() {
    const root = document.getElementById("importsList");
    if (!state.me) {
        root.innerHTML = "";
        return;
    }
    if (!state.imports.length) {
        root.innerHTML = `<div class="import-item">No health information added yet. Upload a file above to open it in the private viewer, then save it to your profile when you are ready.</div>`;
        return;
    }

    root.innerHTML = renderImportCards(state.imports, { interactive: true, includePrivateSummary: true });
    attachVisibilityHandlers(root);
}

function renderImportCards(entries, options) {
    const { interactive, includePrivateSummary } = options;
    return entries.map((entry) => `
        <article class="import-item">
            <div class="import-item__header">
                <div>
                    <strong>${escapeHtml(entry.filename)}</strong>
                    <div class="inline-note">${escapeHtml(entry.source)} • ${entry.record_count} records • latest ${escapeHtml(entry.latest_entry_date || "unknown")}</div>
                </div>
                <span class="pill">${escapeHtml(entry.privacy_level)}</span>
            </div>
            <div class="section-list">
                ${includePrivateSummary ? `<div class="section-item">
                    <div class="section-item__header">
                        <strong>Private profile summary</strong>
                        <span class="pill">private only</span>
                    </div>
                    <pre class="markdown-block">${escapeHtml(entry.private_health_md || "Private view unavailable")}</pre>
                </div>` : ""}
                ${entry.sections.map((section) => `
                    <div class="section-item">
                        <div class="section-item__header">
                            <div>
                                <strong>${escapeHtml(section.title)}</strong>
                                <div class="inline-note">${escapeHtml(section.section_key)}</div>
                            </div>
                            ${interactive ? `<select class="visibility-picker" data-kind="section" data-import-id="${entry.id}" data-item-id="${section.id}">
                                <option value="private" ${section.visibility === "private" ? "selected" : ""}>Private</option>
                                <option value="public" ${section.visibility === "public" ? "selected" : ""}>Public</option>
                            </select>` : `<span class="pill">${escapeHtml(section.visibility || "private")}</span>`}
                        </div>
                        <pre class="markdown-block">${escapeHtml(section.markdown)}</pre>
                    </div>
                `).join("")}
            </div>
            <div class="example-list">
                ${entry.examples.slice(0, 12).map((example) => `
                    <div class="example-item">
                        <div class="example-item__header">
                            <div>
                                <strong>${escapeHtml(example.category)} • ${escapeHtml(example.record_type)}</strong>
                                <div class="inline-note">${escapeHtml(example.entry_date || example.public_date || "Undated")} • ${escapeHtml(example.provider || "Healthcare provider")}</div>
                            </div>
                            ${interactive ? `<select class="visibility-picker" data-kind="example" data-import-id="${entry.id}" data-item-id="${example.id}">
                                <option value="private" ${example.visibility === "private" ? "selected" : ""}>Private</option>
                                <option value="public" ${example.visibility === "public" ? "selected" : ""}>Public</option>
                            </select>` : `<span class="pill">${escapeHtml(example.visibility || "private")}</span>`}
                        </div>
                        <div>${escapeHtml(example.summary)}</div>
                        ${example.details ? `<p class="inline-note">${escapeHtml(example.details)}</p>` : ""}
                        <div class="story-card__tags">
                            ${(example.tags || []).map((tag) => `<span class="pill">${escapeHtml(tag)}</span>`).join("")}
                        </div>
                    </div>
                `).join("")}
            </div>
        </article>
    `).join("");
}

function attachVisibilityHandlers(root) {
    root.querySelectorAll(".visibility-picker").forEach((node) => {
        node.addEventListener("change", async (event) => {
            const target = event.currentTarget;
            const importId = target.dataset.importId;
            const itemId = target.dataset.itemId;
            const kind = target.dataset.kind;
            try {
                await api(`/api/health/imports/${importId}/${kind === "section" ? "sections" : "examples"}/${itemId}/visibility`, {
                    method: "POST",
                    body: JSON.stringify({ visibility: target.value }),
                });
                await Promise.all([loadImports(), loadProfile()]);
                setMessage("Visibility updated.");
            } catch (error) {
                setMessage(error.message, true);
            }
        });
    });
}

function renderPublicPreview() {
    const preview = document.getElementById("publicPreview");
    if (!state.me) {
        preview.innerHTML = "";
        return;
    }
    const imports = state.profile?.health_imports || [];
    if (!imports.length) {
        preview.innerHTML = `<div class="import-item">Nothing is public yet. When you choose to share a section or example, it will appear here as part of your story.</div>`;
        return;
    }

    preview.innerHTML = imports.map((entry) => `
        <article class="import-item">
            <div class="import-item__header">
                <strong>${escapeHtml(entry.filename)}</strong>
                <span class="pill">public preview</span>
            </div>
            <pre class="markdown-block">${escapeHtml(entry.public_health_md || "")}</pre>
            <div class="example-list">
                ${entry.examples.map((example) => `
                    <div class="example-item">
                        <strong>${escapeHtml(example.category)} • ${escapeHtml(example.record_type)}</strong>
                        <div class="inline-note">${escapeHtml(example.public_date || "Undated")} • ${escapeHtml(example.provider || "Healthcare provider")}</div>
                        <div>${escapeHtml(example.summary)}</div>
                        ${example.details ? `<p class="inline-note">${escapeHtml(example.details)}</p>` : ""}
                    </div>
                `).join("")}
            </div>
        </article>
    `).join("");
}

function setUploading(isUploading) {
    uploadInFlight = isUploading;
    uploadButton.disabled = isUploading || !eirFileInput.files[0];
    eirFileInput.disabled = isUploading;
    filePickerButton.classList.toggle("file-picker__button--disabled", isUploading);
    filePickerButton.textContent = isUploading ? "Building your viewer..." : "Choose a health record file";
}

function storeDraft(payload) {
    const draftId = (window.crypto?.randomUUID?.() || `draft-${Date.now()}`);
    const draft = {
        id: draftId,
        createdAt: new Date().toISOString(),
        preview: payload.preview || null,
        rawText: payload.rawText || "",
        storyTitle: storySeedTitle?.value?.trim() || "",
        storyText: storySeedBody?.value?.trim() || "",
    };
    sessionStorage.setItem(`eirStoriesDraft:${draftId}`, JSON.stringify(draft));
    return draftId;
}

function handleStoryOnlyStart() {
    const draftId = storeDraft({});
    setMessage("Opening your writing page...");
    window.location.assign(buildSiteUrl(`/site/drafts/${draftId}/`));
}

async function handleUpload() {
    const file = eirFileInput.files[0];
    if (!file) {
        setMessage("Choose a health record file first.", true);
        return;
    }
    if (uploadInFlight) {
        return;
    }

    const rawText = await file.text();
    const formData = new FormData();
    formData.append("file", new Blob([rawText], { type: file.type || "text/plain" }), file.name);
    setUploading(true);
    setMessage("Building your private viewer...");
    try {
        const payload = await api("/api/health/preview", { method: "POST", body: formData });
        const draftId = storeDraft({ preview: payload.preview, rawText });
        eirFileInput.value = "";
        updateFileSelectionUi(null);
        window.location.href = buildSiteUrl(`/site/drafts/${draftId}/`);
    } catch (error) {
        setMessage(error.message, true);
    } finally {
        setUploading(false);
    }
}

document.getElementById("loginButton").addEventListener("click", async () => {
    try {
        await api("/api/auth/login", {
            method: "POST",
            body: JSON.stringify({
                email: document.getElementById("loginEmail").value,
                password: document.getElementById("loginPassword").value,
            }),
        });
        setMessage("Logged in.");
        await loadSession();
    } catch (error) {
        setMessage(error.message, true);
    }
});

document.getElementById("signupButton").addEventListener("click", async () => {
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
        setMessage("Account created.");
        await loadSession();
    } catch (error) {
        setMessage(error.message, true);
    }
});

document.getElementById("logoutButton").addEventListener("click", async () => {
    try {
        await api("/api/auth/logout", { method: "POST", body: JSON.stringify({}) });
        setMessage("Logged out.");
        await loadSession();
    } catch (error) {
        setMessage(error.message, true);
    }
});

document.getElementById("uploadForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    await handleUpload();
});

filePickerButton.addEventListener("click", () => {
    if (!uploadInFlight) {
        eirFileInput.click();
    }
});

storyOnlyButton.addEventListener("click", () => {
    if (!uploadInFlight) {
        handleStoryOnlyStart();
    }
});

continueWritingButton.addEventListener("click", () => {
    if (!uploadInFlight) {
        handleStoryOnlyStart();
    }
});

eirFileInput.addEventListener("change", async () => {
    const file = eirFileInput.files[0];
    updateFileSelectionUi(file);
    if (file) {
        await handleUpload();
    }
});

updateFileSelectionUi(null);
loadSession();
