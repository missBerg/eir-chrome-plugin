# Eir Stories MVP Spec

## Goal

Build the smallest version of Eir Stories that proves the core loop:

1. a person creates a story
2. they review privacy risks
3. they publish a readable public journey
4. another person finds it and learns from it

## Product Scope

The MVP is not a full social network.

It is:
- a publishing tool
- a browsing experience
- a privacy review system
- a light discovery layer

## MVP Includes

- landing page
- account creation
- story composer
- health context editor
- optional record/evidence attachment flow
- PII review step
- publish settings
- public story page
- browse/search page
- topic pages

## MVP Excludes

- direct messaging
- group spaces
- open comments on day one
- algorithmic recommendations
- clinician verification
- researcher data export

## Product Loop

### Loop 1: Publish

1. User starts a story
2. User writes the narrative
3. User optionally adds health details
4. User optionally adds evidence
5. User reviews privacy warnings
6. User publishes

### Loop 2: Discover

1. Reader visits topic or browse page
2. Reader opens a story
3. Reader understands the journey quickly
4. Reader explores related stories

## Success Criteria

The MVP is working if:
- people can publish narrative-only stories
- people can publish data-enriched stories
- stories are legible and searchable
- privacy review catches obvious risks
- readers can find relevant stories by condition or symptom

## Core Screens

- Home
- Browse stories
- Story detail
- Create story
- Privacy review
- Publish settings
- Topic page
- About / trust / privacy

## Design Constraints

- no feed-like UI
- no vanity metrics as the main visual signal
- no clinical-dashboard aesthetic
- calm typography and strong reading experience

## Required Decisions

### Identity

Users should be able to publish with:
- pseudonym
- first name only
- anonymous profile label

### Visibility

Each story should support:
- public
- unlisted
- draft

### Evidence Display

Evidence should be visible, but never dominate the narrative.

## Build Order

1. landing page
2. story composer
3. privacy review
4. public story page
5. browse and topic pages
6. account and draft management

