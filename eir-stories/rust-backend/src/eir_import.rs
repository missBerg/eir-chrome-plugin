use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct EirDocument {
    pub metadata: Option<EirMetadata>,
    #[serde(default)]
    pub entries: Vec<EirEntry>,
}

#[derive(Debug, Deserialize)]
pub struct EirMetadata {
    pub format_version: Option<String>,
    pub created_at: Option<String>,
    pub source: Option<String>,
    pub patient: Option<EirPatient>,
}

#[derive(Debug, Deserialize)]
pub struct EirPatient {
    pub name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct EirEntry {
    pub id: Option<String>,
    pub date: Option<String>,
    #[serde(rename = "time")]
    pub _time: Option<String>,
    pub category: Option<String>,
    #[serde(rename = "type")]
    pub record_type: Option<String>,
    pub provider: Option<EirNamedEntity>,
    #[serde(rename = "status")]
    pub _status: Option<String>,
    pub responsible_person: Option<EirResponsiblePerson>,
    pub content: Option<EirContent>,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct EirNamedEntity {
    pub name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct EirResponsiblePerson {
    pub name: Option<String>,
    pub role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct EirContent {
    pub summary: Option<String>,
    pub details: Option<String>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct HealthSectionDraft {
    pub key: String,
    pub title: String,
    pub private_markdown: String,
    pub public_markdown: String,
    pub visibility: String,
    pub sort_order: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct HealthExampleDraft {
    pub external_entry_id: String,
    pub entry_date: Option<String>,
    pub public_date: Option<String>,
    pub category: String,
    pub record_type: String,
    pub provider_private: Option<String>,
    pub provider_public: Option<String>,
    pub responsible_role: Option<String>,
    pub summary_private: String,
    pub summary_public: String,
    pub details_private: Option<String>,
    pub details_public: Option<String>,
    pub tags: Vec<String>,
    pub visibility: String,
    pub sort_order: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct ImportedHealthBundle {
    pub source: String,
    pub privacy_level: String,
    pub patient_name_private: Option<String>,
    pub patient_label_public: String,
    pub record_count: usize,
    pub latest_entry_date: Option<String>,
    pub private_health_md: String,
    pub public_health_md: String,
    pub sections: Vec<HealthSectionDraft>,
    pub examples: Vec<HealthExampleDraft>,
    pub story_prompts: Vec<String>,
}

pub fn parse_and_transform_eir(contents: &str) -> Result<ImportedHealthBundle, String> {
    let normalized = normalize_eir_yaml(contents);
    let document: EirDocument = serde_yaml::from_str(&normalized).map_err(|error| error.to_string())?;
    let source = document
        .metadata
        .as_ref()
        .and_then(|metadata| metadata.source.clone())
        .unwrap_or_else(|| "Unknown source".to_string());
    let patient_name = document
        .metadata
        .as_ref()
        .and_then(|metadata| metadata.patient.as_ref())
        .and_then(|patient| patient.name.clone())
        .filter(|value| !value.trim().is_empty());

    let patient_label_public = "Pseudonymous patient".to_string();
    let privacy_level = if patient_name.is_some() {
        "pseudonymized".to_string()
    } else {
        "anonymous".to_string()
    };

    let provider_names: Vec<String> = document
        .entries
        .iter()
        .filter_map(|entry| entry.provider.as_ref())
        .filter_map(|provider| provider.name.clone())
        .collect();
    let responsible_names: Vec<String> = document
        .entries
        .iter()
        .filter_map(|entry| entry.responsible_person.as_ref())
        .filter_map(|person| person.name.clone())
        .collect();

    let mut examples = document
        .entries
        .iter()
        .enumerate()
        .map(|(index, entry)| make_example(entry, index as i64, patient_name.as_deref(), &provider_names, &responsible_names))
        .collect::<Vec<_>>();

    examples.sort_by(|left, right| right.entry_date.cmp(&left.entry_date));

    let diagnoses = collect_diagnosis_themes(&document.entries);
    let medications = collect_medications(&document.entries);
    let vaccinations = collect_vaccinations(&document.entries);
    let care_themes = collect_care_themes(&examples);
    let recent_examples = examples.iter().take(8).cloned().collect::<Vec<_>>();

    let private_sections = build_sections(
        &source,
        &privacy_level,
        patient_name.as_deref(),
        &patient_label_public,
        &document,
        &diagnoses,
        &medications,
        &vaccinations,
        &care_themes,
        &recent_examples,
        false,
    );
    let public_sections = build_sections(
        &source,
        &privacy_level,
        patient_name.as_deref(),
        &patient_label_public,
        &document,
        &diagnoses,
        &medications,
        &vaccinations,
        &care_themes,
        &recent_examples,
        true,
    );

    let private_health_md = render_health_md(
        &source,
        &privacy_level,
        patient_name.as_deref(),
        &patient_label_public,
        document.metadata.as_ref().and_then(|metadata| metadata.created_at.clone()),
        document.metadata.as_ref().and_then(|metadata| metadata.format_version.clone()),
        &private_sections,
        false,
    );
    let public_health_md = render_health_md(
        &source,
        &privacy_level,
        patient_name.as_deref(),
        &patient_label_public,
        document.metadata.as_ref().and_then(|metadata| metadata.created_at.clone()),
        document.metadata.as_ref().and_then(|metadata| metadata.format_version.clone()),
        &public_sections,
        true,
    );

    let story_prompts = build_story_prompts(&diagnoses, &care_themes, &recent_examples);
    let sections = private_sections
        .into_iter()
        .zip(public_sections.into_iter())
        .enumerate()
        .map(|(index, (private_section, public_section))| HealthSectionDraft {
            key: private_section.0,
            title: private_section.1,
            private_markdown: private_section.2,
            public_markdown: public_section.2,
            visibility: "private".to_string(),
            sort_order: index as i64,
        })
        .collect::<Vec<_>>();

    let latest_entry_date = document
        .entries
        .iter()
        .filter_map(|entry| entry.date.clone())
        .max();

    Ok(ImportedHealthBundle {
        source,
        privacy_level,
        patient_name_private: patient_name,
        patient_label_public,
        record_count: document.entries.len(),
        latest_entry_date,
        private_health_md,
        public_health_md,
        sections,
        examples,
        story_prompts,
    })
}

fn normalize_eir_yaml(contents: &str) -> String {
    contents
        .lines()
        .map(|line| {
            if let Some(rest) = line.strip_prefix("-     ") {
                format!("- {}", rest.trim_start())
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn make_example(
    entry: &EirEntry,
    sort_order: i64,
    patient_name: Option<&str>,
    provider_names: &[String],
    responsible_names: &[String],
) -> HealthExampleDraft {
    let provider_private = entry.provider.as_ref().and_then(|provider| provider.name.clone());
    let provider_public = provider_private
        .as_ref()
        .map(|name| generalize_provider_name(name));
    let summary_private = entry
        .content
        .as_ref()
        .and_then(|content| content.summary.clone())
        .or_else(|| entry.record_type.clone())
        .unwrap_or_else(|| "Health record entry".to_string());
    let details_private = entry
        .content
        .as_ref()
        .and_then(|content| content.details.clone())
        .or_else(|| entry.content.as_ref().and_then(|content| content.notes.first().cloned()));
    let summary_public = sanitize_text(
        &summary_private,
        patient_name,
        provider_names,
        responsible_names,
        provider_public.as_deref(),
    );
    let details_public = details_private.as_ref().map(|details| {
        sanitize_text(
            details,
            patient_name,
            provider_names,
            responsible_names,
            provider_public.as_deref(),
        )
    });

    HealthExampleDraft {
        external_entry_id: entry.id.clone().unwrap_or_else(|| format!("entry-{}", sort_order)),
        entry_date: entry.date.clone(),
        public_date: entry.date.as_ref().map(|date| public_date(date)),
        category: entry.category.clone().unwrap_or_else(|| "Record".to_string()),
        record_type: entry
            .record_type
            .clone()
            .unwrap_or_else(|| "Health record".to_string()),
        provider_private,
        provider_public,
        responsible_role: entry
            .responsible_person
            .as_ref()
            .and_then(|person| person.role.clone())
            .filter(|value| !value.trim().is_empty()),
        summary_private,
        summary_public,
        details_private,
        details_public,
        tags: entry.tags.clone(),
        visibility: "private".to_string(),
        sort_order,
    }
}

fn build_sections(
    source: &str,
    privacy_level: &str,
    patient_name: Option<&str>,
    patient_label_public: &str,
    document: &EirDocument,
    diagnoses: &[String],
    medications: &[String],
    vaccinations: &[String],
    care_themes: &[String],
    examples: &[HealthExampleDraft],
    public: bool,
) -> Vec<(String, String, String)> {
    let patient_line = if public {
        format!("- **Patient:** {}", patient_label_public)
    } else {
        format!("- **Patient:** {}", patient_name.unwrap_or("Private patient"))
    };
    let overview = format!(
        "## Demographics\n\n{}\n- **Source:** {}\n- **Privacy Level:** {}\n- **Record Count:** {}\n",
        patient_line,
        source,
        privacy_level,
        document.entries.len()
    );

    let history_items = if diagnoses.is_empty() {
        vec!["- No structured diagnosis names were found in this import.".to_string()]
    } else {
        diagnoses
            .iter()
            .map(|diagnosis| format!("- **Clinical theme:** {}", diagnosis))
            .collect::<Vec<_>>()
    };
    let medical_history = format!("## Medical History\n\n{}\n", history_items.join("\n"));

    let medication_items = if medications.is_empty() {
        vec!["- No clear active medications were detected from the imported entries.".to_string()]
    } else {
        medications
            .iter()
            .map(|medication| format!("- **Relevant medication or product:** {}", medication))
            .collect::<Vec<_>>()
    };
    let medication_section = format!("## Current Medications\n\n{}\n", medication_items.join("\n"));

    let timeline_rows = examples
        .iter()
        .take(8)
        .map(|example| {
            let date = if public {
                example.public_date.clone().unwrap_or_else(|| "Undated".to_string())
            } else {
                example.entry_date.clone().unwrap_or_else(|| "Undated".to_string())
            };
            let summary = if public {
                &example.summary_public
            } else {
                &example.summary_private
            };
            let provider = if public {
                example
                    .provider_public
                    .clone()
                    .unwrap_or_else(|| "Healthcare provider".to_string())
            } else {
                example
                    .provider_private
                    .clone()
                    .unwrap_or_else(|| "Healthcare provider".to_string())
            };
            let details = if public {
                example.details_public.clone().unwrap_or_default()
            } else {
                example.details_private.clone().unwrap_or_default()
            };
            format!(
                "### {}: {}\n- **Category:** {}\n- **Provider:** {}\n- **Details:** {}",
                date,
                summary,
                example.category,
                provider,
                if details.is_empty() { "Summary available in source record.".to_string() } else { details }
            )
        })
        .collect::<Vec<_>>();
    let timeline = format!("## Clinical Timeline\n\n{}\n", timeline_rows.join("\n\n"));

    let vaccine_items = if vaccinations.is_empty() {
        vec!["- No vaccination records were extracted into a separate list.".to_string()]
    } else {
        vaccinations
            .iter()
            .map(|item| format!("- {}", item))
            .collect::<Vec<_>>()
    };
    let vaccine_section = format!("## Immunizations\n\n{}\n", vaccine_items.join("\n"));

    let story_theme_items = if care_themes.is_empty() {
        vec!["- This import does not yet expose obvious health themes for story discovery.".to_string()]
    } else {
        care_themes
            .iter()
            .map(|theme| format!("- {}", theme))
            .collect::<Vec<_>>()
    };
    let discovery_section = format!("## Story Discovery Signals\n\n{}\n", story_theme_items.join("\n"));

    vec![
        ("overview".to_string(), "Overview".to_string(), overview),
        ("medical-history".to_string(), "Medical history".to_string(), medical_history),
        ("medications".to_string(), "Current medications".to_string(), medication_section),
        ("clinical-timeline".to_string(), "Clinical timeline".to_string(), timeline),
        ("immunizations".to_string(), "Immunizations".to_string(), vaccine_section),
        ("story-discovery".to_string(), "Story discovery".to_string(), discovery_section),
    ]
}

fn render_health_md(
    source: &str,
    privacy_level: &str,
    patient_name: Option<&str>,
    patient_label_public: &str,
    created_at: Option<String>,
    source_version: Option<String>,
    sections: &[(String, String, String)],
    public: bool,
) -> String {
    let record_id = if public {
        "shared-profile".to_string()
    } else {
        "private-import".to_string()
    };
    let generated = created_at.unwrap_or_else(|| "2026-03-14T00:00:00Z".to_string());
    let privacy = if public { "anonymous" } else { privacy_level };
    let patient_label = if public {
        patient_label_public.to_string()
    } else {
        patient_name.unwrap_or("Private patient").to_string()
    };

    let mut output = String::new();
    output.push_str("---\n");
    output.push_str("health_md_version: \"1.1\"\n");
    output.push_str(&format!("record_id: \"{}\"\n", record_id));
    output.push_str(&format!("generated: \"{}\"\n", generated));
    output.push_str(&format!("privacy_level: \"{}\"\n", privacy));
    output.push_str(&format!("last_updated: \"{}\"\n", generated));
    output.push_str(&format!("data_sources: [\"{}\"]\n", source));
    if let Some(version) = source_version {
        output.push_str(&format!("source_format_version: \"{}\"\n", version));
    }
    output.push_str("---\n\n");
    output.push_str(&format!("<!-- {} -->\n\n", patient_label));
    for (_, _, markdown) in sections {
        output.push_str(markdown);
        output.push('\n');
    }
    output
}

fn build_story_prompts(
    diagnoses: &[String],
    care_themes: &[String],
    examples: &[HealthExampleDraft],
) -> Vec<String> {
    let mut prompts = Vec::new();
    if let Some(first) = diagnoses.first() {
        prompts.push(format!("Write about how {} changed the way you understood your health journey.", first));
    }
    if let Some(first) = care_themes.first() {
        prompts.push(format!("Explain how {} shaped the decisions or uncertainty in your story.", first));
    }
    if let Some(example) = examples.first() {
        prompts.push(format!(
            "Use the {} record from {} as a concrete turning point in your story.",
            example.category,
            example.public_date.clone().unwrap_or_else(|| "your timeline".to_string())
        ));
    }
    prompts.push("Describe what you wish another patient had told you earlier.".to_string());
    prompts
}

fn collect_diagnosis_themes(entries: &[EirEntry]) -> Vec<String> {
    dedupe(
        entries
            .iter()
            .filter(|entry| matches!(entry.category.as_deref(), Some("Diagnoser")))
            .filter_map(|entry| entry.record_type.clone())
            .filter(|record_type| !record_type.eq_ignore_ascii_case("Journalanteckning"))
            .collect::<Vec<_>>(),
    )
}

fn collect_medications(entries: &[EirEntry]) -> Vec<String> {
    dedupe(
        entries
            .iter()
            .filter_map(|entry| entry.record_type.clone())
            .filter(|record_type| {
                let lowered = record_type.to_lowercase();
                lowered.contains("immun") || lowered.contains("vaccin") || lowered.contains("läkemed") || lowered.contains("medicin")
            })
            .collect::<Vec<_>>(),
    )
}

fn collect_vaccinations(entries: &[EirEntry]) -> Vec<String> {
    dedupe(
        entries
            .iter()
            .filter(|entry| matches!(entry.category.as_deref(), Some("Vaccinationer")))
            .filter_map(|entry| entry.record_type.clone())
            .collect::<Vec<_>>(),
    )
}

fn collect_care_themes(examples: &[HealthExampleDraft]) -> Vec<String> {
    dedupe(
        examples
            .iter()
            .filter_map(|example| {
                let provider = example.provider_public.clone()?;
                Some(format!("{} through {}", example.category, provider))
            })
            .collect::<Vec<_>>(),
    )
}

fn dedupe(values: Vec<String>) -> Vec<String> {
    let mut seen = Vec::new();
    for value in values {
        if !seen.iter().any(|existing: &String| existing.eq_ignore_ascii_case(&value)) {
            seen.push(value);
        }
    }
    seen
}

fn public_date(date: &str) -> String {
    if date.len() >= 7 {
        date[..7].to_string()
    } else {
        date.to_string()
    }
}

fn generalize_provider_name(name: &str) -> String {
    let lowered = name.to_lowercase();
    if lowered.contains("1177") {
        "National patient portal".to_string()
    } else if lowered.contains("vårdcentral") {
        "Primary care clinic".to_string()
    } else if lowered.contains("folktandvården") || lowered.contains("tand") {
        "Dental clinic".to_string()
    } else if lowered.contains("klinisk genetik") {
        "Genetics clinic".to_string()
    } else if lowered.contains("mott") {
        "Specialist clinic".to_string()
    } else {
        "Healthcare provider".to_string()
    }
}

fn sanitize_text(
    text: &str,
    patient_name: Option<&str>,
    provider_names: &[String],
    responsible_names: &[String],
    provider_public: Option<&str>,
) -> String {
    let mut output = text.to_string();

    if let Some(name) = patient_name {
        output = replace_case_insensitive(&output, name, "the patient");
        for part in name.split_whitespace().filter(|part| part.len() > 2) {
            output = replace_case_insensitive(&output, part, "the patient");
        }
    }

    for provider_name in provider_names {
        let replacement = provider_public.unwrap_or("a healthcare provider");
        output = replace_case_insensitive(&output, provider_name, replacement);
    }

    for responsible_name in responsible_names {
        output = replace_case_insensitive(&output, responsible_name, "a healthcare worker");
    }

    output = replace_pattern(&output, r"(?i)\b1177 vårdguiden\b", "the national patient portal");
    output = replace_pattern(&output, r"(?i)\b[a-zåäö0-9 .-]*vårdcentral\b", "a primary care clinic");
    output = replace_pattern(&output, r"(?i)\b[a-zåäö0-9 .-]*klinisk genetik[^,]*\b", "a genetics clinic");
    output = replace_pattern(&output, r"(?i)\bfolktandvården[^,]*\b", "a dental clinic");
    output = replace_pattern(&output, r"(?i)\b[a-zåäö0-9 .-]*mott\b", "a specialist clinic");
    output = output.replace("Region Uppsala", "the region");
    output = output.replace("Stockholm", "the region");
    output = output.replace("Göteborg", "the region");
    output = output.replace("  ", " ");
    output = output.replace(" ,", ",");
    output.trim().to_string()
}

fn replace_case_insensitive(input: &str, needle: &str, replacement: &str) -> String {
    if needle.trim().is_empty() {
        return input.to_string();
    }
    let escaped = regex::escape(needle);
    let Ok(regex) = Regex::new(&format!("(?i){}", escaped)) else {
        return input.to_string();
    };
    regex.replace_all(input, replacement).to_string()
}

fn replace_pattern(input: &str, pattern: &str, replacement: &str) -> String {
    let Ok(regex) = Regex::new(pattern) else {
        return input.to_string();
    };
    regex.replace_all(input, replacement).to_string()
}
