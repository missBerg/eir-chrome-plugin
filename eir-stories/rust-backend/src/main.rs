mod eir_import;

use std::{fs, net::SocketAddr, path::PathBuf, sync::Arc};

use axum::{
    Json, Router,
    extract::{Multipart, Path, State},
    http::StatusCode,
    response::{Html, IntoResponse, Redirect},
    routing::{get, post},
};
use bcrypt::{DEFAULT_COST, hash, verify};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{
    FromRow, Row, SqlitePool,
    sqlite::{SqliteConnectOptions, SqlitePoolOptions},
};
use time::{Duration, OffsetDateTime};
use tower_cookies::{Cookie, CookieManagerLayer, Cookies};
use tower_http::{services::ServeDir, trace::TraceLayer};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use uuid::Uuid;

use crate::eir_import::{
    HealthExampleDraft, HealthSectionDraft, ImportedHealthBundle, parse_and_transform_eir,
};

const SESSION_COOKIE: &str = "eir_stories_session";

#[derive(Clone)]
struct AppState {
    pool: SqlitePool,
}

#[derive(Debug)]
struct AppError {
    status: StatusCode,
    message: String,
}

impl AppError {
    fn new(status: StatusCode, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let payload = Json(serde_json::json!({ "error": self.message }));
        (self.status, payload).into_response()
    }
}

type AppResult<T> = Result<T, AppError>;

#[derive(Debug, Deserialize)]
struct StorySeed {
    slug: String,
    title: String,
    summary: String,
    #[serde(rename = "author")]
    _author: String,
    #[serde(rename = "authorSlug")]
    author_slug: String,
    #[serde(rename = "evidenceLevel")]
    evidence_level: String,
    country: String,
    conditions: Vec<String>,
    symptoms: Vec<String>,
    medications: Vec<String>,
    #[serde(rename = "journeyStage")]
    journey_stage: String,
    body: Vec<String>,
    lessons: Vec<String>,
    timeline: Vec<TimelineEntry>,
    helped: Vec<String>,
    #[serde(rename = "didNotHelp")]
    did_not_help: Vec<String>,
    #[serde(rename = "sourceLabel")]
    source_label: Option<String>,
    #[serde(rename = "sourceUrl")]
    source_url: Option<String>,
    #[serde(rename = "sourceExcerpt")]
    source_excerpt: Option<String>,
    #[serde(rename = "sourceKind")]
    source_kind: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TimelineEntry {
    date: String,
    label: String,
    kind: String,
    details: String,
}

#[derive(Debug, Clone)]
struct ProfileSeed {
    slug: &'static str,
    email: &'static str,
    password: &'static str,
    display_name: &'static str,
    bio: &'static str,
    country: &'static str,
    primary_concern: &'static str,
    profile_mode: &'static str,
    visibility: &'static str,
    messaging_policy: &'static str,
    comment_policy: &'static str,
    conditions: &'static [&'static str],
    symptom_themes: &'static [&'static str],
}

const PROFILE_SEED: &[ProfileSeed] = &[
    ProfileSeed {
        slug: "mika",
        email: "mika@stories.eir.space",
        password: "eirstories",
        display_name: "Mika",
        bio: "I write about recurring migraine, the years before the pattern made sense, and how work and study changed once I could describe the same experience more clearly.",
        country: "Sweden",
        primary_concern: "Migraine",
        profile_mode: "Pseudonymous",
        visibility: "Public",
        messaging_policy: "Open to messages",
        comment_policy: "Open",
        conditions: &["Migraine"],
        symptom_themes: &["Headache", "Light sensitivity", "Nausea"],
    },
    ProfileSeed {
        slug: "aino",
        email: "aino@stories.eir.space",
        password: "eirstories",
        display_name: "Aino",
        bio: "I write about long paths to recognition, pain that was minimized for years, and how timelines changed the way I could speak in appointments.",
        country: "Finland",
        primary_concern: "Endometriosis",
        profile_mode: "Pseudonymous",
        visibility: "Public",
        messaging_policy: "Open to thoughtful requests",
        comment_policy: "Open",
        conditions: &["Endometriosis"],
        symptom_themes: &["Pelvic pain", "Fatigue"],
    },
    ProfileSeed {
        slug: "jonas",
        email: "jonas@stories.eir.space",
        password: "eirstories",
        display_name: "Jonas",
        bio: "I write about long COVID, pacing, setbacks, and the difference between progress that looks clean on paper and progress that feels real in daily life.",
        country: "Denmark",
        primary_concern: "Long COVID",
        profile_mode: "Pseudonymous",
        visibility: "Public",
        messaging_policy: "Open to short messages",
        comment_policy: "Open",
        conditions: &["Long COVID"],
        symptom_themes: &["Fatigue", "Post-exertional crashes", "Brain fog"],
    },
    ProfileSeed {
        slug: "elin",
        email: "elin@stories.eir.space",
        password: "eirstories",
        display_name: "Elin",
        bio: "I am here to show what a profile can look like when you want to be useful to strangers without overexposing your private life.",
        country: "Sweden",
        primary_concern: "Chronic illness",
        profile_mode: "Pseudonymous",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Chronic illness"],
        symptom_themes: &["Fatigue", "Pain"],
    },
    ProfileSeed {
        slug: "lauren-bannon",
        email: "lauren@stories.eir.space",
        password: "eirstories",
        display_name: "Lauren Bannon",
        bio: "A reported public story about using ChatGPT to connect scattered symptoms, push for further testing, and advocate for answers.",
        country: "United States",
        primary_concern: "Thyroid cancer",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Thyroid cancer", "Hashimoto's disease"],
        symptom_themes: &["Hand stiffness", "Heart palpitations", "Stomach pain"],
    },
    ProfileSeed {
        slug: "rich-kaplan",
        email: "rich@stories.eir.space",
        password: "eirstories",
        display_name: "Rich Kaplan",
        bio: "A reported public story about using ChatGPT to challenge insurance paperwork, understand treatment risk, and stay engaged in rare-disease care.",
        country: "United States",
        primary_concern: "Rare autoimmune disease",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Catastrophic antiphospholipid syndrome"],
        symptom_themes: &["Kidney risk", "Treatment delays"],
    },
    ProfileSeed {
        slug: "ayrin-santoso",
        email: "ayrin@stories.eir.space",
        password: "eirstories",
        display_name: "Ayrin Santoso",
        bio: "A reported public story about using ChatGPT to coordinate urgent care for her mother across borders when access and trust were both difficult.",
        country: "United States / Indonesia",
        primary_concern: "Care coordination",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Stroke risk", "Hypertension"],
        symptom_themes: &["Sudden vision loss", "Blood pressure monitoring"],
    },
    ProfileSeed {
        slug: "allison-leeds",
        email: "allison@stories.eir.space",
        password: "eirstories",
        display_name: "Allison Leeds",
        bio: "A reported public story about using ChatGPT to understand recovery through thousands of patient stories and turn that into a support tool for others.",
        country: "United States",
        primary_concern: "Breast cancer recovery",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Breast cancer recovery"],
        symptom_themes: &["Post-surgical recovery", "Emotional recovery"],
    },
    ProfileSeed {
        slug: "autistic-reddit-user",
        email: "autistic-reddit-user@stories.eir.space",
        password: "eirstories",
        display_name: "Autistic Reddit user",
        bio: "A reported public Reddit story about using ChatGPT as a communication aid after a traumatic event, when ordinary writing felt impossible.",
        country: "Unknown",
        primary_concern: "Communication after trauma",
        profile_mode: "Reported from Reddit",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Autism"],
        symptom_themes: &["Communication overload", "Post-traumatic distress"],
    },
    ProfileSeed {
        slug: "whatevergreg",
        email: "whatevergreg@stories.eir.space",
        password: "eirstories",
        display_name: "WhateverGreg",
        bio: "A reported public Reddit story about using ChatGPT to pull together a long neurologic history and push toward the right specialist.",
        country: "Unknown",
        primary_concern: "Neurologic diagnosis",
        profile_mode: "Reported from Reddit",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Neurologic disorder", "CSF leak"],
        symptom_themes: &["Deja vu episodes", "Nausea", "Drooling"],
    },
    ProfileSeed {
        slug: "pulmonary-embolism-reddit-user",
        email: "pulmonary-embolism-reddit-user@stories.eir.space",
        password: "eirstories",
        display_name: "Pulmonary embolism Reddit user",
        bio: "A reported public Reddit story about using ChatGPT to review scans and symptoms after repeated dismissal, then going back for the evaluation that likely saved their life.",
        country: "Unknown",
        primary_concern: "Acute care escalation",
        profile_mode: "Reported from Reddit",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Pulmonary embolism", "Heart failure"],
        symptom_themes: &["Shortness of breath", "Chest pain"],
    },
    ProfileSeed {
        slug: "natallia-tarrien",
        email: "natallia-tarrien@stories.eir.space",
        password: "eirstories",
        display_name: "Natallia Tarrien",
        bio: "A reported public story about asking ChatGPT a casual question during pregnancy that led to a life-saving preeclampsia diagnosis.",
        country: "United States",
        primary_concern: "Severe preeclampsia",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Severe preeclampsia"],
        symptom_themes: &["Jaw tightness", "High blood pressure", "Vision loss"],
    },
    ProfileSeed {
        slug: "jason-aten",
        email: "jason-aten@stories.eir.space",
        password: "eirstories",
        display_name: "Jason Aten",
        bio: "A reported public story about months of breathlessness dismissed as aging, until ChatGPT flagged congestive heart failure.",
        country: "United States",
        primary_concern: "Congestive heart failure",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Congestive heart failure"],
        symptom_themes: &["Shortness of breath", "Exercise intolerance", "Fatigue"],
    },
    ProfileSeed {
        slug: "burt-rosen",
        email: "burt-rosen@stories.eir.space",
        password: "eirstories",
        display_name: "Burt Rosen",
        bio: "A reported public story about navigating two concurrent cancers with ChatGPT and building a custom AI tool for other patients.",
        country: "United States",
        primary_concern: "Dual cancer treatment",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Renal clear cell carcinoma", "Pancreatic neuroendocrine tumor"],
        symptom_themes: &["Fatigue", "Nausea", "Treatment side effects"],
    },
    ProfileSeed {
        slug: "anonymous-sepsis",
        email: "anonymous-sepsis@stories.eir.space",
        password: "eirstories",
        display_name: "Anonymous",
        bio: "A reported public story about ChatGPT urging an ER visit for post-surgical sepsis after the doctor said the cyst was not infected.",
        country: "United States",
        primary_concern: "Post-surgical sepsis",
        profile_mode: "Reported from Reddit",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Post-surgical sepsis"],
        symptom_themes: &["Fever", "Post-surgical deterioration"],
    },
    ProfileSeed {
        slug: "flavio-adamo",
        email: "flavio-adamo@stories.eir.space",
        password: "eirstories",
        display_name: "Flavio Adamo",
        bio: "A reported public story about ChatGPT responding with unusual urgency to escalating pain, with a thirty-minute window before organ loss.",
        country: "Unknown",
        primary_concern: "Organ-threatening emergency",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Organ-threatening emergency"],
        symptom_themes: &["Severe escalating pain"],
    },
    ProfileSeed {
        slug: "anonymous-appendix",
        email: "anonymous-appendix@stories.eir.space",
        password: "eirstories",
        display_name: "Anonymous",
        bio: "A reported public story about Grok contradicting an ER acid reflux diagnosis and recommending a CT scan that found a near-ruptured appendix.",
        country: "Norway",
        primary_concern: "Near-ruptured appendix",
        profile_mode: "Reported from Reddit",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Near-ruptured appendix"],
        symptom_themes: &["Severe abdominal pain", "Nausea"],
    },
    ProfileSeed {
        slug: "pippa-collins-gould",
        email: "pippa-collins-gould@stories.eir.space",
        password: "eirstories",
        display_name: "Pippa Collins-Gould",
        bio: "A reported public story about using ChatGPT to decode a cancer diagnosis from pathology results accidentally released early on a patient portal.",
        country: "United Kingdom",
        primary_concern: "Follicular thyroid cancer",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Follicular thyroid cancer"],
        symptom_themes: &["Neck swelling", "Recurring chest infection"],
    },
    ProfileSeed {
        slug: "anonymous-thyroid",
        email: "anonymous-thyroid@stories.eir.space",
        password: "eirstories",
        display_name: "Anonymous",
        bio: "A reported public story about insisting on an ultrasound after ChatGPT mentioned a tumor as a less likely scenario, catching aggressive thyroid cancer early.",
        country: "Unknown",
        primary_concern: "Aggressive thyroid cancer",
        profile_mode: "Reported from Reddit",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Aggressive thyroid cancer"],
        symptom_themes: &["Sore throat", "Swollen lymph nodes"],
    },
    ProfileSeed {
        slug: "ian-rowan",
        email: "ian-rowan@stories.eir.space",
        password: "eirstories",
        display_name: "Ian Rowan",
        bio: "A reported public story about giving Claude Code nine years of Apple Watch data and building a predictive early warning system for Graves' disease.",
        country: "Unknown",
        primary_concern: "Graves' disease",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Graves' disease"],
        symptom_themes: &["Episodic hyperthyroidism", "Heart rate variability changes"],
    },
    ProfileSeed {
        slug: "katie-mccurdy",
        email: "katie-mccurdy@stories.eir.space",
        password: "eirstories",
        display_name: "Katie McCurdy",
        bio: "A reported public story about setting up Claude as a personalized health consultant to manage five-plus diagnoses and seventeen medications.",
        country: "United States",
        primary_concern: "Multiple chronic conditions",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Multiple chronic conditions"],
        symptom_themes: &["Complex medication interactions", "Multi-system symptoms"],
    },
    ProfileSeed {
        slug: "anonymous-china",
        email: "anonymous-china@stories.eir.space",
        password: "eirstories",
        display_name: "Anonymous",
        bio: "A reported story about a kidney transplant patient in China relying on DeepSeek for health questions in a system where doctor visits last three minutes.",
        country: "China",
        primary_concern: "Post-kidney transplant management",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Post-kidney transplant management"],
        symptom_themes: &["Anemia", "Complex medication needs"],
    },
    ProfileSeed {
        slug: "kimmie-watkins",
        email: "kimmie-watkins@stories.eir.space",
        password: "eirstories",
        display_name: "Kimmie Watkins",
        bio: "A reported public story about an Apple Watch detecting a dangerously high heart rate during sleep, leading to a saddle pulmonary embolism diagnosis.",
        country: "United States",
        primary_concern: "Saddle pulmonary embolism",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Saddle pulmonary embolism", "Clotting disorder"],
        symptom_themes: &["Elevated heart rate during sleep", "Malaise"],
    },
    ProfileSeed {
        slug: "rosie-fertility",
        email: "rosie-fertility@stories.eir.space",
        password: "eirstories",
        display_name: "Rosie",
        bio: "A reported public story about eighteen years of infertility and an AI system that found three hidden sperm cells in a sample declared empty.",
        country: "Unknown",
        primary_concern: "Male infertility",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Azoospermia", "Male infertility"],
        symptom_themes: &["Infertility"],
    },
    ProfileSeed {
        slug: "david-a-grant",
        email: "david-a-grant@stories.eir.space",
        password: "eirstories",
        display_name: "David A. Grant",
        bio: "A reported public story about a daughter using ChatGPT to formulate better questions for doctors, leading to a bowel obstruction diagnosis and emergency surgery.",
        country: "United Kingdom",
        primary_concern: "Bowel obstruction",
        profile_mode: "Reported elsewhere",
        visibility: "Public",
        messaging_policy: "Closed to new messages",
        comment_policy: "Open",
        conditions: &["Bowel obstruction"],
        symptom_themes: &["Worsening abdominal symptoms", "Diagnostic delay"],
    },
];

