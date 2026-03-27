const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const bcrypt = require("bcryptjs");
const Database = require("better-sqlite3");
const storySeed = require("../docs/data/stories.json");

const storageDir = path.join(__dirname, "..", "storage");
const databasePath = path.join(storageDir, "stories.db");
const sessionLifetimeMs = 1000 * 60 * 60 * 24 * 30;

const profileSeed = [
    {
        slug: "mika",
        email: "mika@stories.eir.space",
        password: "eirstories",
        displayName: "Mika",
        bio: "I write about recurring migraine, the years before the pattern made sense, and how work and study changed once I could describe the same experience more clearly.",
        country: "Sweden",
        primaryConcern: "Migraine",
        profileMode: "Pseudonymous",
        visibility: "Public",
        messagingPolicy: "Open to messages",
        commentPolicy: "Open",
        conditions: ["Migraine"],
        symptomThemes: ["Headache", "Light sensitivity", "Nausea"],
    },
    {
        slug: "aino",
        email: "aino@stories.eir.space",
        password: "eirstories",
        displayName: "Aino",
        bio: "I write about long paths to recognition, pain that was minimized for years, and how timelines changed the way I could speak in appointments.",
        country: "Finland",
        primaryConcern: "Endometriosis",
        profileMode: "Pseudonymous",
        visibility: "Public",
        messagingPolicy: "Open to thoughtful requests",
        commentPolicy: "Open",
        conditions: ["Endometriosis"],
        symptomThemes: ["Pelvic pain", "Fatigue"],
    },
    {
        slug: "jonas",
        email: "jonas@stories.eir.space",
        password: "eirstories",
        displayName: "Jonas",
        bio: "I write about long COVID, pacing, setbacks, and the difference between progress that looks clean on paper and progress that feels real in daily life.",
        country: "Denmark",
        primaryConcern: "Long COVID",
        profileMode: "Pseudonymous",
        visibility: "Public",
        messagingPolicy: "Open to short messages",
        commentPolicy: "Open",
        conditions: ["Long COVID"],
        symptomThemes: ["Fatigue", "Post-exertional crashes", "Brain fog"],
    },
    {
        slug: "elin",
        email: "elin@stories.eir.space",
        password: "eirstories",
        displayName: "Elin",
        bio: "I am here to show what a profile can look like when you want to be useful to strangers without overexposing your private life.",
        country: "Sweden",
        primaryConcern: "Chronic illness",
        profileMode: "Pseudonymous",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Chronic illness"],
        symptomThemes: ["Fatigue", "Pain"],
    },
    {
        slug: "lauren-bannon",
        email: "lauren@stories.eir.space",
        password: "eirstories",
        displayName: "Lauren Bannon",
        bio: "A reported public story about using ChatGPT to connect scattered symptoms, push for further testing, and advocate for answers.",
        country: "United States",
        primaryConcern: "Thyroid cancer",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Thyroid cancer", "Hashimoto's disease"],
        symptomThemes: ["Hand stiffness", "Heart palpitations", "Stomach pain"],
    },
    {
        slug: "rich-kaplan",
        email: "rich@stories.eir.space",
        password: "eirstories",
        displayName: "Rich Kaplan",
        bio: "A reported public story about using ChatGPT to challenge insurance paperwork, understand treatment risk, and stay engaged in rare-disease care.",
        country: "United States",
        primaryConcern: "Rare autoimmune disease",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Catastrophic antiphospholipid syndrome"],
        symptomThemes: ["Kidney risk", "Treatment delays"],
    },
    {
        slug: "ayrin-santoso",
        email: "ayrin@stories.eir.space",
        password: "eirstories",
        displayName: "Ayrin Santoso",
        bio: "A reported public story about using ChatGPT to coordinate urgent care for her mother across borders.",
        country: "United States / Indonesia",
        primaryConcern: "Care coordination",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Stroke risk", "Hypertension"],
        symptomThemes: ["Sudden vision loss", "Blood pressure monitoring"],
    },
    {
        slug: "allison-leeds",
        email: "allison@stories.eir.space",
        password: "eirstories",
        displayName: "Allison Leeds",
        bio: "A reported public story about using ChatGPT to understand recovery through thousands of patient stories.",
        country: "United States",
        primaryConcern: "Breast cancer recovery",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Breast cancer recovery"],
        symptomThemes: ["Post-surgical recovery", "Emotional recovery"],
    },
    {
        slug: "autistic-reddit-user",
        email: "autistic-reddit-user@stories.eir.space",
        password: "eirstories",
        displayName: "Autistic Reddit user",
        bio: "A reported public Reddit story about using ChatGPT as a communication aid after a traumatic event.",
        country: "Unknown",
        primaryConcern: "Communication after trauma",
        profileMode: "Reported from Reddit",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Autism"],
        symptomThemes: ["Communication overload", "Post-traumatic distress"],
    },
    {
        slug: "whatevergreg",
        email: "whatevergreg@stories.eir.space",
        password: "eirstories",
        displayName: "WhateverGreg",
        bio: "A reported public Reddit story about using ChatGPT to pull together a long neurologic history.",
        country: "Unknown",
        primaryConcern: "Neurologic diagnosis",
        profileMode: "Reported from Reddit",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Neurologic disorder", "CSF leak"],
        symptomThemes: ["Deja vu episodes", "Nausea", "Drooling"],
    },
    {
        slug: "pulmonary-embolism-reddit-user",
        email: "pulmonary-embolism-reddit-user@stories.eir.space",
        password: "eirstories",
        displayName: "Pulmonary embolism Reddit user",
        bio: "A reported public Reddit story about using ChatGPT to push back after repeated dismissal.",
        country: "Unknown",
        primaryConcern: "Acute care escalation",
        profileMode: "Reported from Reddit",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Pulmonary embolism", "Heart failure"],
        symptomThemes: ["Shortness of breath", "Chest pain"],
    },
    {
        slug: "natallia-tarrien",
        email: "natallia-tarrien@stories.eir.space",
        password: "eirstories",
        displayName: "Natallia Tarrien",
        bio: "A reported public story about asking ChatGPT a casual question during pregnancy that led to a life-saving preeclampsia diagnosis.",
        country: "United States",
        primaryConcern: "Severe preeclampsia",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Severe preeclampsia"],
        symptomThemes: ["Jaw tightness", "High blood pressure", "Vision loss"],
    },
    {
        slug: "jason-aten",
        email: "jason-aten@stories.eir.space",
        password: "eirstories",
        displayName: "Jason Aten",
        bio: "A reported public story about months of breathlessness dismissed as aging, until ChatGPT flagged congestive heart failure.",
        country: "United States",
        primaryConcern: "Congestive heart failure",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Congestive heart failure"],
        symptomThemes: ["Shortness of breath", "Exercise intolerance", "Fatigue"],
    },
    {
        slug: "burt-rosen",
        email: "burt-rosen@stories.eir.space",
        password: "eirstories",
        displayName: "Burt Rosen",
        bio: "A reported public story about navigating two concurrent cancers with ChatGPT and building a custom AI tool for other patients.",
        country: "United States",
        primaryConcern: "Dual cancer treatment",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Renal clear cell carcinoma", "Pancreatic neuroendocrine tumor"],
        symptomThemes: ["Fatigue", "Nausea", "Treatment side effects"],
    },
    {
        slug: "anonymous-sepsis",
        email: "anonymous-sepsis@stories.eir.space",
        password: "eirstories",
        displayName: "Anonymous",
        bio: "A reported public story about ChatGPT urging an ER visit for post-surgical sepsis after the doctor said the cyst was not infected.",
        country: "United States",
        primaryConcern: "Post-surgical sepsis",
        profileMode: "Reported from Reddit",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Post-surgical sepsis"],
        symptomThemes: ["Fever", "Post-surgical deterioration"],
    },
    {
        slug: "flavio-adamo",
        email: "flavio-adamo@stories.eir.space",
        password: "eirstories",
        displayName: "Flavio Adamo",
        bio: "A reported public story about ChatGPT responding with unusual urgency to escalating pain, with a thirty-minute window before organ loss.",
        country: "Unknown",
        primaryConcern: "Organ-threatening emergency",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Organ-threatening emergency"],
        symptomThemes: ["Severe escalating pain"],
    },
    {
        slug: "anonymous-appendix",
        email: "anonymous-appendix@stories.eir.space",
        password: "eirstories",
        displayName: "Anonymous",
        bio: "A reported public story about Grok contradicting an ER acid reflux diagnosis and recommending a CT scan that found a near-ruptured appendix.",
        country: "Norway",
        primaryConcern: "Near-ruptured appendix",
        profileMode: "Reported from Reddit",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Near-ruptured appendix"],
        symptomThemes: ["Severe abdominal pain", "Nausea"],
    },
    {
        slug: "pippa-collins-gould",
        email: "pippa-collins-gould@stories.eir.space",
        password: "eirstories",
        displayName: "Pippa Collins-Gould",
        bio: "A reported public story about using ChatGPT to decode a cancer diagnosis from pathology results accidentally released early.",
        country: "United Kingdom",
        primaryConcern: "Follicular thyroid cancer",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Follicular thyroid cancer"],
        symptomThemes: ["Neck swelling", "Recurring chest infection"],
    },
    {
        slug: "anonymous-thyroid",
        email: "anonymous-thyroid@stories.eir.space",
        password: "eirstories",
        displayName: "Anonymous",
        bio: "A reported public story about insisting on an ultrasound after ChatGPT mentioned a tumor as a less likely scenario.",
        country: "Unknown",
        primaryConcern: "Aggressive thyroid cancer",
        profileMode: "Reported from Reddit",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Aggressive thyroid cancer"],
        symptomThemes: ["Sore throat", "Swollen lymph nodes"],
    },
    {
        slug: "ian-rowan",
        email: "ian-rowan@stories.eir.space",
        password: "eirstories",
        displayName: "Ian Rowan",
        bio: "A reported public story about giving Claude Code nine years of Apple Watch data and building a predictive early warning system for Graves' disease.",
        country: "Unknown",
        primaryConcern: "Graves' disease",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Graves' disease"],
        symptomThemes: ["Episodic hyperthyroidism", "Heart rate variability changes"],
    },
    {
        slug: "katie-mccurdy",
        email: "katie-mccurdy@stories.eir.space",
        password: "eirstories",
        displayName: "Katie McCurdy",
        bio: "A reported public story about setting up Claude as a personalized health consultant for five-plus diagnoses and seventeen medications.",
        country: "United States",
        primaryConcern: "Multiple chronic conditions",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Multiple chronic conditions"],
        symptomThemes: ["Complex medication interactions", "Multi-system symptoms"],
    },
    {
        slug: "anonymous-china",
        email: "anonymous-china@stories.eir.space",
        password: "eirstories",
        displayName: "Anonymous",
        bio: "A reported story about a kidney transplant patient in China relying on DeepSeek for health questions in a system where doctor visits last three minutes.",
        country: "China",
        primaryConcern: "Post-kidney transplant management",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Post-kidney transplant management"],
        symptomThemes: ["Anemia", "Complex medication needs"],
    },
    {
        slug: "kimmie-watkins",
        email: "kimmie-watkins@stories.eir.space",
        password: "eirstories",
        displayName: "Kimmie Watkins",
        bio: "A reported public story about an Apple Watch detecting a dangerously high heart rate during sleep, leading to a saddle pulmonary embolism diagnosis.",
        country: "United States",
        primaryConcern: "Saddle pulmonary embolism",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Saddle pulmonary embolism", "Clotting disorder"],
        symptomThemes: ["Elevated heart rate during sleep", "Malaise"],
    },
    {
        slug: "rosie-fertility",
        email: "rosie-fertility@stories.eir.space",
        password: "eirstories",
        displayName: "Rosie",
        bio: "A reported public story about eighteen years of infertility and an AI system that found three hidden sperm cells in a sample declared empty.",
        country: "Unknown",
        primaryConcern: "Male infertility",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Azoospermia", "Male infertility"],
        symptomThemes: ["Infertility"],
    },
    {
        slug: "david-a-grant",
        email: "david-a-grant@stories.eir.space",
        password: "eirstories",
        displayName: "David A. Grant",
        bio: "A reported public story about a daughter using ChatGPT to formulate better questions for doctors, leading to a bowel obstruction diagnosis.",
        country: "United Kingdom",
        primaryConcern: "Bowel obstruction",
        profileMode: "Reported elsewhere",
        visibility: "Public",
        messagingPolicy: "Closed to new messages",
        commentPolicy: "Open",
        conditions: ["Bowel obstruction"],
        symptomThemes: ["Worsening abdominal symptoms", "Diagnostic delay"],
    },
];

