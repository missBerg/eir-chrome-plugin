# Eir Stories PII Review

## Purpose

The privacy review is the safety boundary between private drafting and public publishing.

It should assume users miss identifying details.

## What To Detect

### Direct identifiers

- full names
- phone numbers
- email addresses
- home addresses
- patient IDs
- document numbers
- exact birth dates

### High-risk quasi-identifiers

- exact hospital names in rare contexts
- exact dates paired with rare events
- small towns or workplaces
- rare clinician names
- family member names

## Review Output

The review step should show:
- flagged text snippets
- why they may identify the person
- suggested replacement
- severity level

Example replacements:
- full date -> month/year
- exact town -> region
- hospital ward -> large hospital system
- personal name -> role label

## User Controls

The user must be able to:
- accept a redaction suggestion
- ignore it
- edit it manually
- preview the public version

## Publish Gate

The platform should block publishing if obvious direct identifiers remain unless the user explicitly confirms the risk.

That confirmation should be difficult to do by accident.

## Copy Principles

The tone should be:
- calm
- factual
- non-alarmist

Bad:
- `Danger! You are exposing your private data`

Good:
- `This line may identify you more directly than intended. Consider generalizing the date or location.`

## Source Separation

The system should distinguish between:
- private source material
- extracted structured data
- public story content

Users should always know which layer they are editing.

