function escapeHtml(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function renderMark() {
    return `<span class="brand__mark" aria-hidden="true"><img src="https://eir-design-system.netlify.app/icon-white.png" alt=""></span>`;
}

function renderLayout({ title, description, user, body, pathname = "/", notice = "", error = "" }) {
    const nav = user
        ? `
            <a href="/feed">Feed</a>
            <a href="/stories/">Stories</a>
            <a href="/profiles/">Profiles</a>
            <a href="/messages/">Messages</a>
            <a href="/profiles/${encodeURIComponent(user.slug)}">My profile</a>
            <form class="nav__form" method="post" action="/logout">
                <button class="nav__cta nav__cta--ghost" type="submit">Log out</button>
            </form>
        `
        : `
            <a href="/stories/">Stories</a>
            <a href="/profiles/">Profiles</a>
            <a href="/create/">Create account</a>
            <a class="nav__cta" href="/create/">Join now</a>
        `;

    const alerts = [error ? `<div class="shell flash flash--error">${escapeHtml(error)}</div>` : "", notice ? `<div class="shell flash flash--notice">${escapeHtml(notice)}</div>` : ""].join("");

    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${escapeHtml(title)}</title>
    <meta name="description" content="${escapeHtml(description)}">
    <meta name="theme-color" content="#fafaf7">
    <link rel="icon" href="https://eir-design-system.netlify.app/icon-teal.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="/stories-ui.css">
</head>
<body data-pathname="${escapeHtml(pathname)}">
    <header class="site-header">
        <div class="shell site-header__inner">
            <a class="brand" href="/" aria-label="Eir Stories home">
                ${renderMark()}
                <span><span class="brand__eyebrow">stories.eir.space</span><span class="brand__name">Eir Stories</span></span>
            </a>
            <nav class="nav" aria-label="Primary">
                ${nav}
            </nav>
        </div>
    </header>
    ${alerts}
    <main>${body}</main>
</body>
</html>`;
}

function formatDate(value) {
    try {
        return new Date(value).toLocaleDateString("en-GB", { year: "numeric", month: "short", day: "numeric" });
    } catch {
        return value;
    }
}

function initials(name) {
    return String(name || "")
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((part) => part[0])
        .join("")
        .toUpperCase() || "ES";
}

function renderStoryCards(stories) {
    return stories.map((story) => `
        <article class="story-card">
            <div class="story-card__author">
                <span class="author-dot">${escapeHtml(initials(story.authorName))}</span>
                <a href="/profiles/${encodeURIComponent(story.authorSlug)}">${escapeHtml(story.authorName)}</a>
            </div>
            <div class="story-card__meta">
                <span class="pill">${escapeHtml(story.evidence_level || story.evidenceLevel)}</span>
                <span class="pill">${escapeHtml(story.country)}</span>
                <span class="pill">${Number(story.commentCount || 0)} comments</span>
            </div>
            <div>
                <h3><a href="/stories/${encodeURIComponent(story.slug)}">${escapeHtml(story.title)}</a></h3>
                <p>${escapeHtml(story.summary)}</p>
            </div>
            <div class="story-card__tags">
                ${(story.conditions || []).map((tag) => `<span class="pill">${escapeHtml(tag)}</span>`).join("")}
                ${(story.symptoms || []).slice(0, 2).map((tag) => `<span class="pill">${escapeHtml(tag)}</span>`).join("")}
            </div>
            <div class="timeline-preview">
                ${(story.timeline || []).slice(0, 2).map((item) => `
                    <div class="timeline-preview__row">
                        <strong>${escapeHtml(item.date)}</strong>
                        <span>${escapeHtml(item.label)}</span>
                    </div>
                `).join("")}
            </div>
        </article>
    `).join("");
}

function renderProfileCards(profiles) {
    return profiles.map((profile) => `
        <article class="surface profile-mini-card">
            <div class="profile-mini-card__head">
                <div class="profile-avatar">${escapeHtml(initials(profile.display_name || profile.displayName))}</div>
                <div>
                    <h3><a href="/profiles/${encodeURIComponent(profile.slug)}">${escapeHtml(profile.display_name || profile.displayName)}</a></h3>
                    <p>${escapeHtml(profile.primary_concern || "Health journey")} • ${escapeHtml(profile.country || "Global")}</p>
                </div>
            </div>
            <p>${escapeHtml(profile.bio)}</p>
            <div class="profile-stats">
                <span class="pill">${Number(profile.followerCount || 0)} followers</span>
                <span class="pill">${Number(profile.storyCount || 0)} stories</span>
            </div>
        </article>
    `).join("");
}

function renderHome({ snapshot, error = "", notice = "" }) {
    const leadStory = snapshot.latestStories[0];
    const secondStory = snapshot.latestStories[1];
    const thirdStory = snapshot.latestStories[2];
    const featuredProfiles = snapshot.featuredProfiles;

    return renderLayout({
        title: "Eir Stories",
        description: "Share your health journey. Help someone else navigate theirs.",
        pathname: "/",
        error,
        notice,
        body: `
            <section class="page-hero home-hero">
                <div class="shell home-hero__wrap">
                    <div>
                        <div class="eyebrow"><span class="eyebrow__dot" aria-hidden="true"></span>The first social network for health journeys</div>
                        <h1>Share your health journey. Help someone else navigate theirs.</h1>
                        <p class="home-hero__lede">Eir Stories is a place to build a health profile, publish your own story, and connect with people living through similar patterns. Stories come first. Health information can support them, but it never has to overpower them.</p>
                        <div class="home-hero__actions">
                            <a class="button button--primary" href="/create/">Create account</a>
                            <a class="button button--secondary" href="/stories/">Browse public stories</a>
                        </div>
                    </div>
                    <section class="surface home-network" aria-label="Public activity">
                        <div class="home-network__cluster">
                            <article class="home-note__profile">
                                <div class="home-note__header">
                                    <div class="home-note__avatar">${escapeHtml(initials(featuredProfiles[0]?.display_name || featuredProfiles[0]?.displayName || "ES"))}</div>
                                    <div>
                                        <div class="home-note__name">${escapeHtml(featuredProfiles[0]?.display_name || featuredProfiles[0]?.displayName || "Mika")}</div>
                                        <div class="home-note__meta">${escapeHtml(featuredProfiles[0]?.primary_concern || "Migraine")} • ${escapeHtml(featuredProfiles[0]?.country || "Sweden")}</div>
                                    </div>
                                </div>
                                <p>${escapeHtml(featuredProfiles[0]?.bio || "")}</p>
                                <div class="home-note__row">
                                    <span class="pill">${Number(featuredProfiles[0]?.followerCount || 0)} followers</span>
                                    <span class="pill">${Number(featuredProfiles[0]?.storyCount || 0)} public stories</span>
                                </div>
                            </article>
                            <article class="home-note__story">
                                <div>
                                    <div class="home-note__meta">Latest public story</div>
                                    <h3><a href="/stories/${encodeURIComponent(leadStory.slug)}">${escapeHtml(leadStory.title)}</a></h3>
                                    <p>${escapeHtml(leadStory.summary)}</p>
                                </div>
                                <div class="home-note__footer">
                                    <span class="pill">${escapeHtml(leadStory.country)}</span>
                                    <span class="pill">${escapeHtml(leadStory.evidence_level || leadStory.evidenceLevel)}</span>
                                </div>
                            </article>
                        </div>
                        <article class="home-note__thread">
                            <strong>Recent reply</strong>
                            <p>${escapeHtml(snapshot.latestComment?.body || "People are already responding to stories with timelines, care tips, and recognition.")}</p>
                            <div class="home-note__meta" style="margin-top:8px;">${escapeHtml(snapshot.latestComment?.author_name || "Aino")} on ${escapeHtml(snapshot.latestComment?.story_title || "a public story")}</div>
                        </article>
                        <article class="home-note__dm">
                            <strong>Private messages with boundaries</strong>
                            <p>Profiles can open or close messages. People can share a story publicly without making themselves permanently reachable.</p>
                        </article>
                        <div class="home-note__row">
                            ${secondStory ? `<span class="pill"><a href="/stories/${encodeURIComponent(secondStory.slug)}">${escapeHtml(secondStory.title)}</a></span>` : ""}
                            ${thirdStory ? `<span class="pill"><a href="/stories/${encodeURIComponent(thirdStory.slug)}">${escapeHtml(thirdStory.title)}</a></span>` : ""}
                        </div>
                    </section>
                    <section class="surface auth-card" aria-label="Log in">
                        <div>
                            <div class="brand__eyebrow">Log in</div>
                            <h2>Come back to your stories, follows, and messages.</h2>
                            <p>Use one account for your profile, public stories, saved journeys, comments, and inbox.</p>
                        </div>
                        <form class="auth-card__form" method="post" action="/login">
                            <input type="hidden" name="redirectTo" value="/feed">
                            <label class="auth-card__field">
                                <span class="sr-only">Email</span>
                                <input type="email" name="email" autocomplete="email" placeholder="Email" required>
                            </label>
                            <label class="auth-card__field">
                                <span class="sr-only">Password</span>
                                <input type="password" name="password" autocomplete="current-password" placeholder="Password" required>
                            </label>
                            <button class="button auth-card__submit" type="submit">Log in</button>
                        </form>
                        <a class="auth-card__forgot" href="/create/">Create a new account instead</a>
                        <div class="auth-card__divider"></div>
                        <div class="auth-card__meta">
                            <span class="pill">Stories first</span>
                            <span class="pill">Health context optional</span>
                            <span class="pill">Profiles, comments, DMs</span>
                        </div>
                    </section>
                </div>
            </section>
            <section class="home-section">
                <div class="shell">
                    <div class="home-section__head">
                        <h2>Public stories and real profiles, not anonymous fragments.</h2>
                        <p>People should be able to recognize themselves in a story, follow the author if they want, leave a thoughtful comment, or ask to connect. That is what makes this a network instead of a pile of posts.</p>
                    </div>
                    <div class="simple-grid">
                        ${renderProfileCards(featuredProfiles)}
                    </div>
                </div>
            </section>
        `,
    });
}

function renderSignup({ error = "", notice = "" }) {
    return renderLayout({
        title: "Create account | Eir Stories",
        description: "Create an Eir Stories account and publish your first health journey.",
        pathname: "/create/",
        error,
        notice,
        body: `
            <section class="page-hero">
                <div class="shell">
                    <div class="eyebrow"><span class="eyebrow__dot" aria-hidden="true"></span>Create your account</div>
                    <h1>Start with your story.</h1>
                    <p class="lede">You can add conditions, symptoms, medications, or evidence if they help. But the first thing we ask is the one that matters most: what happened?</p>
                </div>
            </section>
            <section>
                <div class="shell signup-layout">
                    <div class="signup-main">
                        <form class="surface signup-card" method="post" action="/signup">
                            <h2>Create your profile</h2>
                            <div class="signup-grid">
                                <label class="field">Email
                                    <input type="email" name="email" autocomplete="email" required>
                                </label>
                                <label class="field">Password
                                    <input type="password" name="password" autocomplete="new-password" minlength="8" required>
                                </label>
                                <label class="field">Display name
                                    <input type="text" name="displayName" placeholder="How people will know you" required>
                                </label>
                                <label class="field">Country
                                    <input type="text" name="country" placeholder="Sweden">
                                </label>
                                <label class="field">Primary condition or concern
                                    <input type="text" name="primaryConcern" placeholder="Migraine, Long COVID, undiagnosed">
                                </label>
                                <label class="field">Messages
                                    <select name="messagingPolicy">
                                        <option>Open to messages</option>
                                        <option>Open to thoughtful requests</option>
                                        <option>Closed to new messages</option>
                                    </select>
                                </label>
                            </div>
                            <h3>First story</h3>
                            <div class="signup-grid">
                                <label class="field">Story title
                                    <input type="text" name="storyTitle" placeholder="The title people will see on your first story">
                                </label>
                                <label class="field">What happened?
                                    <textarea name="storyText" placeholder="Write the beginning of your story. What happened, how did it unfold, and what do you wish someone else had understood earlier?"></textarea>
                                </label>
                                <label class="field">Short summary
                                    <textarea name="summary" placeholder="A short summary for the feed and profile."></textarea>
                                </label>
                                <label class="field">Evidence level
                                    <select name="evidenceLevel">
                                        <option>Narrative only</option>
                                        <option>Narrative + structured context</option>
                                        <option>Narrative + record-backed evidence</option>
                                    </select>
                                </label>
                                <label class="field">Conditions
                                    <input type="text" name="conditions" placeholder="Comma-separated">
                                </label>
                                <label class="field">Symptoms
                                    <input type="text" name="symptoms" placeholder="Comma-separated">
                                </label>
                            </div>
                            <div style="margin-top:16px;">
                                <button class="button button--primary signup-cta" type="submit">Create account</button>
                            </div>
                        </form>
                    </div>
                    <aside class="signup-side">
                        <article class="surface signup-card">
                            <h3>What happens next</h3>
                            <ul>
                                <li>You get a public health profile.</li>
                                <li>You can publish stories, not just posts.</li>
                                <li>Other people can follow, comment, and message within your boundaries.</li>
                                <li>You can add structured health context only where it helps.</li>
                            </ul>
                        </article>
                    </aside>
                </div>
            </section>
        `,
    });
}

function renderFeed({ user, snapshot, error = "", notice = "" }) {
    return renderLayout({
        title: "Feed | Eir Stories",
        description: "Your health story feed on Eir Stories.",
        pathname: "/feed",
        user,
        error,
        notice,
        body: `
            <section class="page-hero">
                <div class="shell">
                    <div class="eyebrow"><span class="eyebrow__dot" aria-hidden="true"></span>Your network</div>
                    <h1>${escapeHtml(user.display_name)}’s health story feed.</h1>
                    <p class="lede">Write new stories, follow people with similar experiences, reply to public journeys, and keep private messages within the boundaries people chose for their profile.</p>
                </div>
            </section>
            <section>
                <div class="shell app-layout">
                    <div class="app-main">
                        <form class="surface composer-card app-composer" method="post" action="/stories">
                            <h2>Write a new story</h2>
                            <div class="signup-grid">
                                <label class="field">Story title
                                    <input type="text" name="title" placeholder="A title that tells people what this story is about" required>
                                </label>
                                <label class="field field--full">What happened?
                                    <textarea name="storyText" placeholder="Start with what happened. Describe the pattern, the uncertainty, the turning points, and what you want someone else to understand." required></textarea>
                                </label>
                                <label class="field">Summary
                                    <textarea name="summary" placeholder="Short feed summary"></textarea>
                                </label>
                                <label class="field">Evidence level
                                    <select name="evidenceLevel">
                                        <option>Narrative only</option>
                                        <option>Narrative + structured context</option>
                                        <option>Narrative + record-backed evidence</option>
                                    </select>
                                </label>
                                <label class="field">Country
                                    <input type="text" name="country" value="${escapeHtml(user.country)}">
                                </label>
                                <label class="field">Journey stage
                                    <select name="journeyStage">
                                        <option>Ongoing</option>
                                        <option>Improving</option>
                                        <option>Recently diagnosed</option>
                                        <option>Managing a stable pattern</option>
                                    </select>
                                </label>
                                <label class="field">Conditions
                                    <input type="text" name="conditions" placeholder="Comma-separated">
                                </label>
                                <label class="field">Symptoms
                                    <input type="text" name="symptoms" placeholder="Comma-separated">
                                </label>
                                <label class="field">Medications
                                    <input type="text" name="medications" placeholder="Comma-separated">
                                </label>
                            </div>
                            <div class="composer-actions">
                                <button class="button button--primary" type="submit">Publish story</button>
                            </div>
                        </form>
                        <div class="stories-grid stories-grid--feed">
                            ${renderStoryCards(snapshot.stories)}
                        </div>
                    </div>
                    <aside class="app-side">
                        <article class="sidebar-card">
                            <h3>Your profile</h3>
                            <div class="profile-mini-card__head">
                                <div class="profile-avatar">${escapeHtml(initials(user.display_name))}</div>
                                <div>
                                    <strong>${escapeHtml(user.display_name)}</strong>
                                    <p>${escapeHtml(user.primary_concern || "Health journey")} • ${escapeHtml(user.country || "Global")}</p>
                                </div>
                            </div>
                            <p>${escapeHtml(user.bio || "Your profile is ready for stories, comments, follows, and messages.")}</p>
                            <a class="button button--secondary" href="/profiles/${encodeURIComponent(user.slug)}">View profile</a>
                        </article>
                        <article class="sidebar-card">
                            <h3>Inbox</h3>
                            <div class="message-list">
                                ${snapshot.inbox.length ? snapshot.inbox.map((message) => `
                                    <div class="message-item">
                                        <strong>${escapeHtml(message.senderName)}</strong>
                                        <p>${escapeHtml(message.body)}</p>
                                    </div>
                                `).join("") : "<p>No messages yet.</p>"}
                            </div>
                            <a class="button button--secondary" href="/messages/">Open messages</a>
                        </article>
                        <article class="sidebar-card">
                            <h3>Suggested profiles</h3>
                            <div class="suggestion-list">
                                ${snapshot.suggestions.map((profile) => `
                                    <div class="suggestion-item">
                                        <div>
                                            <strong><a href="/profiles/${encodeURIComponent(profile.slug)}">${escapeHtml(profile.display_name || profile.displayName)}</a></strong>
                                            <p>${escapeHtml(profile.primary_concern)} • ${escapeHtml(profile.country)}</p>
                                        </div>
                                    </div>
                                `).join("")}
                            </div>
                        </article>
                    </aside>
                </div>
            </section>
        `,
    });
}

function renderStoriesIndex({ stories, user, error = "", notice = "" }) {
    return renderLayout({
        title: "Stories | Eir Stories",
        description: "Browse public health journeys on Eir Stories.",
        pathname: "/stories/",
        user,
        error,
        notice,
        body: `
            <section class="page-hero">
                <div class="shell">
                    <div class="eyebrow"><span class="eyebrow__dot" aria-hidden="true"></span>Public health journeys</div>
                    <h1>Stories people can actually read, save, and respond to.</h1>
                    <p class="lede">Some stories stay narrative-only. Some carry conditions, symptoms, medications, or selected evidence. The point is not to force structure. It is to make stories legible enough to help someone else.</p>
                </div>
            </section>
            <section>
                <div class="shell">
                    <div class="stories-grid">
                        ${renderStoryCards(stories)}
                    </div>
                </div>
            </section>
        `,
    });
}

function renderStoryPage({ story, comments, user, error = "", notice = "" }) {
    const followAction = user && user.slug !== story.authorSlug
        ? `
            <form method="post" action="/profiles/${encodeURIComponent(story.authorSlug)}/follow">
                <button class="action-chip" type="submit">${story.isFollowingAuthor ? "Following" : "Follow"}</button>
            </form>
        `
        : "";
    const messageAction = user && user.slug !== story.authorSlug
        ? `<a class="action-chip" href="/profiles/${encodeURIComponent(story.authorSlug)}#message-form">Message</a>`
        : "";
    const commentForm = user
        ? `
            <form class="surface comment-form" method="post" action="/stories/${encodeURIComponent(story.slug)}/comments">
                <h3>Leave a reply</h3>
                <textarea name="body" placeholder="Add a thoughtful reply that helps, recognizes, or clarifies." required></textarea>
                <div class="composer-actions">
                    <button class="button button--primary" type="submit">Post comment</button>
                </div>
            </form>
        `
        : `
            <article class="surface comment-form">
                <h3>Log in to reply</h3>
                <p>You can browse stories without an account, but commenting and following happen inside the network.</p>
                <a class="button button--primary" href="/create/">Create account</a>
            </article>
        `;

    return renderLayout({
        title: `${story.title} | Eir Stories`,
        description: story.summary,
        pathname: `/stories/${story.slug}`,
        user,
        error,
        notice,
        body: `
            <section class="page-hero">
                <div class="shell story-layout">
                    <article class="story-main">
                        <div class="story-header">
                            <div class="story-card__author">
                                <span class="author-dot">${escapeHtml(initials(story.authorName))}</span>
                                <a href="/profiles/${encodeURIComponent(story.authorSlug)}">${escapeHtml(story.authorName)}</a>
                                <span class="pill">${escapeHtml(story.authorProfileMode)}</span>
                            </div>
                            <div class="story-actions">
                                ${followAction}
                                ${messageAction}
                            </div>
                        </div>
                        <h1>${escapeHtml(story.title)}</h1>
                        <p class="lede">${escapeHtml(story.summary)}</p>
                        <div class="story-card__tags">
                            ${(story.conditions || []).map((tag) => `<span class="pill">${escapeHtml(tag)}</span>`).join("")}
                            ${(story.symptoms || []).map((tag) => `<span class="pill">${escapeHtml(tag)}</span>`).join("")}
                            <span class="pill">${escapeHtml(story.country)}</span>
                            <span class="pill">${escapeHtml(story.evidence_level)}</span>
                        </div>
                        <article class="surface section-card">
                            <h2>The story</h2>
                            <div class="story-body">
                                ${(story.body || []).map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`).join("")}
                            </div>
                        </article>
                        ${(story.timeline || []).length ? `
                            <article class="surface section-card">
                                <h2>Timeline</h2>
                                <div class="timeline-list">
                                    ${story.timeline.map((item) => `
                                        <div class="timeline-item">
                                            <strong>${escapeHtml(item.date)}</strong>
                                            <div>
                                                <h3>${escapeHtml(item.label)}</h3>
                                                <p>${escapeHtml(item.details || "")}</p>
                                            </div>
                                        </div>
                                    `).join("")}
                                </div>
                            </article>
                        ` : ""}
                        <article class="surface section-card" id="comments">
                            <h2>Comments</h2>
                            <div class="comments-list">
                                ${comments.length ? comments.map((comment) => `
                                    <div class="comment">
                                        <div class="comment__meta">
                                            <span class="author-dot">${escapeHtml(initials(comment.authorName))}</span>
                                            <a href="/profiles/${encodeURIComponent(comment.authorSlug)}">${escapeHtml(comment.authorName)}</a>
                                            <span>${escapeHtml(formatDate(comment.createdAt))}</span>
                                        </div>
                                        <div class="comment__bubble">${escapeHtml(comment.body)}</div>
                                    </div>
                                `).join("") : "<p>No replies yet.</p>"}
                            </div>
                        </article>
                        ${commentForm}
                    </article>
                    <aside class="story-sidebar">
                        <article class="sidebar-card">
                            <h3>Profile context</h3>
                            <ul>
                                <li>${escapeHtml(story.authorPrimaryConcern || "Health journey")}</li>
                                <li>${escapeHtml(story.authorCountry || "Global")}</li>
                                <li>${escapeHtml(story.authorMessagingPolicy || "Open to messages")}</li>
                            </ul>
                        </article>
                        ${(story.helped || []).length ? `
                            <article class="sidebar-card">
                                <h3>What helped</h3>
                                <ul>${story.helped.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>
                            </article>
                        ` : ""}
                        ${(story.didNotHelp || []).length ? `
                            <article class="sidebar-card">
                                <h3>What did not help</h3>
                                <ul>${story.didNotHelp.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>
                            </article>
                        ` : ""}
                    </aside>
                </div>
            </section>
        `,
    });
}

function renderProfilesIndex({ profiles, user, error = "", notice = "" }) {
    return renderLayout({
        title: "Profiles | Eir Stories",
        description: "Browse public health profiles on Eir Stories.",
        pathname: "/profiles/",
        user,
        error,
        notice,
        body: `
            <section class="page-hero">
                <div class="shell">
                    <div class="eyebrow"><span class="eyebrow__dot" aria-hidden="true"></span>Profiles</div>
                    <h1>People behind the stories.</h1>
                    <p class="lede">Profiles make stories easier to follow over time. You can choose how much health context to show, whether messages are open, and how public you want to be.</p>
                </div>
            </section>
            <section>
                <div class="shell profile-directory">
                    ${renderProfileCards(profiles)}
                </div>
            </section>
        `,
    });
}

function renderProfilePage({ profile, stories, user, error = "", notice = "" }) {
    const followForm = user && user.slug !== profile.slug
        ? `
            <form method="post" action="/profiles/${encodeURIComponent(profile.slug)}/follow">
                <button class="action-chip" type="submit">${profile.isFollowing ? "Following" : "Follow profile"}</button>
            </form>
        `
        : "";
    const messageForm = user && user.slug !== profile.slug
        ? `
            <form class="surface section-card" id="message-form" method="post" action="/profiles/${encodeURIComponent(profile.slug)}/messages">
                <h2>Send a message</h2>
                <label class="field">Message
                    <textarea name="body" placeholder="Write a short message that explains why you are reaching out." required></textarea>
                </label>
                <div class="composer-actions">
                    <button class="button button--primary" type="submit">Send message</button>
                </div>
            </form>
        `
        : "";

    return renderLayout({
        title: `${profile.display_name} | Eir Stories`,
        description: profile.bio,
        pathname: `/profiles/${profile.slug}`,
        user,
        error,
        notice,
        body: `
            <section class="page-hero">
                <div class="shell">
                    <article class="surface profile-header">
                        <div class="profile-header__top">
                            <div>
                                <div class="profile-header__identity">
                                    <div class="profile-avatar">${escapeHtml(initials(profile.display_name))}</div>
                                    <div>
                                        <div class="brand__eyebrow">${escapeHtml(profile.profile_mode)}</div>
                                        <h1 class="profile-header__name">${escapeHtml(profile.display_name)}</h1>
                                        <div class="home-note__meta">${escapeHtml(profile.primary_concern || "Health journey")} • ${escapeHtml(profile.country || "Global")} • ${escapeHtml(profile.messaging_policy || "Open to messages")}</div>
                                    </div>
                                </div>
                                <p class="profile-header__summary">${escapeHtml(profile.bio)}</p>
                                <div class="profile-stats">
                                    <span class="pill">${Number(profile.followerCount || 0)} followers</span>
                                    <span class="pill">${Number(profile.storyCount || 0)} public stories</span>
                                    <span class="pill">${Number(profile.commentCount || 0)} total comments</span>
                                </div>
                            </div>
                            <div class="story-actions">
                                ${followForm}
                            </div>
                        </div>
                    </article>
                </div>
            </section>
            <section>
                <div class="shell profile-layout">
                    <div class="profile-main">
                        <article class="surface section-card">
                            <h2>Public stories</h2>
                            <div class="profile-story-list">
                                ${stories.length ? stories.map((story) => `
                                    <div class="profile-story-item">
                                        <a href="/stories/${encodeURIComponent(story.slug)}"><h3>${escapeHtml(story.title)}</h3></a>
                                        <p>${escapeHtml(story.summary)}</p>
                                    </div>
                                `).join("") : "<p>No public stories yet.</p>"}
                            </div>
                        </article>
                        ${messageForm}
                    </div>
                    <aside class="profile-sidebar">
                        <article class="sidebar-card">
                            <h3>Health context</h3>
                            <ul>
                                ${(profile.conditions || []).map((item) => `<li>${escapeHtml(item)}</li>`).join("")}
                                ${(profile.symptomThemes || []).map((item) => `<li>${escapeHtml(item)}</li>`).join("")}
                            </ul>
                        </article>
                        <article class="sidebar-card">
                            <h3>Interaction settings</h3>
                            <ul>
                                <li>Comments: ${escapeHtml(profile.comment_policy || "Open")}</li>
                                <li>Messages: ${escapeHtml(profile.messaging_policy || "Open to messages")}</li>
                                <li>Visibility: ${escapeHtml(profile.visibility || "Public")}</li>
                            </ul>
                        </article>
                    </aside>
                </div>
            </section>
        `,
    });
}

function renderMessagesPage({ user, messages, error = "", notice = "" }) {
    return renderLayout({
        title: "Messages | Eir Stories",
        description: "Private messages on Eir Stories.",
        pathname: "/messages/",
        user,
        error,
        notice,
        body: `
            <section class="page-hero">
                <div class="shell">
                    <div class="eyebrow"><span class="eyebrow__dot" aria-hidden="true"></span>Inbox</div>
                    <h1>Your messages.</h1>
                    <p class="lede">Private messages are for one-to-one follow-up after a public story made someone feel understood.</p>
                </div>
            </section>
            <section>
                <div class="shell">
                    <article class="surface inbox-card">
                        ${messages.length ? messages.map((message) => `
                            <div class="message-thread">
                                <div class="message-thread__meta">
                                    <strong>${escapeHtml(message.senderName)}</strong>
                                    <span>${escapeHtml(formatDate(message.createdAt))}</span>
                                </div>
                                <p>${escapeHtml(message.body)}</p>
                            </div>
                        `).join("") : "<p>No messages yet.</p>"}
                    </article>
                </div>
            </section>
        `,
    });
}

module.exports = {
    renderFeed,
    renderHome,
    renderMessagesPage,
    renderProfilePage,
    renderProfilesIndex,
    renderSignup,
    renderStoriesIndex,
    renderStoryPage,
};
