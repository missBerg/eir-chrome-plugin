# Eir Stories Composer

## Objective

The composer should make it easy to tell a useful health journey without making data import feel mandatory.

The first question should not be:
`Upload your records`

The first question should be:
`What happened?`

## Composer Steps

### Step 1: Start With The Story

Fields:
- title
- one-sentence summary
- what happened
- current status

Prompts:
- `What do you want someone else to understand about your journey?`
- `What was the turning point?`
- `What has been hardest to explain to other people?`

### Step 2: Add Context

Optional fields:
- condition tags
- symptom tags
- medication tags
- procedure tags
- country
- age range
- care context

This step should make the story easier to discover.

### Step 3: Build The Timeline

Users can add events manually:
- symptom started
- referral
- diagnosis
- medication started
- medication changed
- procedure
- setback
- improvement

Each event can be:
- narrative only
- structured
- evidence-backed

### Step 4: Add Health Information

Optional supporting information:
- diagnoses
- medications
- procedures
- outcomes
- test/result summaries

Important:
The UI should encourage summary fields, not giant record dumps.

### Step 5: Add Evidence

Optional.

The user can:
- attach selected events from imported records
- attach excerpts
- attach date-backed milestones

The evidence step should feel selective and deliberate.

### Step 6: Privacy Review

Before publishing, the story must go through a redaction pass.

### Step 7: Publish

Choose:
- public
- unlisted
- draft

## Composer UX Principles

- narrative first
- no medical form fatigue
- progress should feel calm and linear
- optional data steps should stay optional
- every step should help the story become clearer

## Save State

Drafts should save:
- title
- narrative blocks
- tags
- timeline events
- privacy review status
- publish state