#[derive(Debug, FromRow)]
struct UserRow {
    id: i64,
    email: String,
    slug: String,
    display_name: String,
    bio: String,
    country: String,
    primary_concern: String,
    profile_mode: String,
    visibility: String,
    messaging_policy: String,
    comment_policy: String,
    conditions_json: String,
    symptom_themes_json: String,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Serialize)]
struct UserPublic {
    id: i64,
    email: String,
    slug: String,
    display_name: String,
    bio: String,
    country: String,
    primary_concern: String,
    profile_mode: String,
    visibility: String,
    messaging_policy: String,
    comment_policy: String,
    conditions: Vec<String>,
    symptom_themes: Vec<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, FromRow)]
struct StoryRow {
    id: i64,
    user_id: i64,
    slug: String,
    title: String,
    summary: String,
    body_json: String,
    country: String,
    evidence_level: String,
    journey_stage: String,
    conditions_json: String,
    symptoms_json: String,
    medications_json: String,
    lessons_json: String,
    helped_json: String,
    did_not_help_json: String,
    timeline_json: String,
    source_label: Option<String>,
    source_url: Option<String>,
    source_excerpt: Option<String>,
    source_kind: String,
    status: String,
    created_at: String,
    updated_at: String,
    author_name: String,
    author_slug: String,
    comment_count: i64,
}

#[derive(Debug, Serialize)]
struct StoryPublic {
    id: i64,
    slug: String,
    title: String,
    summary: String,
    body: Vec<String>,
    country: String,
    evidence_level: String,
    journey_stage: String,
    conditions: Vec<String>,
    symptoms: Vec<String>,
    medications: Vec<String>,
    lessons: Vec<String>,
    helped: Vec<String>,
    did_not_help: Vec<String>,
    timeline: Vec<TimelineEntry>,
    source_label: Option<String>,
    source_url: Option<String>,
    source_excerpt: Option<String>,
    source_kind: String,
    created_at: String,
    updated_at: String,
    author_name: String,
    author_slug: String,
    comment_count: i64,
}

#[derive(Debug, Serialize)]
struct ProfileSummary {
    id: i64,
    slug: String,
    display_name: String,
    bio: String,
    country: String,
    primary_concern: String,
    profile_mode: String,
    visibility: String,
    messaging_policy: String,
    comment_policy: String,
    conditions: Vec<String>,
    symptom_themes: Vec<String>,
    follower_count: i64,
    story_count: i64,
    is_following: bool,
}

#[derive(Debug, Serialize)]
struct CommentPublic {
    id: i64,
    body: String,
    created_at: String,
    author_name: String,
    author_slug: String,
}

#[derive(Debug, Serialize)]
struct MessagePublic {
    id: i64,
    body: String,
    created_at: String,
    sender_name: String,
    sender_slug: String,
    recipient_name: String,
    direction: String,
}

