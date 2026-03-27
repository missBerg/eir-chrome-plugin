# Eir Stories Product Brief

## Name

`Eir Stories`

## URL

`stories.eir.space`

## Tagline

`Share your health journey. Help someone else navigate theirs.`

## One-Sentence Description

Eir Stories is a privacy-conscious platform where people can publish health journeys, optionally enrich them with their own records, and find others with similar experiences.

## Problem

People can increasingly access their own health data, but access alone does not solve three harder problems:

- the records are hard to understand
- the journey is fragmented across institutions and time
- people rarely know how their experience compares with anyone else's

At the same time, most health communities rely on memory, informal posts, and incomplete context.

That creates a gap:
- patients have records but no humane way to share them
- communities have empathy but weak structure

There is a second gap too:
- some people have an important health story to tell even before they have clean structured records
- they still need a safe, useful way to share that story

## Vision

Create the public layer of patient experience that sits between private medical records and general health discussion.

The long-term vision is that people can:
- understand their own care history
- publish a privacy-safe version of it
- discover others with similar health journeys
- learn from real experience without giving up control of their identity

## Product Thesis

If Eir helps people access and structure their own records, then Eir Stories can help them turn those records into meaningful, shareable health journeys.

But the product should not require records to be useful.

The right model is:
- story first
- health context second
- record-backed evidence optional

The social value is not in exposing raw medical data.

The value is in transforming private records into:
- structured stories
- searchable timelines
- comparable experiences
- practical patient-to-patient insight

## Design Principles

### Calm, not noisy

This should feel closer to reading a thoughtful case history than scrolling a chaotic feed.

### Patient-led

The story belongs to the patient. Publishing is deliberate, reversible, and reviewed.

### Structured, not vague

Every story should have a recognizable shape:
- condition or concern
- key events
- interventions
- outcomes
- reflections

### Privacy-forward

The interface should constantly help people avoid oversharing.

### Useful before viral

The platform should optimize for trust and relevance, not engagement tricks.

## Core Objects

### Story

A public or semi-public health journey created by a user from narrative writing, optional structured health fields, and optional record-backed evidence.

### Profile

A person-facing representation of the story owner with optional pseudonymity and limited public identity fields.

### Timeline Event

A normalized event in the user journey:
- symptom onset
- referral
- diagnosis
- medication start
- dosage change
- procedure
- hospital visit
- outcome milestone

Timeline events can be:
- narrative-only
- user-entered structured events
- record-backed events

### Topic Layer

Tags and facets that make stories discoverable:
- diagnosis
- symptoms
- body system
- medication
- procedure
- age range
- geography
- care context

## MVP Scope

### Included

- landing page
- onboarding flow for story creation
- narrative-first story composer
- PII review step
- public story page
- browse/search results
- topic pages
- simple account system

### Not Included Yet

- full messaging system
- clinical validation layer
- recommendation engine
- researcher tooling
- advanced community moderation tools

## PII and Safety Model

The platform should assume users are bad at noticing what is identifying.

So the product should include:
- automatic redaction suggestions
- warnings for names, addresses, phone numbers, email addresses, exact birth dates, and document IDs
- prompts to generalize rare dates and locations
- manual review before publish
- granular visibility settings

It should also distinguish clearly between:
- public story text
- optional structured health fields
- optional evidence attached to timeline events
- private source files

## Why This Fits Eir

Eir already sits upstream of this idea.

First Eir helps people get their data.
Then Eir helps them understand it.
Then Eir Stories gives them a way to tell the story of that journey, with as much or as little record-backed detail as they choose.

## Launch Message

`People should not have to face a health journey alone, and they should not have to overshare to be understood.`
