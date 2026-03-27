# EgenRemiss — Project Assessment

## Goal
Email all relevant Swedish healthcare providers with information about EgenRemiss (patients' right to self-refer directly to specialist care without a GP referral).

---

## What You Have

### Clinic Database (17,802 clinics scraped from 1177.se)
| Field              | Coverage      |
|--------------------|---------------|
| Name               | 17,802 (100%) |
| Address            | 17,515 (98%)  |
| Phone              | 17,638 (99%)  |
| 1177.se URL        | 17,802 (100%) |
| GPS coordinates    | 17,802 (100%) |
| HSA ID             | 17,802 (100%) |
| **Email**          | **0 (0%)**    |

### Clinic Types in Dataset
| Type                              | Count  | Relevant for EgenRemiss? |
|-----------------------------------|--------|--------------------------|
| Mottagningar (specialist clinics) | ~5,370 | Yes — primary target     |
| Vårdcentraler (primary care)      | ~1,820 | Yes — inform about flow   |
| Tandvård (dental)                 | ~1,670 | No                       |
| Sjukhus (hospitals)               | ~1,120 | Partially                |
| Other (lab, vaccination, etc.)    | ~7,800 | No                       |

### Tools
- `scrape-clinics.js` — scrapes all clinics from 1177.se API
- EirViewer desktop app — displays and filters all clinics with map view
- Clinic type classification logic in `ClinicStore.swift`

---

## What's Missing

### 1. Email Addresses (Critical Blocker)
The 1177.se data has no email addresses. You need to acquire them. Options:

**Option A: Scrape from 1177.se clinic pages**
Each clinic has a detail page (the `url` field). Some pages list an email address. Would require visiting all 17,802 URLs and extracting contact info.

**Option B: HSA Katalogen (Swedish healthcare directory)**
The HSA directory (hsaid.se / HSA Katalog) contains structured contact data including email for healthcare units. You already have HSA IDs for every clinic — these can be used as lookup keys.

**Option C: Regional registries**
Each Swedish region maintains its own provider registries. The 21 regions could be contacted individually for bulk email lists.

**Option D: Manual research per target segment**
Filter to the ~2,000–3,000 most relevant clinics (vårdcentraler + specialist mottagningar) and research emails in batches.

### 2. Target Segmentation
Not all 17,802 clinics are relevant. EgenRemiss primarily concerns:
- **Specialist mottagningar** that receive referrals (orthopedics, dermatology, psychiatry, gynecology, eye care, etc.)
- **Vårdcentraler** that currently write referrals and should know about the patient-direct path
- Exclude: dental, vaccination stations, labs, radiology, mammography wagons, etc.

### 3. Email Content
- Information about what EgenRemiss is
- How it benefits both patients and providers
- What the provider should do / how to support it
- Possibly a link to more resources

### 4. Email Sending Infrastructure
- Bulk email service (e.g., Mailgun, SendGrid, Postmark, or Brevo)
- Unsubscribe handling
- Tracking (opens, clicks)
- Compliance with GDPR for organizational emails (not personal data, but still needs a legal basis)

---

## Done So Far

### Phase 1: Filter & Segment — DONE
- [x] `filter-clinics.js` filters 17,802 clinics into target segments
- [x] Results: **8,665 target clinics** broken down as:
  - `targets-specialist.json` — 4,878 specialist mottagningar
  - `targets-vardcentral.json` — 2,663 vårdcentraler
  - `targets-hospital.json` — 1,124 hospitals
  - `targets-all.json` / `targets-all.csv` — combined
- [x] 2,703 excluded (dental, labs, vaccination, etc.)
- [x] 6,435 need manual review (uncategorized + generic mottagningar)

### Phase 1.5: Email Scraping Test — DONE
- [x] Tested scraping emails from 1177.se clinic detail pages
- [x] Result: **~2.9% of pages have an email** (extrapolates to ~250 of 8,665)
- [x] 1177.se pages rarely list email — this is NOT a viable primary strategy
- [x] `scrape-emails.js` is ready if you want to harvest what's available

---

## Recommended Next Steps

### Phase 2: Email Acquisition (the critical blocker)
1177.se only yields ~3% email coverage. Better options:

- [ ] **HSA Katalogen lookup** — Use the HSA IDs you already have to query the national healthcare directory for structured email data. This is the most promising path.
- [ ] **Scrape clinic websites** — Many 1177 pages link to the clinic's own website, which more often has a contact email. Extend `scrape-emails.js` to follow these links.
- [ ] **Regional approach** — Contact each of the 21 regions' IT/admin departments for bulk provider email lists.
- [ ] **Run full 1177 scrape anyway** — Even at 3%, that's ~250 emails as a starting batch. Run `node scrape-emails.js` (takes ~30 min for all 8,665).

### Phase 3: Content & Templates
- [ ] Draft the EgenRemiss information email (Swedish)
- [ ] Create variations for specialist vs. vårdcentral recipients
- [ ] Include clear call-to-action and resources link

### Phase 4: Send & Track
- [ ] Set up email sending service (SendGrid, Postmark, or Brevo)
- [ ] Unsubscribe handling + GDPR compliance for organizational emails
- [ ] Test with small batch, then scale

---

## Files in This Folder

| File | Description |
|------|-------------|
| `PROJECT-ASSESSMENT.md` | This file |
| `filter-clinics.js` | Filters 17,802 clinics into target segments |
| `scrape-emails.js` | Scrapes emails from 1177.se pages (with checkpoint/resume) |
| `targets-all.json` | 8,665 target clinics (combined) |
| `targets-all.csv` | Same as above, CSV for spreadsheet review |
| `targets-specialist.json` | 4,878 specialist clinics |
| `targets-vardcentral.json` | 2,663 primary care centers |
| `targets-hospital.json` | 1,124 hospitals |