#[derive(Debug, Serialize)]
struct HealthImportPublic {
    id: i64,
    filename: String,
    source: String,
    privacy_level: String,
    patient_label_public: String,
    record_count: i64,
    latest_entry_date: Option<String>,
    created_at: String,
    public_health_md: String,
    private_health_md: Option<String>,
    story_prompts: Vec<String>,
    sections: Vec<HealthSectionPublic>,
    examples: Vec<HealthExamplePublic>,
}

#[derive(Debug, Serialize)]
struct HealthSectionPublic {
    id: i64,
    section_key: String,
    title: String,
    visibility: String,
    markdown: String,
    private_markdown: Option<String>,
    sort_order: i64,
}

#[derive(Debug, Serialize)]
struct HealthExamplePublic {
    id: i64,
    external_entry_id: String,
    entry_date: Option<String>,
    public_date: Option<String>,
    category: String,
    record_type: String,
    provider: Option<String>,
    provider_private: Option<String>,
    responsible_role: Option<String>,
    summary: String,
    summary_private: Option<String>,
    details: Option<String>,
    details_private: Option<String>,
    tags: Vec<String>,
    visibility: String,
    sort_order: i64,
}

#[derive(Debug, Deserialize)]
struct VisibilityRequest {
    visibility: String,
}

#[derive(Debug, Deserialize)]
struct SignupRequest {
    email: String,
    password: String,
    display_name: String,
    country: Option<String>,
    primary_concern: Option<String>,
    messaging_policy: Option<String>,
    comment_policy: Option<String>,
    conditions: Option<Vec<String>>,
    symptom_themes: Option<Vec<String>>,
    bio: Option<String>,
}

#[derive(Debug, Deserialize)]
struct LoginRequest {
    email: String,
    password: String,
}

#[derive(Debug, Deserialize)]
struct CreateStoryRequest {
    title: String,
    summary: Option<String>,
    story_text: String,
    status: Option<String>,
    country: Option<String>,
    evidence_level: Option<String>,
    journey_stage: Option<String>,
    conditions: Option<Vec<String>>,
    symptoms: Option<Vec<String>>,
    medications: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct CommentRequest {
    body: String,
}

#[derive(Debug, Deserialize)]
struct MessageRequest {
    body: String,
}

#[derive(Debug, Serialize)]
struct FollowResponse {
    is_following: bool,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "rust_backend=info,tower_http=info".to_string()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let pool = initialize_database().await?;
    let state = Arc::new(AppState { pool });

    let docs_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../docs");

    let app = Router::new()
        .route("/", get(root))
        .route("/health", get(health))
        .route("/site/drafts/{draft_id}", get(story_view_shell))
        .route("/site/drafts/{draft_id}/", get(story_view_shell))
        .route("/api/me", get(me))
        .route("/api/auth/signup", post(signup))
        .route("/api/auth/login", post(login))
        .route("/api/auth/logout", post(logout))
        .route("/api/stories", get(list_stories).post(create_story_handler))
        .route("/api/stories/{slug}", get(get_story_handler))
        .route("/api/stories/{slug}/comments", post(add_comment_handler))
        .route("/api/profiles", get(list_profiles_handler))
        .route("/api/profiles/{slug}", get(get_profile_handler))
        .route("/api/profiles/{slug}/follow", post(toggle_follow_handler))
        .route("/api/profiles/{slug}/messages", post(create_message_handler))
        .route("/api/messages", get(list_messages_handler))
        .route("/api/health/preview", post(preview_health_file_handler))
        .route("/api/health/imports", get(list_health_imports_handler).post(import_health_file_handler))
        .route("/api/health/imports/{id}", get(get_health_import_handler))
        .route("/api/health/imports/{id}/sections/{section_id}/visibility", post(update_health_section_visibility_handler))
        .route("/api/health/imports/{id}/examples/{example_id}/visibility", post(update_health_example_visibility_handler))
        .nest_service("/site", ServeDir::new(docs_dir))
        .with_state(state)
        .layer(CookieManagerLayer::new())
        .layer(TraceLayer::new_for_http());

    let port = std::env::var("PORT")
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(4181);
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    tracing::info!("Eir Stories Rust backend listening on http://{}", address);

    let listener = tokio::net::TcpListener::bind(address).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn initialize_database() -> Result<SqlitePool, Box<dyn std::error::Error>> {
    let storage_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../storage");
    fs::create_dir_all(&storage_dir)?;
    let database_path = storage_dir.join("stories-rust.db");
    let options = SqliteConnectOptions::new()
        .filename(&database_path)
        .create_if_missing(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(10)
        .connect_with(options)
        .await?;

    sqlx::query(
        r#"
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
            source_label text,
            source_url text,
            source_excerpt text,
            source_kind text not null default 'native',
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

        create table if not exists health_imports (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            filename text not null,
            source text not null default '',
            privacy_level text not null default 'pseudonymized',
            patient_name_private text,
            patient_label_public text not null default 'Pseudonymous patient',
            record_count integer not null default 0,
            latest_entry_date text,
            raw_content text not null,
            public_health_md text not null,
            private_health_md text not null,
            story_prompts_json text not null default '[]',
            created_at text not null
        );

        create table if not exists health_sections (
            id integer primary key autoincrement,
            import_id integer not null references health_imports(id) on delete cascade,
            section_key text not null,
            title text not null,
            private_markdown text not null,
            public_markdown text not null,
            visibility text not null default 'private',
            sort_order integer not null default 0,
            unique(import_id, section_key)
        );

        create table if not exists health_examples (
            id integer primary key autoincrement,
            import_id integer not null references health_imports(id) on delete cascade,
            external_entry_id text not null,
            entry_date text,
            public_date text,
            category text not null,
            record_type text not null,
            provider_private text,
            provider_public text,
            responsible_role text,
            summary_private text not null,
            summary_public text not null,
            details_private text,
            details_public text,
            tags_json text not null default '[]',
            visibility text not null default 'private',
            sort_order integer not null default 0
        );
    "#,
    )
    .execute(&pool)
    .await?;

    let _ = sqlx::query("alter table stories add column source_label text")
        .execute(&pool)
        .await;
    let _ = sqlx::query("alter table stories add column source_url text")
        .execute(&pool)
        .await;
    let _ = sqlx::query("alter table stories add column source_excerpt text")
        .execute(&pool)
        .await;
    let _ = sqlx::query("alter table stories add column source_kind text not null default 'native'")
        .execute(&pool)
        .await;

    seed_if_needed(&pool).await?;
    Ok(pool)
}

async fn seed_if_needed(pool: &SqlitePool) -> Result<(), Box<dyn std::error::Error>> {
    let count: i64 = sqlx::query_scalar("select count(*) from users")
        .fetch_one(pool)
        .await?;
    let is_pristine = count == 0;

    let stories_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../docs/data/stories.json");
    let stories_json = fs::read_to_string(stories_path)?;
    let stories: Vec<StorySeed> = match serde_json::from_str(&stories_json) {
        Ok(s) => s,
        Err(e) => {
            tracing::error!("Failed to parse stories.json: {}", e);
            return Err(e.into());
        }
    };
    tracing::info!("Parsed {} stories from stories.json", stories.len());

    let now = now_iso();

    for profile in PROFILE_SEED {
        sqlx::query(
            r#"
            insert or ignore into users (
                email, password_hash, slug, display_name, bio, country, primary_concern,
                profile_mode, visibility, messaging_policy, comment_policy,
                conditions_json, symptom_themes_json, created_at, updated_at
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#,
        )
        .bind(profile.email.to_lowercase())
        .bind(hash(profile.password, DEFAULT_COST)?)
        .bind(profile.slug)
        .bind(profile.display_name)
        .bind(profile.bio)
        .bind(profile.country)
        .bind(profile.primary_concern)
        .bind(profile.profile_mode)
        .bind(profile.visibility)
        .bind(profile.messaging_policy)
        .bind(profile.comment_policy)
        .bind(serde_json::to_string(&profile.conditions)?)
        .bind(serde_json::to_string(&profile.symptom_themes)?)
        .bind(&now)
        .bind(&now)
        .execute(pool)
        .await?;
    }

    for story in &stories {
        let user_id: i64 = match sqlx::query_scalar("select id from users where slug = ?")
            .bind(&story.author_slug)
            .fetch_one(pool)
            .await {
                Ok(id) => id,
                Err(e) => {
                    tracing::error!("Failed to find user for story '{}' (author_slug: '{}'): {}", story.slug, story.author_slug, e);
                    continue;
                }
            };
        sqlx::query(
            r#"
            insert into stories (
                user_id, slug, title, summary, body_json, country, evidence_level,
                journey_stage, conditions_json, symptoms_json, medications_json,
                lessons_json, helped_json, did_not_help_json, timeline_json,
                source_label, source_url, source_excerpt, source_kind,
                status, created_at, updated_at
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'public', ?, ?)
            on conflict(slug) do update set
                user_id = excluded.user_id,
                title = excluded.title,
                summary = excluded.summary,
                body_json = excluded.body_json,
                country = excluded.country,
                evidence_level = excluded.evidence_level,
                journey_stage = excluded.journey_stage,
                conditions_json = excluded.conditions_json,
                symptoms_json = excluded.symptoms_json,
                medications_json = excluded.medications_json,
                lessons_json = excluded.lessons_json,
                helped_json = excluded.helped_json,
                did_not_help_json = excluded.did_not_help_json,
                timeline_json = excluded.timeline_json,
                source_label = excluded.source_label,
                source_url = excluded.source_url,
                source_excerpt = excluded.source_excerpt,
                source_kind = excluded.source_kind,
                status = excluded.status,
                updated_at = excluded.updated_at
        "#,
        )
        .bind(user_id)
        .bind(&story.slug)
        .bind(&story.title)
        .bind(&story.summary)
        .bind(serde_json::to_string(&story.body)?)
        .bind(&story.country)
        .bind(&story.evidence_level)
        .bind(&story.journey_stage)
        .bind(serde_json::to_string(&story.conditions)?)
        .bind(serde_json::to_string(&story.symptoms)?)
        .bind(serde_json::to_string(&story.medications)?)
        .bind(serde_json::to_string(&story.lessons)?)
        .bind(serde_json::to_string(&story.helped)?)
        .bind(serde_json::to_string(&story.did_not_help)?)
        .bind(serde_json::to_string(&story.timeline)?)
        .bind(&story.source_label)
        .bind(&story.source_url)
        .bind(&story.source_excerpt)
        .bind(story.source_kind.clone().unwrap_or_else(|| "native".to_string()))
        .bind(&now)
        .bind(&now)
        .execute(pool)
        .await?;
    }

    if !is_pristine {
        return Ok(());
    }

    let migraine_story_id: i64 = sqlx::query_scalar("select id from stories where slug = ?")
        .bind("living-with-migraine-across-work-and-university")
        .fetch_one(pool)
        .await?;
    let long_covid_story_id: i64 = sqlx::query_scalar("select id from stories where slug = ?")
        .bind("what-changed-after-i-started-tracking-the-setbacks")
        .fetch_one(pool)
        .await?;
    let aino_id = get_user_id_by_slug(pool, "aino").await?;
    let mika_id = get_user_id_by_slug(pool, "mika").await?;
    let jonas_id = get_user_id_by_slug(pool, "jonas").await?;

    for (follower, followed) in [(aino_id, mika_id), (jonas_id, mika_id), (mika_id, aino_id)] {
        sqlx::query("insert into follows (follower_user_id, followed_user_id, created_at) values (?, ?, ?)")
            .bind(follower)
            .bind(followed)
            .bind(&now)
            .execute(pool)
            .await?;
    }

    for (story_id, author_id, body) in [
        (
            migraine_story_id,
            aino_id,
            "Thank you for writing this so plainly. The part about finally having language for the same repeating experience stayed with me.",
        ),
        (
            migraine_story_id,
            jonas_id,
            "I saved this because it shows exactly how a story can be useful without oversharing.",
        ),
        (
            long_covid_story_id,
            mika_id,
            "The point about setbacks being part of the pattern is the part I wish I had understood earlier.",
        ),
    ] {
        sqlx::query("insert into comments (story_id, user_id, body, created_at) values (?, ?, ?, ?)")
            .bind(story_id)
            .bind(author_id)
            .bind(body)
            .bind(&now)
            .execute(pool)
            .await?;
    }

    for (sender_id, recipient_id, body) in [
        (
            aino_id,
            mika_id,
            "Your migraine story helped me rewrite my own timeline before my last appointment. Thank you.",
        ),
        (
            jonas_id,
            aino_id,
            "If you ever want to compare how you structure evidence without making it overwhelming, I would be glad to share what helped me.",
        ),
    ] {
        sqlx::query("insert into messages (sender_user_id, recipient_user_id, body, created_at) values (?, ?, ?, ?)")
            .bind(sender_id)
            .bind(recipient_id)
            .bind(body)
            .bind(&now)
            .execute(pool)
            .await?;
    }

    Ok(())
}

async fn get_user_id_by_slug(pool: &SqlitePool, slug: &str) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar("select id from users where slug = ?")
        .bind(slug)
        .fetch_one(pool)
        .await
}

async fn root() -> Redirect {
    Redirect::temporary("/site/app/")
}

async fn story_view_shell(Path(_draft_id): Path<String>) -> AppResult<Html<String>> {
    let story_view_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../docs/app/story-view.html");
    let html = fs::read_to_string(story_view_path).map_err(internal_error)?;
    Ok(Html(html))
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "ok": true }))
}

