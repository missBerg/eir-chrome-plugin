# Eir Stories Story Model

## Principle

Stories should work without health data.

Health data should strengthen a story when the user wants it to, not be a requirement for participation.

So the model has three layers:

1. Narrative layer
2. Structured health layer
3. Evidence layer

## Layer 1: Narrative

This is the minimum viable story.

Fields:
- title
- short summary
- body
- current status
- lessons learned
- what helped
- what was difficult

This layer should be enough to publish a story on its own.

## Layer 2: Structured Health Layer

This makes stories searchable and comparable.

Fields:
- condition tags
- symptom tags
- medication tags
- procedure tags
- body system tags
- age range
- country
- care context
- timeline markers

This layer can be filled manually by the user even without imported records.

## Layer 3: Evidence Layer

This is optional.

It adds stronger grounding to the story:
- imported events from records
- selected excerpts
- normalized timeline events
- dates generalized where needed
- confidence labels

This layer should always be review-first and privacy-checked.

## Evidence Levels

Each story should expose an evidence level:

- `Narrative only`
- `Narrative + structured context`
- `Narrative + record-backed evidence`

That helps readers understand what kind of story they are reading without creating a false hierarchy of worth.

## Story Object

```json
{
  "title": "Living with migraine across work and university",
  "slug": "living-with-migraine-across-work-and-university",
  "author": {
    "display_name": "Mika",
    "is_pseudonymous": true
  },
  "summary": "A seven-year journey through delayed diagnosis, medication changes, and finally finding a pattern that made daily life manageable.",
  "body": "Long-form narrative content.",
  "status": "ongoing",
  "evidence_level": "narrative_plus_structured_context",
  "topics": {
    "conditions": ["migraine"],
    "symptoms": ["headache", "light sensitivity", "nausea"],
    "medications": ["sumatriptan"],
    "procedures": [],
    "country": "Sweden"
  },
  "timeline": [
    {
      "label": "Symptoms began",
      "kind": "narrative",
      "date_precision": "year_month",
      "date": "2019-09"
    },
    {
      "label": "Started sumatriptan",
      "kind": "structured",
      "date_precision": "year_month",
      "date": "2021-02"
    }
  ],
  "lessons_learned": [
    "Tracking sleep and stress patterns mattered more than I expected."
  ]
}
```

## Publishing Rules

### Narrative-only stories

Allowed and encouraged.

### Structured-only stories

Not ideal. The platform should always encourage some human narrative.

### Evidence-heavy stories

Allowed, but the interface should still keep the story legible for non-clinical readers.

## UX Implications

The creation flow should ask:

1. What happened?
2. What do you want someone else to understand?
3. Do you want to add health details?
4. Do you want to connect records or keep this story narrative-only?

That keeps the product anchored in story rather than data extraction.

