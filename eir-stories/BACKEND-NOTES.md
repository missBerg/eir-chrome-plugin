# Eir Stories Backend Notes

## Direction

The frontend scaffold is static for now, but the real product should move toward the same pattern as `skills.eir.space`:

- a lightweight web frontend
- a real hosted backend
- persistent story data
- a database that supports drafts, publishing, and search

## Suggested Shape

### Hosting

- app server on `Fly.io`
- Postgres on `Fly.io`

### Core backend responsibilities

- accounts
- draft storage
- story publishing
- visibility controls
- basic search and topic indexing
- privacy review results

### Tables

- `users`
- `stories`
- `story_events`
- `story_topics`
- `story_evidence`
- `draft_redaction_flags`

## Important Product Constraint

The backend should store the story as layered content:

1. narrative
2. structured health context
3. optional evidence

That keeps the product aligned with the concept:
- stories work without health data
- health information can accompany a story
- evidence is additive, not required

## Good First API Shape

- `GET /stories`
- `GET /stories/:slug`
- `POST /drafts`
- `PATCH /drafts/:id`
- `POST /drafts/:id/review`
- `POST /drafts/:id/publish`

## Why Not Static Long Term

The current static scaffold is good for product design and GitHub Pages.

The real product will need a backend because:
- people need drafts
- privacy review needs state
- stories need moderation and visibility settings
- search and topic pages should be queryable