async fn me(State(state): State<Arc<AppState>>, cookies: Cookies) -> AppResult<Json<serde_json::Value>> {
    let Some(user) = current_user(&state.pool, &cookies).await? else {
        return Err(AppError::new(StatusCode::UNAUTHORIZED, "Not logged in."));
    };
    Ok(Json(serde_json::json!({ "user": user })))
}

async fn signup(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Json(payload): Json<SignupRequest>,
) -> AppResult<Json<serde_json::Value>> {
    if payload.password.len() < 8 {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "Password must be at least 8 characters."));
    }
    let email = payload.email.trim().to_lowercase();
    if email.is_empty() || payload.display_name.trim().is_empty() {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "Email and display name are required."));
    }

    let existing: Option<i64> = sqlx::query_scalar("select id from users where email = ?")
        .bind(&email)
        .fetch_optional(&state.pool)
        .await
        .map_err(internal_error)?;
    if existing.is_some() {
        return Err(AppError::new(StatusCode::CONFLICT, "An account with that email already exists."));
    }

    let slug = unique_slug(&state.pool, "users", &payload.display_name).await?;
    let now = now_iso();
    let password_hash = hash(&payload.password, DEFAULT_COST).map_err(internal_error)?;

    let insert = sqlx::query(
        r#"
        insert into users (
            email, password_hash, slug, display_name, bio, country, primary_concern,
            profile_mode, visibility, messaging_policy, comment_policy,
            conditions_json, symptom_themes_json, created_at, updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    "#,
    )
    .bind(&email)
    .bind(password_hash)
    .bind(&slug)
    .bind(payload.display_name.trim())
    .bind(payload.bio.clone().unwrap_or_default())
    .bind(payload.country.clone().unwrap_or_default())
    .bind(payload.primary_concern.clone().unwrap_or_default())
    .bind("Pseudonymous")
    .bind("Public")
    .bind(payload.messaging_policy.clone().unwrap_or_else(|| "Open to messages".to_string()))
    .bind(payload.comment_policy.clone().unwrap_or_else(|| "Open".to_string()))
    .bind(serde_json::to_string(&payload.conditions.unwrap_or_default()).map_err(internal_error)?)
    .bind(serde_json::to_string(&payload.symptom_themes.unwrap_or_default()).map_err(internal_error)?)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .map_err(internal_error)?;

    let user_id = insert.last_insert_rowid();
    let session = create_session(&state.pool, user_id).await?;
    set_session_cookie(&cookies, &session);
    let user = get_user_by_id(&state.pool, user_id).await?.ok_or_else(|| AppError::new(StatusCode::INTERNAL_SERVER_ERROR, "Created user was not found."))?;
    Ok(Json(serde_json::json!({ "user": user })))
}

async fn login(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Json(payload): Json<LoginRequest>,
) -> AppResult<Json<serde_json::Value>> {
    let row = sqlx::query("select id, password_hash from users where email = ?")
        .bind(payload.email.trim().to_lowercase())
        .fetch_optional(&state.pool)
        .await
        .map_err(internal_error)?
        .ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "That email and password combination did not work."))?;
    let user_id: i64 = row.get("id");
    let password_hash: String = row.get("password_hash");
    let ok = verify(payload.password, &password_hash).map_err(internal_error)?;
    if !ok {
        return Err(AppError::new(StatusCode::UNAUTHORIZED, "That email and password combination did not work."));
    }

    let session = create_session(&state.pool, user_id).await?;
    set_session_cookie(&cookies, &session);
    let user = get_user_by_id(&state.pool, user_id).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "User not found."))?;
    Ok(Json(serde_json::json!({ "user": user })))
}

async fn logout(State(state): State<Arc<AppState>>, cookies: Cookies) -> AppResult<Json<serde_json::Value>> {
    if let Some(cookie) = cookies.get(SESSION_COOKIE) {
        let token_hash = sha256(cookie.value().to_string());
        sqlx::query("delete from sessions where token_hash = ?")
            .bind(token_hash)
            .execute(&state.pool)
            .await
            .map_err(internal_error)?;
    }
    clear_session_cookie(&cookies);
    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn list_stories(State(state): State<Arc<AppState>>) -> AppResult<Json<Vec<StoryPublic>>> {
    let stories = fetch_public_stories(&state.pool).await?;
    Ok(Json(stories))
}

async fn get_story_handler(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let story = fetch_public_story_by_slug(&state.pool, &slug).await?;
    let comments = fetch_story_comments(&state.pool, story.id).await?;
    Ok(Json(serde_json::json!({
        "story": story,
        "comments": comments
    })))
}

async fn create_story_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Json(payload): Json<CreateStoryRequest>,
) -> AppResult<Json<serde_json::Value>> {
    let user = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    if payload.title.trim().is_empty() || payload.story_text.trim().is_empty() {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "Title and story text are required."));
    }

    let slug = unique_slug(&state.pool, "stories", &payload.title).await?;
    let body: Vec<String> = payload.story_text
        .split("\n\n")
        .map(|part| part.trim().to_string())
        .filter(|part| !part.is_empty())
        .collect();
    if body.is_empty() {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "Write at least one paragraph before publishing."));
    }
    let summary = payload
        .summary
        .clone()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| body.first().cloned().unwrap_or_default());
    let status = match payload.status.as_deref() {
        Some("private") => "private".to_string(),
        _ => "public".to_string(),
    };
    let now = now_iso();

    sqlx::query(
        r#"
        insert into stories (
            user_id, slug, title, summary, body_json, country, evidence_level, journey_stage,
            conditions_json, symptoms_json, medications_json, lessons_json, helped_json, did_not_help_json,
            timeline_json, source_label, source_url, source_excerpt, source_kind, status, created_at, updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', '[]', '[]', '[]', null, null, null, 'native', ?, ?, ?)
    "#,
    )
    .bind(user.id)
    .bind(&slug)
    .bind(payload.title.trim())
    .bind(summary)
    .bind(serde_json::to_string(&body).map_err(internal_error)?)
    .bind(payload.country.unwrap_or_else(|| user.country.clone()))
    .bind(payload.evidence_level.unwrap_or_else(|| "Narrative only".to_string()))
    .bind(payload.journey_stage.unwrap_or_else(|| "Ongoing".to_string()))
    .bind(serde_json::to_string(&payload.conditions.unwrap_or_default()).map_err(internal_error)?)
    .bind(serde_json::to_string(&payload.symptoms.unwrap_or_default()).map_err(internal_error)?)
    .bind(serde_json::to_string(&payload.medications.unwrap_or_default()).map_err(internal_error)?)
    .bind(&status)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .map_err(internal_error)?;

    if status == "public" {
        let story = fetch_public_story_by_slug(&state.pool, &slug).await?;
        Ok(Json(serde_json::json!({ "story": story })))
    } else {
        Ok(Json(serde_json::json!({ "story": { "slug": slug, "status": status } })))
    }
}