function nowIso() {
    return new Date().toISOString();
}

function hashToken(token) {
    return crypto.createHash("sha256").update(token).digest("hex");
}

function slugify(value) {
    return String(value || "")
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 72) || "story";
}

function serializeJson(value) {
    return JSON.stringify(value ?? []);
}

function parseJson(value) {
    if (!value) {
        return [];
    }
    try {
        return JSON.parse(value);
    } catch {
        return [];
    }
}

function mapUser(row) {
    if (!row) {
        return null;
    }
    return {
        ...row,
        conditions: parseJson(row.conditions_json),
        symptomThemes: parseJson(row.symptom_themes_json),
    };
}

function mapStory(row) {
    if (!row) {
        return null;
    }
    return {
        ...row,
        body: parseJson(row.body_json),
        conditions: parseJson(row.conditions_json),
        symptoms: parseJson(row.symptoms_json),
        medications: parseJson(row.medications_json),
        lessons: parseJson(row.lessons_json),
        helped: parseJson(row.helped_json),
        didNotHelp: parseJson(row.did_not_help_json),
        timeline: parseJson(row.timeline_json),
    };
}

function createDatabase() {
    fs.mkdirSync(storageDir, { recursive: true });
    const db = new Database(databasePath);
    db.pragma("journal_mode = WAL");

    db.exec(`
        create table if not exists users (
            id integer primary key autoincrement,
            email text not null unique,
            password_hash text not null,
            slug text not null unique,
            display_name text not null,
            bio text not null default '',
            country text not null default '',
            primary_concern text not null default '',
            profile_mode text not null default 'Pseudonymous',
            visibility text not null default 'Public',
            messaging_policy text not null default 'Open to messages',
            comment_policy text not null default 'Open',
            conditions_json text not null default '[]',
            symptom_themes_json text not null default '[]',
            created_at text not null,
            updated_at text not null
        );

        create table if not exists stories (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            slug text not null unique,
            title text not null,
            summary text not null,
            body_json text not null default '[]',
            country text not null default '',
            evidence_level text not null default 'Narrative only',
            journey_stage text not null default 'Ongoing',
            conditions_json text not null default '[]',
            symptoms_json text not null default '[]',
            medications_json text not null default '[]',
            lessons_json text not null default '[]',
            helped_json text not null default '[]',
            did_not_help_json text not null default '[]',
            timeline_json text not null default '[]',
            status text not null default 'public',
            created_at text not null,
            updated_at text not null
        );

        create table if not exists comments (
            id integer primary key autoincrement,
            story_id integer not null references stories(id) on delete cascade,
            user_id integer not null references users(id) on delete cascade,
            body text not null,
            created_at text not null
        );

        create table if not exists follows (
            id integer primary key autoincrement,
            follower_user_id integer not null references users(id) on delete cascade,
            followed_user_id integer not null references users(id) on delete cascade,
            created_at text not null,
            unique (follower_user_id, followed_user_id)
        );

        create table if not exists messages (
            id integer primary key autoincrement,
            sender_user_id integer not null references users(id) on delete cascade,
            recipient_user_id integer not null references users(id) on delete cascade,
            body text not null,
            created_at text not null
        );

        create table if not exists sessions (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            token_hash text not null unique,
            created_at text not null,
            expires_at text not null
        );
    `);

    seedIfNeeded(db);
    return db;
}

