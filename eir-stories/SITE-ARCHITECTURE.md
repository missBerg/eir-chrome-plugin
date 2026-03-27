# Eir Stories Site Architecture

## Public Site Map

### `/`

Landing page.

Goals:
- explain what Eir Stories is
- explain privacy posture
- show example health journeys
- show that stories can be narrative-only or data-enriched
- drive signups or early access

### `/stories`

Browse all public stories.

Facets:
- condition
- symptoms
- medications
- procedures
- age range
- journey stage
- country
- evidence level

### `/stories/[slug]`

Public story page.

Sections:
- short summary
- condition context
- timeline
- treatments and changes
- lessons learned
- optional health information
- optional discussion or follow

### `/topics/[slug]`

Topic hubs such as:
- endometriosis
- long covid
- ADHD
- migraine
- rheumatoid arthritis

### `/create`

Story creation flow.

Steps:
1. start with your story
2. optionally add health information
3. optionally import or connect data
4. redact and review
5. choose visibility
6. publish

### `/privacy`

Clear explanation of:
- what source data stays private
- what can become public
- how redaction works
- what users should never share

### `/about`

Mission, trust model, and why Eir is building this.

## Core User Flows

## Flow 1: Reader

1. Arrive on landing page
2. Browse a condition or symptom
3. Open a story
4. Understand someone else's journey
5. Follow, save, or join waitlist

## Flow 2: Sharer

1. Arrive on landing page
2. Understand the privacy model
3. Start a story draft
4. Write the narrative first
5. Optionally add health data
6. Review redactions
7. Publish a public journey

## Flow 3: Similarity Discovery

1. User publishes a story
2. Platform suggests related stories
3. User sees others with overlapping paths
4. User feels less isolated and gains practical context

## Story Page Structure

Each story page should include:

### Story Header

- title
- pseudonym or chosen name
- short health context
- visibility level

### Journey Summary

- what happened
- how long it took
- current status

### Timeline

- chronological events
- event type badges
- optional record-backed evidence

### Health Information

- optional diagnoses
- optional medications
- optional procedures
- optional symptom tags
- optional evidence notes

### Treatment and Outcome

- medication changes
- procedures
- response patterns
- side effects

### Patient Notes

- what helped
- what was difficult
- what they wish they knew earlier

### Related Stories

- similar condition
- similar treatment path
- similar symptom cluster

## Design Direction

The visual direction should feel:
- editorial
- humane
- highly legible
- calm and serious

Avoid:
- gamified community UI
- noisy social metrics
- bright health-tech clichés

## Moderation Model

The platform will need:
- report flow
- identity and impersonation policy
- harmful medical advice policy
- self-harm escalation guidance
- anti-doxxing enforcement

The tone should always be:
- supportive
- non-diagnostic
- non-sensational

## MVP Tech Recommendation

For a standalone repo:
- `Next.js` or `Astro` for the marketing/public site
- static-first pages for story reading where possible
- server-side APIs only for auth, moderation, and private draft handling

## Suggested Repo Layout

```text
eir-stories/
  app/
  components/
  content/
  public/
  styles/
  docs/
    product-brief.md
    moderation.md
    privacy-model.md
```