async fn add_comment_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Path(slug): Path<String>,
    Json(payload): Json<CommentRequest>,
) -> AppResult<Json<CommentPublic>> {
    let user = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    let body = payload.body.trim();
    if body.is_empty() {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "Write a comment before posting."));
    }
    let story_id: i64 = sqlx::query_scalar("select id from stories where slug = ? and status = 'public'")
        .bind(&slug)
        .fetch_optional(&state.pool)
        .await
        .map_err(internal_error)?
        .ok_or_else(|| AppError::new(StatusCode::NOT_FOUND, "Story not found."))?;
    let now = now_iso();
    let insert = sqlx::query("insert into comments (story_id, user_id, body, created_at) values (?, ?, ?, ?)")
        .bind(story_id)
        .bind(user.id)
        .bind(body)
        .bind(&now)
        .execute(&state.pool)
        .await
        .map_err(internal_error)?;
    let comment_id = insert.last_insert_rowid();
    let comment = sqlx::query(
        r#"
        select comments.id, comments.body, comments.created_at, users.display_name as author_name, users.slug as author_slug
        from comments
        join users on users.id = comments.user_id
        where comments.id = ?
    "#,
    )
    .bind(comment_id)
    .fetch_one(&state.pool)
    .await
    .map_err(internal_error)?;
    Ok(Json(CommentPublic {
        id: comment.get("id"),
        body: comment.get("body"),
        created_at: comment.get("created_at"),
        author_name: comment.get("author_name"),
        author_slug: comment.get("author_slug"),
    }))
}

async fn list_profiles_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
) -> AppResult<Json<Vec<ProfileSummary>>> {
    let current = current_user(&state.pool, &cookies).await?;
    let profiles = fetch_profiles(&state.pool, current.as_ref().map(|user| user.id)).await?;
    Ok(Json(profiles))
}

async fn get_profile_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Path(slug): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let current = current_user(&state.pool, &cookies).await?;
    let profile = fetch_profile_by_slug(&state.pool, &slug, current.as_ref().map(|user| user.id)).await?;
    let stories = fetch_public_stories_by_user(&state.pool, profile.id).await?;
    let health_imports = fetch_public_health_imports_for_user(&state.pool, profile.id).await?;
    Ok(Json(serde_json::json!({
        "profile": profile,
        "stories": stories,
        "health_imports": health_imports
    })))
}

async fn toggle_follow_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Path(slug): Path<String>,
) -> AppResult<Json<FollowResponse>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    let target_id: i64 = sqlx::query_scalar("select id from users where slug = ?")
        .bind(&slug)
        .fetch_optional(&state.pool)
        .await
        .map_err(internal_error)?
        .ok_or_else(|| AppError::new(StatusCode::NOT_FOUND, "Profile not found."))?;
    if target_id == current.id {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "You cannot follow yourself."));
    }
    let existing: Option<i64> = sqlx::query_scalar("select id from follows where follower_user_id = ? and followed_user_id = ?")
        .bind(current.id)
        .bind(target_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(internal_error)?;
    let is_following = if let Some(follow_id) = existing {
        sqlx::query("delete from follows where id = ?")
            .bind(follow_id)
            .execute(&state.pool)
            .await
            .map_err(internal_error)?;
        false
    } else {
        sqlx::query("insert into follows (follower_user_id, followed_user_id, created_at) values (?, ?, ?)")
            .bind(current.id)
            .bind(target_id)
            .bind(now_iso())
            .execute(&state.pool)
            .await
            .map_err(internal_error)?;
        true
    };
    Ok(Json(FollowResponse { is_following }))
}

async fn create_message_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Path(slug): Path<String>,
    Json(payload): Json<MessageRequest>,
) -> AppResult<Json<serde_json::Value>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    let recipient_id: i64 = sqlx::query_scalar("select id from users where slug = ?")
        .bind(&slug)
        .fetch_optional(&state.pool)
        .await
        .map_err(internal_error)?
        .ok_or_else(|| AppError::new(StatusCode::NOT_FOUND, "Profile not found."))?;
    if recipient_id == current.id {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "You cannot send a message to yourself."));
    }
    let body = payload.body.trim();
    if body.is_empty() {
        return Err(AppError::new(StatusCode::BAD_REQUEST, "Write a message before sending."));
    }
    let now = now_iso();
    sqlx::query("insert into messages (sender_user_id, recipient_user_id, body, created_at) values (?, ?, ?, ?)")
        .bind(current.id)
        .bind(recipient_id)
        .bind(body)
        .bind(&now)
        .execute(&state.pool)
        .await
        .map_err(internal_error)?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn list_messages_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
) -> AppResult<Json<Vec<MessagePublic>>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    let rows = sqlx::query(
        r#"
        select
            messages.id,
            messages.body,
            messages.created_at,
            sender.display_name as sender_name,
            sender.slug as sender_slug,
            recipient.display_name as recipient_name,
            case when messages.recipient_user_id = ? then 'inbound' else 'outbound' end as direction
        from messages
        join users as sender on sender.id = messages.sender_user_id
        join users as recipient on recipient.id = messages.recipient_user_id
        where messages.recipient_user_id = ?
           or messages.sender_user_id = ?
        order by messages.created_at desc, messages.id desc
    "#,
    )
    .bind(current.id)
    .bind(current.id)
    .bind(current.id)
    .fetch_all(&state.pool)
    .await
    .map_err(internal_error)?;

    let messages = rows
        .into_iter()
        .map(|row| MessagePublic {
            id: row.get("id"),
            body: row.get("body"),
            created_at: row.get("created_at"),
            sender_name: row.get("sender_name"),
            sender_slug: row.get("sender_slug"),
            recipient_name: row.get("recipient_name"),
            direction: row.get("direction"),
        })
        .collect();
    Ok(Json(messages))
}

async fn import_health_file_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    mut multipart: Multipart,
) -> AppResult<Json<serde_json::Value>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    let mut filename = "import.eir".to_string();
    let mut contents = None;

    while let Some(field) = multipart.next_field().await.map_err(internal_error)? {
        if field.name() == Some("file") {
            if let Some(name) = field.file_name() {
                filename = name.to_string();
            }
            let bytes = field.bytes().await.map_err(internal_error)?;
            contents = Some(String::from_utf8(bytes.to_vec()).map_err(internal_error)?);
        }
    }

    let contents = contents.ok_or_else(|| AppError::new(StatusCode::BAD_REQUEST, "Attach a .eir file in the `file` field."))?;
    let bundle = parse_and_transform_eir(&contents).map_err(|error| AppError::new(StatusCode::BAD_REQUEST, error))?;
    let import_id = store_health_import(&state.pool, current.id, &filename, &contents, &bundle).await?;
    sync_user_profile_from_import(&state.pool, current.id, &bundle).await?;
    let import = fetch_health_import_by_id(&state.pool, import_id, current.id, true).await?;
    Ok(Json(serde_json::json!({ "import": import })))
}

async fn preview_health_file_handler(
    mut multipart: Multipart,
) -> AppResult<Json<serde_json::Value>> {
    let mut filename = "health-record.eir".to_string();
    let mut contents = None;

    while let Some(field) = multipart.next_field().await.map_err(internal_error)? {
        if field.name() == Some("file") {
            if let Some(name) = field.file_name() {
                filename = name.to_string();
            }
            let bytes = field.bytes().await.map_err(internal_error)?;
            contents = Some(String::from_utf8(bytes.to_vec()).map_err(internal_error)?);
        }
    }

    let contents = contents.ok_or_else(|| AppError::new(StatusCode::BAD_REQUEST, "Attach a health record file in the `file` field."))?;
    let bundle = parse_and_transform_eir(&contents).map_err(|error| AppError::new(StatusCode::BAD_REQUEST, error))?;
    let preview = build_health_import_preview(&filename, &bundle, true);
    Ok(Json(serde_json::json!({ "preview": preview })))
}

async fn list_health_imports_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
) -> AppResult<Json<Vec<HealthImportPublic>>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    let import_ids = sqlx::query_scalar::<_, i64>("select id from health_imports where user_id = ? order by created_at desc, id desc")
        .bind(current.id)
        .fetch_all(&state.pool)
        .await
        .map_err(internal_error)?;
    let mut imports = Vec::new();
    for import_id in import_ids {
        imports.push(fetch_health_import_by_id(&state.pool, import_id, current.id, true).await?);
    }
    Ok(Json(imports))
}