function seedIfNeeded(db) {
    const userCount = db.prepare("select count(*) as count from users").get().count;
    if (userCount > 0) {
        return;
    }

    const insertUser = db.prepare(`
        insert into users (
            email,
            password_hash,
            slug,
            display_name,
            bio,
            country,
            primary_concern,
            profile_mode,
            visibility,
            messaging_policy,
            comment_policy,
            conditions_json,
            symptom_themes_json,
            created_at,
            updated_at
        ) values (
            @email,
            @passwordHash,
            @slug,
            @displayName,
            @bio,
            @country,
            @primaryConcern,
            @profileMode,
            @visibility,
            @messagingPolicy,
            @commentPolicy,
            @conditionsJson,
            @symptomThemesJson,
            @createdAt,
            @updatedAt
        )
    `);

    const insertStory = db.prepare(`
        insert into stories (
            user_id,
            slug,
            title,
            summary,
            body_json,
            country,
            evidence_level,
            journey_stage,
            conditions_json,
            symptoms_json,
            medications_json,
            lessons_json,
            helped_json,
            did_not_help_json,
            timeline_json,
            status,
            created_at,
            updated_at
        ) values (
            @userId,
            @slug,
            @title,
            @summary,
            @bodyJson,
            @country,
            @evidenceLevel,
            @journeyStage,
            @conditionsJson,
            @symptomsJson,
            @medicationsJson,
            @lessonsJson,
            @helpedJson,
            @didNotHelpJson,
            @timelineJson,
            'public',
            @createdAt,
            @updatedAt
        )
    `);

    const insertFollow = db.prepare(`
        insert into follows (follower_user_id, followed_user_id, created_at)
        values (?, ?, ?)
    `);

    const insertComment = db.prepare(`
        insert into comments (story_id, user_id, body, created_at)
        values (?, ?, ?, ?)
    `);

    const insertMessage = db.prepare(`
        insert into messages (sender_user_id, recipient_user_id, body, created_at)
        values (?, ?, ?, ?)
    `);

    const now = nowIso();
    const userIds = new Map();

    for (const profile of profileSeed) {
        const info = insertUser.run({
            email: profile.email.toLowerCase(),
            passwordHash: bcrypt.hashSync(profile.password, 10),
            slug: profile.slug,
            displayName: profile.displayName,
            bio: profile.bio,
            country: profile.country,
            primaryConcern: profile.primaryConcern,
            profileMode: profile.profileMode,
            visibility: profile.visibility,
            messagingPolicy: profile.messagingPolicy,
            commentPolicy: profile.commentPolicy,
            conditionsJson: serializeJson(profile.conditions),
            symptomThemesJson: serializeJson(profile.symptomThemes),
            createdAt: now,
            updatedAt: now,
        });
        userIds.set(profile.slug, info.lastInsertRowid);
    }

    for (const story of storySeed) {
        insertStory.run({
            userId: userIds.get(story.authorSlug),
            slug: story.slug,
            title: story.title,
            summary: story.summary,
            bodyJson: serializeJson(story.body),
            country: story.country,
            evidenceLevel: story.evidenceLevel,
            journeyStage: story.journeyStage,
            conditionsJson: serializeJson(story.conditions),
            symptomsJson: serializeJson(story.symptoms),
            medicationsJson: serializeJson(story.medications),
            lessonsJson: serializeJson(story.lessons),
            helpedJson: serializeJson(story.helped),
            didNotHelpJson: serializeJson(story.didNotHelp),
            timelineJson: serializeJson(story.timeline),
            createdAt: now,
            updatedAt: now,
        });
    }

    insertFollow.run(userIds.get("aino"), userIds.get("mika"), now);
    insertFollow.run(userIds.get("jonas"), userIds.get("mika"), now);
    insertFollow.run(userIds.get("mika"), userIds.get("aino"), now);

    const migraineStory = db.prepare("select id from stories where slug = ?").get("living-with-migraine-across-work-and-university");
    const longCovidStory = db.prepare("select id from stories where slug = ?").get("what-changed-after-i-started-tracking-the-setbacks");

    insertComment.run(migraineStory.id, userIds.get("aino"), "Thank you for writing this so plainly. The part about finally having language for the same repeating experience stayed with me.", now);
    insertComment.run(migraineStory.id, userIds.get("jonas"), "I saved this because it shows exactly how a story can be useful without oversharing.", now);
    insertComment.run(longCovidStory.id, userIds.get("mika"), "The point about setbacks being part of the pattern is the part I wish I had understood earlier.", now);

    insertMessage.run(userIds.get("aino"), userIds.get("mika"), "Your migraine story helped me rewrite my own timeline before my last appointment. Thank you.", now);
    insertMessage.run(userIds.get("jonas"), userIds.get("aino"), "If you ever want to compare how you structure evidence without making it overwhelming, I would be glad to share what helped me.", now);
}

