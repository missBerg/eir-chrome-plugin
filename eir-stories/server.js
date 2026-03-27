const path = require("path");

const cookieParser = require("cookie-parser");
const express = require("express");

const {
    addComment,
    authenticateUser,
    createDatabase,
    createMessage,
    createSession,
    createStory,
    createUser,
    deleteSession,
    getFeedSnapshot,
    getHomeSnapshot,
    getProfileBySlug,
    getStoryBySlug,
    getUserBySessionToken,
    listMessagesForUser,
    listProfiles,
    listStories,
    listStoriesForUser,
    listStoryComments,
    toggleFollow,
} = require("./src/database");
const {
    renderFeed,
    renderHome,
    renderMessagesPage,
    renderProfilePage,
    renderProfilesIndex,
    renderSignup,
    renderStoriesIndex,
    renderStoryPage,
} = require("./src/views");

const app = express();
const db = createDatabase();
const port = Number(process.env.PORT || 4180);
const sessionCookieName = "eir_stories_session";

app.use(express.urlencoded({ extended: false, limit: "1mb" }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, "docs"), { extensions: ["html"] }));

app.use((req, res, next) => {
    const token = req.cookies[sessionCookieName];
    req.currentUser = getUserBySessionToken(db, token);
    next();
});

function setSessionCookie(res, session) {
    res.cookie(sessionCookieName, session.token, {
        httpOnly: true,
        sameSite: "lax",
        secure: false,
        expires: new Date(session.expiresAt),
    });
}

function clearSessionCookie(res) {
    res.clearCookie(sessionCookieName);
}

function requireUser(req, res, next) {
    if (!req.currentUser) {
        return res.redirect("/?error=" + encodeURIComponent("Log in or create an account to use that part of the network."));
    }
    return next();
}

function readMessage(req, key) {
    return typeof req.query[key] === "string" ? req.query[key] : "";
}

app.get("/health", (_req, res) => {
    res.json({ ok: true });
});

app.get("/", (req, res) => {
    if (req.currentUser) {
        return res.redirect("/feed");
    }
    return res.send(renderHome({
        snapshot: getHomeSnapshot(db),
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.post("/login", (req, res) => {
    const user = authenticateUser(db, req.body.email, req.body.password);
    if (!user) {
        return res.redirect("/?error=" + encodeURIComponent("That email and password combination did not work."));
    }
    const session = createSession(db, user.id);
    setSessionCookie(res, session);
    return res.redirect(req.body.redirectTo || "/feed");
});

app.post("/logout", (req, res) => {
    deleteSession(db, req.cookies[sessionCookieName]);
    clearSessionCookie(res);
    return res.redirect("/?notice=" + encodeURIComponent("You have been logged out."));
});

app.get("/create/", (req, res) => {
    if (req.currentUser) {
        return res.redirect("/feed");
    }
    return res.send(renderSignup({
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.post("/signup", (req, res) => {
    try {
        const user = createUser(db, {
            email: req.body.email,
            password: req.body.password,
            displayName: req.body.displayName,
            country: req.body.country,
            primaryConcern: req.body.primaryConcern,
            messagingPolicy: req.body.messagingPolicy,
            conditions: String(req.body.conditions || "").split(",").map((item) => item.trim()).filter(Boolean),
            symptomThemes: String(req.body.symptoms || "").split(",").map((item) => item.trim()).filter(Boolean),
            bio: String(req.body.storyText || "").trim().split(/\n+/)[0] || "A new Eir Stories member.",
        });
        if (String(req.body.storyTitle || "").trim() && String(req.body.storyText || "").trim()) {
            createStory(db, user.id, {
                title: req.body.storyTitle,
                storyText: req.body.storyText,
                summary: req.body.summary,
                evidenceLevel: req.body.evidenceLevel,
                country: req.body.country,
                conditions: req.body.conditions,
                symptoms: req.body.symptoms,
            });
        }
        const session = createSession(db, user.id);
        setSessionCookie(res, session);
        return res.redirect("/feed?notice=" + encodeURIComponent("Your account is live."));
    } catch (error) {
        return res.redirect("/create/?error=" + encodeURIComponent(error.message));
    }
});

app.get("/feed", requireUser, (req, res) => {
    return res.send(renderFeed({
        user: req.currentUser,
        snapshot: getFeedSnapshot(db, req.currentUser.id),
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.post("/stories", requireUser, (req, res) => {
    try {
        const slug = createStory(db, req.currentUser.id, req.body);
        return res.redirect(`/stories/${encodeURIComponent(slug)}?notice=` + encodeURIComponent("Story published."));
    } catch (error) {
        return res.redirect("/feed?error=" + encodeURIComponent(error.message));
    }
});

app.get("/stories/", (req, res) => {
    return res.send(renderStoriesIndex({
        user: req.currentUser,
        stories: listStories(db),
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.get("/stories/:slug", (req, res) => {
    const story = getStoryBySlug(db, req.params.slug, req.currentUser?.id);
    if (!story) {
        return res.status(404).send("Story not found.");
    }
    return res.send(renderStoryPage({
        user: req.currentUser,
        story,
        comments: listStoryComments(db, story.id),
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.post("/stories/:slug/comments", requireUser, (req, res) => {
    try {
        addComment(db, req.params.slug, req.currentUser.id, req.body.body);
        return res.redirect(`/stories/${encodeURIComponent(req.params.slug)}?notice=` + encodeURIComponent("Comment posted.") + "#comments");
    } catch (error) {
        return res.redirect(`/stories/${encodeURIComponent(req.params.slug)}?error=` + encodeURIComponent(error.message) + "#comments");
    }
});

app.get("/profiles/", (req, res) => {
    return res.send(renderProfilesIndex({
        user: req.currentUser,
        profiles: listProfiles(db, req.currentUser?.id),
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.get("/profiles/:slug", (req, res) => {
    const profile = getProfileBySlug(db, req.params.slug, req.currentUser?.id);
    if (!profile) {
        return res.status(404).send("Profile not found.");
    }
    return res.send(renderProfilePage({
        user: req.currentUser,
        profile,
        stories: listStoriesForUser(db, profile.id),
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.post("/profiles/:slug/follow", requireUser, (req, res) => {
    try {
        const isFollowing = toggleFollow(db, req.currentUser.id, req.params.slug);
        const notice = isFollowing ? "Profile followed." : "Profile unfollowed.";
        return res.redirect(`/profiles/${encodeURIComponent(req.params.slug)}?notice=` + encodeURIComponent(notice));
    } catch (error) {
        return res.redirect(`/profiles/${encodeURIComponent(req.params.slug)}?error=` + encodeURIComponent(error.message));
    }
});

app.post("/profiles/:slug/messages", requireUser, (req, res) => {
    try {
        createMessage(db, req.currentUser.id, req.params.slug, req.body.body);
        return res.redirect(`/profiles/${encodeURIComponent(req.params.slug)}?notice=` + encodeURIComponent("Message sent."));
    } catch (error) {
        return res.redirect(`/profiles/${encodeURIComponent(req.params.slug)}?error=` + encodeURIComponent(error.message));
    }
});

app.get("/messages/", requireUser, (req, res) => {
    return res.send(renderMessagesPage({
        user: req.currentUser,
        messages: listMessagesForUser(db, req.currentUser.id),
        error: readMessage(req, "error"),
        notice: readMessage(req, "notice"),
    }));
});

app.listen(port, () => {
    console.log(`Eir Stories listening on http://localhost:${port}`);
});