async fn get_health_import_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Path(id): Path<i64>,
) -> AppResult<Json<HealthImportPublic>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    let import = fetch_health_import_by_id(&state.pool, id, current.id, true).await?;
    Ok(Json(import))
}

async fn update_health_section_visibility_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Path((id, section_id)): Path<(i64, i64)>,
    Json(payload): Json<VisibilityRequest>,
) -> AppResult<Json<serde_json::Value>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    validate_import_owner(&state.pool, id, current.id).await?;
    let visibility = normalize_visibility(&payload.visibility)?;
    sqlx::query("update health_sections set visibility = ? where id = ? and import_id = ?")
        .bind(&visibility)
        .bind(section_id)
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(internal_error)?;
    let import = fetch_health_import_by_id(&state.pool, id, current.id, true).await?;
    Ok(Json(serde_json::json!({ "import": import })))
}

async fn update_health_example_visibility_handler(
    State(state): State<Arc<AppState>>,
    cookies: Cookies,
    Path((id, example_id)): Path<(i64, i64)>,
    Json(payload): Json<VisibilityRequest>,
) -> AppResult<Json<serde_json::Value>> {
    let current = current_user(&state.pool, &cookies).await?.ok_or_else(|| AppError::new(StatusCode::UNAUTHORIZED, "Log in first."))?;
    validate_import_owner(&state.pool, id, current.id).await?;
    let visibility = normalize_visibility(&payload.visibility)?;
    sqlx::query("update health_examples set visibility = ? where id = ? and import_id = ?")
        .bind(&visibility)
        .bind(example_id)
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(internal_error)?;
    let import = fetch_health_import_by_id(&state.pool, id, current.id, true).await?;
    Ok(Json(serde_json::json!({ "import": import })))
}

async fn current_user(pool: &SqlitePool, cookies: &Cookies) -> AppResult<Option<UserPublic>> {
    let Some(cookie) = cookies.get(SESSION_COOKIE) else {
        return Ok(None);
    };
    let now = now_iso();
    sqlx::query("delete from sessions where expires_at <= ?")
        .bind(&now)
        .execute(pool)
        .await
        .map_err(internal_error)?;
    let user_id = sqlx::query_scalar::<_, i64>("select user_id from sessions where token_hash = ? and expires_at > ?")
        .bind(sha256(cookie.value().to_string()))
        .bind(&now)
        .fetch_optional(pool)
        .await
        .map_err(internal_error)?;
    match user_id {
        Some(id) => get_user_by_id(pool, id).await,
        None => Ok(None),
    }
}

async fn validate_import_owner(pool: &SqlitePool, import_id: i64, user_id: i64) -> AppResult<()> {
    let owner: Option<i64> = sqlx::query_scalar("select user_id from health_imports where id = ?")
        .bind(import_id)
        .fetch_optional(pool)
        .await
        .map_err(internal_error)?;
    match owner {
        Some(found) if found == user_id => Ok(()),
        Some(_) => Err(AppError::new(StatusCode::FORBIDDEN, "You do not own this import.")),
        None => Err(AppError::new(StatusCode::NOT_FOUND, "Health import not found.")),
    }
}