function ensureUniqueSlug(db, table, base) {
    const candidate = slugify(base);
    let current = candidate;
    let index = 2;
    const statement = db.prepare(`select 1 from ${table} where slug = ? limit 1`);
    while (statement.get(current)) {
        current = `${candidate}-${index}`;
        index += 1;
    }
    return current;
}

function createUser(db, input) {
    const email = String(input.email || "").trim().toLowerCase();
    const displayName = String(input.displayName || "").trim();
    const password = String(input.password || "");

    if (!email || !displayName || !password) {
        throw new Error("Email, display name, and password are required.");
    }
    if (password.length < 8) {
        throw new Error("Password must be at least 8 characters.");
    }
    if (db.prepare("select id from users where email = ?").get(email)) {
        throw new Error("An account with that email already exists.");
    }

    const now = nowIso();
    const slug = ensureUniqueSlug(db, "users", input.slug || displayName);
    const info = db.prepare(`
        insert into users (
            email,
            password_hash,
            slug,
            display_name,
            bio,
            country,
            primary_concern,
            profile_mode,
            visibility,
            messaging_policy,
            comment_policy,
            conditions_json,
            symptom_themes_json,
            created_at,
            updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
        email,
        bcrypt.hashSync(password, 10),
        slug,
        displayName,
        String(input.bio || "").trim(),
        String(input.country || "").trim(),
        String(input.primaryConcern || "").trim(),
        String(input.profileMode || "Pseudonymous").trim(),
        String(input.visibility || "Public").trim(),
        String(input.messagingPolicy || "Open to messages").trim(),
        String(input.commentPolicy || "Open").trim(),
        serializeJson(input.conditions || []),
        serializeJson(input.symptomThemes || []),
        now,
        now,
    );
    return getUserById(db, info.lastInsertRowid);
}

function authenticateUser(db, email, password) {
    const row = db.prepare("select * from users where email = ?").get(String(email || "").trim().toLowerCase());
    if (!row) {
        return null;
    }
    if (!bcrypt.compareSync(String(password || ""), row.password_hash)) {
        return null;
    }
    return mapUser(row);
}

function createSession(db, userId) {
    const token = crypto.randomBytes(32).toString("hex");
    const now = new Date();
    const expiresAt = new Date(now.getTime() + sessionLifetimeMs).toISOString();
    db.prepare("insert into sessions (user_id, token_hash, created_at, expires_at) values (?, ?, ?, ?)").run(
        userId,
        hashToken(token),
        now.toISOString(),
        expiresAt,
    );
    return { token, expiresAt };
}

function deleteSession(db, token) {
    if (!token) {
        return;
    }
    db.prepare("delete from sessions where token_hash = ?").run(hashToken(token));
}

function getUserBySessionToken(db, token) {
    if (!token) {
        return null;
    }
    const now = nowIso();
    db.prepare("delete from sessions where expires_at <= ?").run(now);
    const row = db.prepare(`
        select users.*
        from sessions
        join users on users.id = sessions.user_id
        where sessions.token_hash = ?
          and sessions.expires_at > ?
        limit 1
    `).get(hashToken(token), now);
    return mapUser(row);
}

function getUserById(db, id) {
    return mapUser(db.prepare("select * from users where id = ?").get(id));
}

function getUserBySlug(db, slug) {
    return mapUser(db.prepare("select * from users where slug = ?").get(slug));
}

function listProfiles(db, currentUserId) {
    const rows = db.prepare(`
        select
            users.*,
            (select count(*) from follows where followed_user_id = users.id) as follower_count,
            (select count(*) from stories where user_id = users.id and status = 'public') as story_count,
            exists(
                select 1 from follows
                where follower_user_id = @currentUserId
                  and followed_user_id = users.id
            ) as is_following
        from users
        order by follower_count desc, users.display_name asc
    `).all({ currentUserId: currentUserId || 0 });
    return rows.map((row) => ({
        ...mapUser(row),
        followerCount: row.follower_count,
        storyCount: row.story_count,
        isFollowing: !!row.is_following,
    }));
}

function listStories(db, limit) {
    const sql = `
        select
            stories.*,
            users.display_name as author_name,
            users.slug as author_slug,
            users.profile_mode as author_profile_mode,
            (select count(*) from comments where story_id = stories.id) as comment_count
        from stories
        join users on users.id = stories.user_id
        where stories.status = 'public'
        order by stories.created_at desc, stories.id desc
        ${limit ? `limit ${Number(limit)}` : ""}
    `;
    return db.prepare(sql).all().map((row) => ({
        ...mapStory(row),
        authorName: row.author_name,
        authorSlug: row.author_slug,
        authorProfileMode: row.author_profile_mode,
        commentCount: row.comment_count,
    }));
}

function getStoryBySlug(db, slug, currentUserId) {
    const row = db.prepare(`
        select
            stories.*,
            users.display_name as author_name,
            users.slug as author_slug,
            users.profile_mode as author_profile_mode,
            users.messaging_policy as author_messaging_policy,
            users.primary_concern as author_primary_concern,
            users.country as author_country,
            (select count(*) from comments where story_id = stories.id) as comment_count,
            exists(
                select 1 from follows
                where follower_user_id = @currentUserId
                  and followed_user_id = users.id
            ) as is_following_author
        from stories
        join users on users.id = stories.user_id
        where stories.slug = @slug
          and stories.status = 'public'
        limit 1
    `).get({ slug, currentUserId: currentUserId || 0 });
    if (!row) {
        return null;
    }
    return {
        ...mapStory(row),
        authorName: row.author_name,
        authorSlug: row.author_slug,
        authorProfileMode: row.author_profile_mode,
        authorMessagingPolicy: row.author_messaging_policy,
        authorPrimaryConcern: row.author_primary_concern,
        authorCountry: row.author_country,
        commentCount: row.comment_count,
        isFollowingAuthor: !!row.is_following_author,
    };
}

function listStoryComments(db, storyId) {
    return db.prepare(`
        select comments.*, users.display_name as author_name, users.slug as author_slug
        from comments
        join users on users.id = comments.user_id
        where comments.story_id = ?
        order by comments.created_at asc, comments.id asc
    `).all(storyId).map((row) => ({
        id: row.id,
        body: row.body,
        createdAt: row.created_at,
        authorName: row.author_name,
        authorSlug: row.author_slug,
    }));
}

function listStoriesForUser(db, userId) {
    return db.prepare(`
        select
            stories.*,
            users.display_name as author_name,
            users.slug as author_slug,
            users.profile_mode as author_profile_mode,
            (select count(*) from comments where story_id = stories.id) as comment_count
        from stories
        join users on users.id = stories.user_id
        where stories.user_id = ?
          and stories.status = 'public'
        order by stories.created_at desc, stories.id desc
    `).all(userId).map((row) => ({
        ...mapStory(row),
        authorName: row.author_name,
        authorSlug: row.author_slug,
        authorProfileMode: row.author_profile_mode,
        commentCount: row.comment_count,
    }));
}

function getProfileBySlug(db, slug, currentUserId) {
    const row = db.prepare(`
        select
            users.*,
            (select count(*) from follows where followed_user_id = users.id) as follower_count,
            (select count(*) from stories where user_id = users.id and status = 'public') as story_count,
            (select count(*) from comments join stories on stories.id = comments.story_id where stories.user_id = users.id) as comment_count,
            exists(
                select 1 from follows
                where follower_user_id = @currentUserId
                  and followed_user_id = users.id
            ) as is_following
        from users
        where users.slug = @slug
        limit 1
    `).get({ slug, currentUserId: currentUserId || 0 });
    if (!row) {
        return null;
    }
    return {
        ...mapUser(row),
        followerCount: row.follower_count,
        storyCount: row.story_count,
        commentCount: row.comment_count,
        isFollowing: !!row.is_following,
    };
}

function createStory(db, userId, input) {
    const title = String(input.title || "").trim();
    const storyText = String(input.storyText || "").trim();
    if (!title || !storyText) {
        throw new Error("A story title and the story itself are required.");
    }
    const body = storyText.split(/\n+/).map((part) => part.trim()).filter(Boolean);
    if (body.length === 0) {
        throw new Error("Write at least one paragraph before publishing.");
    }
    const summary = String(input.summary || "").trim() || body[0].slice(0, 170);
    const conditions = splitCommaList(input.conditions);
    const symptoms = splitCommaList(input.symptoms);
    const medications = splitCommaList(input.medications);
    const slug = ensureUniqueSlug(db, "stories", title);
    const now = nowIso();
    db.prepare(`
        insert into stories (
            user_id,
            slug,
            title,
            summary,
            body_json,
            country,
            evidence_level,
            journey_stage,
            conditions_json,
            symptoms_json,
            medications_json,
            lessons_json,
            helped_json,
            did_not_help_json,
            timeline_json,
            status,
            created_at,
            updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', '[]', '[]', '[]', 'public', ?, ?)
    `).run(
        userId,
        slug,
        title,
        summary,
        serializeJson(body),
        String(input.country || "").trim(),
        String(input.evidenceLevel || "Narrative only").trim(),
        String(input.journeyStage || "Ongoing").trim(),
        serializeJson(conditions),
        serializeJson(symptoms),
        serializeJson(medications),
        now,
        now,
    );
    return slug;
}

function addComment(db, storySlug, userId, body) {
    const story = db.prepare("select id from stories where slug = ? and status = 'public'").get(storySlug);
    if (!story) {
        throw new Error("Story not found.");
    }
    const commentBody = String(body || "").trim();
    if (!commentBody) {
        throw new Error("Write a comment before posting.");
    }
    db.prepare("insert into comments (story_id, user_id, body, created_at) values (?, ?, ?, ?)").run(
        story.id,
        userId,
        commentBody,
        nowIso(),
    );
}

function toggleFollow(db, followerUserId, followedSlug) {
    const target = db.prepare("select id from users where slug = ?").get(followedSlug);
    if (!target) {
        throw new Error("Profile not found.");
    }
    if (target.id === followerUserId) {
        return false;
    }
    const existing = db.prepare(`
        select id from follows
        where follower_user_id = ?
          and followed_user_id = ?
    `).get(followerUserId, target.id);
    if (existing) {
        db.prepare("delete from follows where id = ?").run(existing.id);
        return false;
    }
    db.prepare("insert into follows (follower_user_id, followed_user_id, created_at) values (?, ?, ?)").run(
        followerUserId,
        target.id,
        nowIso(),
    );
    return true;
}

function createMessage(db, senderUserId, recipientSlug, body) {
    const recipient = db.prepare("select id from users where slug = ?").get(recipientSlug);
    if (!recipient) {
        throw new Error("Profile not found.");
    }
    const messageBody = String(body || "").trim();
    if (!messageBody) {
        throw new Error("Write a message before sending.");
    }
    if (recipient.id === senderUserId) {
        throw new Error("You cannot send a message to yourself.");
    }
    db.prepare("insert into messages (sender_user_id, recipient_user_id, body, created_at) values (?, ?, ?, ?)").run(
        senderUserId,
        recipient.id,
        messageBody,
        nowIso(),
    );
}

function listMessagesForUser(db, userId) {
    return db.prepare(`
        select
            messages.*,
            sender.display_name as sender_name,
            sender.slug as sender_slug,
            recipient.display_name as recipient_name
        from messages
        join users as sender on sender.id = messages.sender_user_id
        join users as recipient on recipient.id = messages.recipient_user_id
        where messages.recipient_user_id = ?
           or messages.sender_user_id = ?
        order by messages.created_at desc, messages.id desc
        limit 40
    `).all(userId, userId).map((row) => ({
        id: row.id,
        body: row.body,
        createdAt: row.created_at,
        senderName: row.sender_name,
        senderSlug: row.sender_slug,
        recipientName: row.recipient_name,
        isInbound: row.recipient_name && row.sender_slug ? row.recipient_name !== row.sender_name : true,
    }));
}

function splitCommaList(value) {
    return String(value || "")
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean)
        .slice(0, 8);
}

function getHomeSnapshot(db) {
    const latestStories = listStories(db, 3);
    const featuredProfiles = listProfiles(db, 0).slice(0, 3);
    const latestComment = db.prepare(`
        select comments.body, users.display_name as author_name, stories.slug as story_slug, stories.title as story_title
        from comments
        join users on users.id = comments.user_id
        join stories on stories.id = comments.story_id
        order by comments.created_at desc, comments.id desc
        limit 1
    `).get();
    return {
        latestStories,
        featuredProfiles,
        latestComment,
    };
}

function getFeedSnapshot(db, userId) {
    const stories = listStories(db, 8);
    const suggestions = listProfiles(db, userId)
        .filter((profile) => profile.id !== userId)
        .slice(0, 4);
    const inbox = listMessagesForUser(db, userId).slice(0, 6);
    return { stories, suggestions, inbox };
}

module.exports = {
    createDatabase,
    createMessage,
    createSession,
    createStory,
    createUser,
    addComment,
    authenticateUser,
    deleteSession,
    getFeedSnapshot,
    getHomeSnapshot,
    getProfileBySlug,
    getStoryBySlug,
    getUserBySessionToken,
    getUserBySlug,
    listMessagesForUser,
    listProfiles,
    listStories,
    listStoriesForUser,
    listStoryComments,
    toggleFollow,
};