async fn store_health_import(
    pool: &SqlitePool,
    user_id: i64,
    filename: &str,
    raw_content: &str,
    bundle: &ImportedHealthBundle,
) -> AppResult<i64> {
    let created_at = now_iso();
    let insert = sqlx::query(
        r#"
        insert into health_imports (
            user_id, filename, source, privacy_level, patient_name_private, patient_label_public,
            record_count, latest_entry_date, raw_content, public_health_md, private_health_md,
            story_prompts_json, created_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    "#,
    )
    .bind(user_id)
    .bind(filename)
    .bind(&bundle.source)
    .bind(&bundle.privacy_level)
    .bind(&bundle.patient_name_private)
    .bind(&bundle.patient_label_public)
    .bind(bundle.record_count as i64)
    .bind(&bundle.latest_entry_date)
    .bind(raw_content)
    .bind(&bundle.public_health_md)
    .bind(&bundle.private_health_md)
    .bind(serde_json::to_string(&bundle.story_prompts).map_err(internal_error)?)
    .bind(&created_at)
    .execute(pool)
    .await
    .map_err(internal_error)?;
    let import_id = insert.last_insert_rowid();

    for section in &bundle.sections {
        insert_health_section(pool, import_id, section).await?;
    }
    for example in &bundle.examples {
        insert_health_example(pool, import_id, example).await?;
    }

    Ok(import_id)
}

async fn insert_health_section(pool: &SqlitePool, import_id: i64, section: &HealthSectionDraft) -> AppResult<()> {
    sqlx::query(
        r#"
        insert into health_sections (
            import_id, section_key, title, private_markdown, public_markdown, visibility, sort_order
        ) values (?, ?, ?, ?, ?, ?, ?)
    "#,
    )
    .bind(import_id)
    .bind(&section.key)
    .bind(&section.title)
    .bind(&section.private_markdown)
    .bind(&section.public_markdown)
    .bind(&section.visibility)
    .bind(section.sort_order)
    .execute(pool)
    .await
    .map_err(internal_error)?;
    Ok(())
}

async fn insert_health_example(pool: &SqlitePool, import_id: i64, example: &HealthExampleDraft) -> AppResult<()> {
    sqlx::query(
        r#"
        insert into health_examples (
            import_id, external_entry_id, entry_date, public_date, category, record_type,
            provider_private, provider_public, responsible_role, summary_private, summary_public,
            details_private, details_public, tags_json, visibility, sort_order
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    "#,
    )
    .bind(import_id)
    .bind(&example.external_entry_id)
    .bind(&example.entry_date)
    .bind(&example.public_date)
    .bind(&example.category)
    .bind(&example.record_type)
    .bind(&example.provider_private)
    .bind(&example.provider_public)
    .bind(&example.responsible_role)
    .bind(&example.summary_private)
    .bind(&example.summary_public)
    .bind(&example.details_private)
    .bind(&example.details_public)
    .bind(serde_json::to_string(&example.tags).map_err(internal_error)?)
    .bind(&example.visibility)
    .bind(example.sort_order)
    .execute(pool)
    .await
    .map_err(internal_error)?;
    Ok(())
}

async fn sync_user_profile_from_import(pool: &SqlitePool, user_id: i64, bundle: &ImportedHealthBundle) -> AppResult<()> {
    let current = get_user_by_id(pool, user_id)
        .await?
        .ok_or_else(|| AppError::new(StatusCode::NOT_FOUND, "User not found."))?;
    let inferred_conditions = bundle
        .examples
        .iter()
        .filter(|example| example.category.eq_ignore_ascii_case("Diagnoser"))
        .map(|example| example.summary_public.clone())
        .take(4)
        .collect::<Vec<_>>();
    let inferred_tags = bundle
        .examples
        .iter()
        .flat_map(|example| example.tags.clone())
        .filter(|tag| !matches!(tag.as_str(), "diagnoser" | "diagnos" | "anteckningar" | "vårdkontakter"))
        .take(8)
        .collect::<Vec<_>>();

    let merged_conditions = merge_unique_strings(current.conditions, inferred_conditions);
    let merged_symptom_themes = merge_unique_strings(current.symptom_themes, inferred_tags);
    let next_primary_concern = if current.primary_concern.trim().is_empty() {
        merged_conditions
            .first()
            .cloned()
            .unwrap_or_else(|| bundle.source.clone())
    } else {
        current.primary_concern
    };

    sqlx::query(
        "update users set primary_concern = ?, conditions_json = ?, symptom_themes_json = ?, updated_at = ? where id = ?",
    )
    .bind(next_primary_concern)
    .bind(serde_json::to_string(&merged_conditions).map_err(internal_error)?)
    .bind(serde_json::to_string(&merged_symptom_themes).map_err(internal_error)?)
    .bind(now_iso())
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(internal_error)?;
    Ok(())
}

async fn fetch_health_import_by_id(
    pool: &SqlitePool,
    import_id: i64,
    viewer_user_id: i64,
    include_private: bool,
) -> AppResult<HealthImportPublic> {
    let row = sqlx::query(
        r#"
        select id, user_id, filename, source, privacy_level, patient_label_public, record_count,
               latest_entry_date, public_health_md, private_health_md, story_prompts_json, created_at
        from health_imports
        where id = ?
        limit 1
    "#,
    )
    .bind(import_id)
    .fetch_optional(pool)
    .await
    .map_err(internal_error)?
    .ok_or_else(|| AppError::new(StatusCode::NOT_FOUND, "Health import not found."))?;
    let owner_id: i64 = row.get("user_id");
    let can_view_private = include_private && owner_id == viewer_user_id;

    let sections = fetch_health_sections(pool, import_id, can_view_private).await?;
    let examples = fetch_health_examples(pool, import_id, can_view_private).await?;
    let public_health_md = if can_view_private {
        row.get("public_health_md")
    } else {
        sections
            .iter()
            .map(|section| section.markdown.clone())
            .collect::<Vec<_>>()
            .join("\n")
    };

    Ok(HealthImportPublic {
        id: row.get("id"),
        filename: row.get("filename"),
        source: row.get("source"),
        privacy_level: row.get("privacy_level"),
        patient_label_public: row.get("patient_label_public"),
        record_count: row.get("record_count"),
        latest_entry_date: row.get("latest_entry_date"),
        created_at: row.get("created_at"),
        public_health_md,
        private_health_md: if can_view_private { Some(row.get("private_health_md")) } else { None },
        story_prompts: parse_json_vec(&row.get::<String, _>("story_prompts_json")),
        sections,
        examples,
    })
}

async fn fetch_health_sections(
    pool: &SqlitePool,
    import_id: i64,
    include_private: bool,
) -> AppResult<Vec<HealthSectionPublic>> {
    let query = if include_private {
        "select id, section_key, title, private_markdown, public_markdown, visibility, sort_order from health_sections where import_id = ? order by sort_order asc, id asc"
    } else {
        "select id, section_key, title, private_markdown, public_markdown, visibility, sort_order from health_sections where import_id = ? and visibility = 'public' order by sort_order asc, id asc"
    };
    let rows = sqlx::query(query)
        .bind(import_id)
        .fetch_all(pool)
        .await
        .map_err(internal_error)?;
    Ok(rows
        .into_iter()
        .map(|row| {
            let public_markdown: String = row.get("public_markdown");
            let private_markdown: String = row.get("private_markdown");
            HealthSectionPublic {
                id: row.get("id"),
                section_key: row.get("section_key"),
                title: row.get("title"),
                visibility: row.get("visibility"),
                markdown: if include_private { private_markdown.clone() } else { public_markdown.clone() },
                private_markdown: if include_private { Some(private_markdown) } else { None },
                sort_order: row.get("sort_order"),
            }
        })
        .collect())
}

async fn fetch_health_examples(
    pool: &SqlitePool,
    import_id: i64,
    include_private: bool,
) -> AppResult<Vec<HealthExamplePublic>> {
    let query = if include_private {
        "select id, external_entry_id, entry_date, public_date, category, record_type, provider_private, provider_public, responsible_role, summary_private, summary_public, details_private, details_public, tags_json, visibility, sort_order from health_examples where import_id = ? order by sort_order asc, id asc"
    } else {
        "select id, external_entry_id, entry_date, public_date, category, record_type, provider_private, provider_public, responsible_role, summary_private, summary_public, details_private, details_public, tags_json, visibility, sort_order from health_examples where import_id = ? and visibility = 'public' order by sort_order asc, id asc"
    };
    let rows = sqlx::query(query)
        .bind(import_id)
        .fetch_all(pool)
        .await
        .map_err(internal_error)?;
    Ok(rows
        .into_iter()
        .map(|row| {
            let summary_public: String = row.get("summary_public");
            let summary_private: String = row.get("summary_private");
            let details_public: Option<String> = row.get("details_public");
            let details_private: Option<String> = row.get("details_private");
            let provider_public: Option<String> = row.get("provider_public");
            let provider_private: Option<String> = row.get("provider_private");
            HealthExamplePublic {
                id: row.get("id"),
                external_entry_id: row.get("external_entry_id"),
                entry_date: if include_private { row.get("entry_date") } else { None },
                public_date: row.get("public_date"),
                category: row.get("category"),
                record_type: row.get("record_type"),
                provider: if include_private { provider_private.clone() } else { provider_public.clone() },
                provider_private: if include_private { provider_private } else { None },
                responsible_role: row.get("responsible_role"),
                summary: if include_private { summary_private.clone() } else { summary_public.clone() },
                summary_private: if include_private { Some(summary_private) } else { None },
                details: if include_private { details_private.clone() } else { details_public.clone() },
                details_private: if include_private { details_private } else { None },
                tags: parse_json_vec(&row.get::<String, _>("tags_json")),
                visibility: row.get("visibility"),
                sort_order: row.get("sort_order"),
            }
        })
        .collect())
}

async fn fetch_public_health_imports_for_user(pool: &SqlitePool, user_id: i64) -> AppResult<Vec<HealthImportPublic>> {
    let import_ids = sqlx::query_scalar::<_, i64>("select id from health_imports where user_id = ? order by created_at desc, id desc")
        .bind(user_id)
        .fetch_all(pool)
        .await
        .map_err(internal_error)?;
    let mut imports = Vec::new();
    for import_id in import_ids {
        let import = fetch_health_import_by_id(pool, import_id, user_id + 1_000_000_000, false).await?;
        if !import.sections.is_empty() || !import.examples.is_empty() {
            imports.push(import);
        }
    }
    Ok(imports)
}

fn build_health_import_preview(
    filename: &str,
    bundle: &ImportedHealthBundle,
    include_private: bool,
) -> HealthImportPublic {
    let sections = bundle
        .sections
        .iter()
        .filter(|section| include_private || section.visibility == "public")
        .map(|section| HealthSectionPublic {
            id: 0,
            section_key: section.key.clone(),
            title: section.title.clone(),
            visibility: section.visibility.clone(),
            markdown: if include_private {
                section.private_markdown.clone()
            } else {
                section.public_markdown.clone()
            },
            private_markdown: if include_private {
                Some(section.private_markdown.clone())
            } else {
                None
            },
            sort_order: section.sort_order,
        })
        .collect::<Vec<_>>();

    let examples = bundle
        .examples
        .iter()
        .filter(|example| include_private || example.visibility == "public")
        .map(|example| HealthExamplePublic {
            id: 0,
            external_entry_id: example.external_entry_id.clone(),
            entry_date: if include_private { example.entry_date.clone() } else { None },
            public_date: example.public_date.clone(),
            category: example.category.clone(),
            record_type: example.record_type.clone(),
            provider: if include_private {
                example.provider_private.clone()
            } else {
                example.provider_public.clone()
            },
            provider_private: if include_private {
                example.provider_private.clone()
            } else {
                None
            },
            responsible_role: example.responsible_role.clone(),
            summary: if include_private {
                example.summary_private.clone()
            } else {
                example.summary_public.clone()
            },
            summary_private: if include_private {
                Some(example.summary_private.clone())
            } else {
                None
            },
            details: if include_private {
                example.details_private.clone()
            } else {
                example.details_public.clone()
            },
            details_private: if include_private {
                example.details_private.clone()
            } else {
                None
            },
            tags: example.tags.clone(),
            visibility: example.visibility.clone(),
            sort_order: example.sort_order,
        })
        .collect::<Vec<_>>();

    HealthImportPublic {
        id: 0,
        filename: filename.to_string(),
        source: bundle.source.clone(),
        privacy_level: bundle.privacy_level.clone(),
        patient_label_public: bundle.patient_label_public.clone(),
        record_count: bundle.record_count as i64,
        latest_entry_date: bundle.latest_entry_date.clone(),
        created_at: now_iso(),
        public_health_md: if include_private {
            bundle.private_health_md.clone()
        } else {
            sections.iter().map(|section| section.markdown.clone()).collect::<Vec<_>>().join("\n")
        },
        private_health_md: if include_private {
            Some(bundle.private_health_md.clone())
        } else {
            None
        },
        story_prompts: bundle.story_prompts.clone(),
        sections,
        examples,
    }
}

async fn get_user_by_id(pool: &SqlitePool, id: i64) -> AppResult<Option<UserPublic>> {
    let row = sqlx::query_as::<_, UserRow>("select id, email, slug, display_name, bio, country, primary_concern, profile_mode, visibility, messaging_policy, comment_policy, conditions_json, symptom_themes_json, created_at, updated_at from users where id = ?")
        .bind(id)
        .fetch_optional(pool)
        .await
        .map_err(internal_error)?;
    Ok(row.map(map_user))
}

async fn create_session(pool: &SqlitePool, user_id: i64) -> AppResult<SessionData> {
    let token = Uuid::new_v4().to_string();
    let expires_at = OffsetDateTime::now_utc() + Duration::days(30);
    sqlx::query("insert into sessions (user_id, token_hash, created_at, expires_at) values (?, ?, ?, ?)")
        .bind(user_id)
        .bind(sha256(token.clone()))
        .bind(now_iso())
        .bind(expires_at.format(&time::format_description::well_known::Rfc3339).map_err(internal_error)?)
        .execute(pool)
        .await
        .map_err(internal_error)?;
    Ok(SessionData { token, expires_at })
}

struct SessionData {
    token: String,
    expires_at: OffsetDateTime,
}

fn set_session_cookie(cookies: &Cookies, session: &SessionData) {
    let cookie = Cookie::build((SESSION_COOKIE, session.token.clone()))
        .path("/")
        .http_only(true)
        .same_site(tower_cookies::cookie::SameSite::Lax)
        .expires(session.expires_at)
        .build();
    cookies.add(cookie);
}

fn clear_session_cookie(cookies: &Cookies) {
    let cookie = Cookie::build((SESSION_COOKIE, ""))
        .path("/")
        .expires(OffsetDateTime::now_utc() - Duration::days(1))
        .build();
    cookies.remove(cookie);
}

async fn fetch_public_stories(pool: &SqlitePool) -> AppResult<Vec<StoryPublic>> {
    let rows = sqlx::query(
        r#"
        select
            stories.*,
            users.display_name as author_name,
            users.slug as author_slug,
            (select count(*) from comments where story_id = stories.id) as comment_count
        from stories
        join users on users.id = stories.user_id
        where stories.status = 'public'
        order by stories.created_at desc, stories.id desc
    "#,
    )
    .fetch_all(pool)
    .await
    .map_err(internal_error)?;
    tracing::info!("fetch_public_stories: {} rows from DB", rows.len());
    let mut stories = Vec::new();
    for row in rows {
        match map_story_from_row(row) {
            Ok(story) => stories.push(story),
            Err(e) => tracing::error!("Failed to map story row: {:?}", e),
        }
    }
    Ok(stories)
}

async fn fetch_public_story_by_slug(pool: &SqlitePool, slug: &str) -> AppResult<StoryPublic> {
    let row = sqlx::query(
        r#"
        select
            stories.*,
            users.display_name as author_name,
            users.slug as author_slug,
            (select count(*) from comments where story_id = stories.id) as comment_count
        from stories
        join users on users.id = stories.user_id
        where stories.slug = ?
          and stories.status = 'public'
        limit 1
    "#,
    )
    .bind(slug)
    .fetch_optional(pool)
    .await
    .map_err(internal_error)?
    .ok_or_else(|| AppError::new(StatusCode::NOT_FOUND, "Story not found."))?;
    map_story_from_row(row)
}

async fn fetch_story_comments(pool: &SqlitePool, story_id: i64) -> AppResult<Vec<CommentPublic>> {
    let rows = sqlx::query(
        r#"
        select comments.id, comments.body, comments.created_at, users.display_name as author_name, users.slug as author_slug
        from comments
        join users on users.id = comments.user_id
        where comments.story_id = ?
        order by comments.created_at asc, comments.id asc
    "#,
    )
    .bind(story_id)
    .fetch_all(pool)
    .await
    .map_err(internal_error)?;
    Ok(rows
        .into_iter()
        .map(|row| CommentPublic {
            id: row.get("id"),
            body: row.get("body"),
            created_at: row.get("created_at"),
            author_name: row.get("author_name"),
            author_slug: row.get("author_slug"),
        })
        .collect())
}

async fn fetch_profiles(pool: &SqlitePool, current_user_id: Option<i64>) -> AppResult<Vec<ProfileSummary>> {
    let current_id = current_user_id.unwrap_or_default();
    let rows = sqlx::query(
        r#"
        select
            users.*,
            (select count(*) from follows where followed_user_id = users.id) as follower_count,
            (select count(*) from stories where user_id = users.id and status = 'public') as story_count,
            exists(
                select 1 from follows where follower_user_id = ? and followed_user_id = users.id
            ) as is_following
        from users
        order by follower_count desc, users.display_name asc
    "#,
    )
    .bind(current_id)
    .fetch_all(pool)
    .await
    .map_err(internal_error)?;
    rows.into_iter().map(map_profile_from_row).collect()
}

async fn fetch_profile_by_slug(pool: &SqlitePool, slug: &str, current_user_id: Option<i64>) -> AppResult<ProfileSummary> {
    let current_id = current_user_id.unwrap_or_default();
    let row = sqlx::query(
        r#"
        select
            users.*,
            (select count(*) from follows where followed_user_id = users.id) as follower_count,
            (select count(*) from stories where user_id = users.id and status = 'public') as story_count,
            exists(
                select 1 from follows where follower_user_id = ? and followed_user_id = users.id
            ) as is_following
        from users
        where users.slug = ?
        limit 1
    "#,
    )
    .bind(current_id)
    .bind(slug)
    .fetch_optional(pool)
    .await
    .map_err(internal_error)?
    .ok_or_else(|| AppError::new(StatusCode::NOT_FOUND, "Profile not found."))?;
    map_profile_from_row(row)
}

async fn fetch_public_stories_by_user(pool: &SqlitePool, user_id: i64) -> AppResult<Vec<StoryPublic>> {
    let rows = sqlx::query(
        r#"
        select
            stories.*,
            users.display_name as author_name,
            users.slug as author_slug,
            (select count(*) from comments where story_id = stories.id) as comment_count
        from stories
        join users on users.id = stories.user_id
        where stories.user_id = ?
          and stories.status = 'public'
        order by stories.created_at desc, stories.id desc
    "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(internal_error)?;
    rows.into_iter().map(map_story_from_row).collect()
}

fn map_user(row: UserRow) -> UserPublic {
    UserPublic {
        id: row.id,
        email: row.email,
        slug: row.slug,
        display_name: row.display_name,
        bio: row.bio,
        country: row.country,
        primary_concern: row.primary_concern,
        profile_mode: row.profile_mode,
        visibility: row.visibility,
        messaging_policy: row.messaging_policy,
        comment_policy: row.comment_policy,
        conditions: parse_json_vec(&row.conditions_json),
        symptom_themes: parse_json_vec(&row.symptom_themes_json),
        created_at: row.created_at,
        updated_at: row.updated_at,
    }
}

fn map_story_from_row(row: sqlx::sqlite::SqliteRow) -> AppResult<StoryPublic> {
    let row = StoryRow {
        id: row.get("id"),
        user_id: row.get("user_id"),
        slug: row.get("slug"),
        title: row.get("title"),
        summary: row.get("summary"),
        body_json: row.get("body_json"),
        country: row.get("country"),
        evidence_level: row.get("evidence_level"),
        journey_stage: row.get("journey_stage"),
        conditions_json: row.get("conditions_json"),
        symptoms_json: row.get("symptoms_json"),
        medications_json: row.get("medications_json"),
        lessons_json: row.get("lessons_json"),
        helped_json: row.get("helped_json"),
        did_not_help_json: row.get("did_not_help_json"),
        timeline_json: row.get("timeline_json"),
        source_label: row.get("source_label"),
        source_url: row.get("source_url"),
        source_excerpt: row.get("source_excerpt"),
        source_kind: row.get("source_kind"),
        status: row.get("status"),
        created_at: row.get("created_at"),
        updated_at: row.get("updated_at"),
        author_name: row.get("author_name"),
        author_slug: row.get("author_slug"),
        comment_count: row.get("comment_count"),
    };

    let _ = row.user_id;
    let _ = &row.status;

    Ok(StoryPublic {
        id: row.id,
        slug: row.slug,
        title: row.title,
        summary: row.summary,
        body: parse_json_vec(&row.body_json),
        country: row.country,
        evidence_level: row.evidence_level,
        journey_stage: row.journey_stage,
        conditions: parse_json_vec(&row.conditions_json),
        symptoms: parse_json_vec(&row.symptoms_json),
        medications: parse_json_vec(&row.medications_json),
        lessons: parse_json_vec(&row.lessons_json),
        helped: parse_json_vec(&row.helped_json),
        did_not_help: parse_json_vec(&row.did_not_help_json),
        timeline: parse_json_timeline(&row.timeline_json)?,
        source_label: row.source_label,
        source_url: row.source_url,
        source_excerpt: row.source_excerpt,
        source_kind: row.source_kind,
        created_at: row.created_at,
        updated_at: row.updated_at,
        author_name: row.author_name,
        author_slug: row.author_slug,
        comment_count: row.comment_count,
    })
}

fn map_profile_from_row(row: sqlx::sqlite::SqliteRow) -> AppResult<ProfileSummary> {
    Ok(ProfileSummary {
        id: row.get("id"),
        slug: row.get("slug"),
        display_name: row.get("display_name"),
        bio: row.get("bio"),
        country: row.get("country"),
        primary_concern: row.get("primary_concern"),
        profile_mode: row.get("profile_mode"),
        visibility: row.get("visibility"),
        messaging_policy: row.get("messaging_policy"),
        comment_policy: row.get("comment_policy"),
        conditions: parse_json_vec(&row.get::<String, _>("conditions_json")),
        symptom_themes: parse_json_vec(&row.get::<String, _>("symptom_themes_json")),
        follower_count: row.get("follower_count"),
        story_count: row.get("story_count"),
        is_following: row.get::<i64, _>("is_following") != 0,
    })
}

fn parse_json_vec(value: &str) -> Vec<String> {
    serde_json::from_str(value).unwrap_or_default()
}

fn parse_json_timeline(value: &str) -> AppResult<Vec<TimelineEntry>> {
    serde_json::from_str(value).map_err(internal_error)
}

fn normalize_visibility(value: &str) -> AppResult<String> {
    let normalized = value.trim().to_lowercase();
    match normalized.as_str() {
        "public" | "private" => Ok(normalized),
        _ => Err(AppError::new(StatusCode::BAD_REQUEST, "Visibility must be either `public` or `private`.")),
    }
}

fn merge_unique_strings(existing: Vec<String>, incoming: Vec<String>) -> Vec<String> {
    let mut merged = existing;
    for value in incoming {
        if value.trim().is_empty() {
            continue;
        }
        if !merged.iter().any(|item| item.eq_ignore_ascii_case(&value)) {
            merged.push(value);
        }
    }
    merged
}

fn sha256(value: String) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn now_iso() -> String {
    OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}

async fn unique_slug(pool: &SqlitePool, table: &str, input: &str) -> AppResult<String> {
    let base = slugify(input);
    let mut candidate = base.clone();
    let mut index = 2;
    loop {
        let sql = format!("select 1 from {} where slug = ? limit 1", table);
        let exists: Option<i64> = sqlx::query_scalar(&sql)
            .bind(&candidate)
            .fetch_optional(pool)
            .await
            .map_err(internal_error)?;
        if exists.is_none() {
            return Ok(candidate);
        }
        candidate = format!("{}-{}", base, index);
        index += 1;
    }
}

fn slugify(value: &str) -> String {
    let slug = value
        .trim()
        .to_lowercase()
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    if slug.is_empty() {
        "story".to_string()
    } else {
        slug
    }
}

fn internal_error<E: std::fmt::Display>(error: E) -> AppError {
    AppError::new(StatusCode::INTERNAL_SERVER_ERROR, error.to_string())
}
