# EU EHR Integration Roadmap

Based on: [EU Patient-Facing EHR Integration Map](/Users/birger/Community/eir-chrome-plugin/docs/eu-patient-ehr-integration-map.md)

Research baseline date: March 13, 2026

Purpose: convert the country map into an execution roadmap for Eir. The focus is not “which countries have digital health access,” but “which countries are worth building next if Eir follows the same patient-facing electronic access flow that real patients use.”

## Decision Framework

Each country is placed by:

- patient-flow coherence: whether one official patient flow covers most record access
- likely extraction surface: browser portal, mixed web/app, or fragmented ecosystem
- identity complexity: whether login is straightforward to observe and replay conceptually
- backend complexity: whether one patient portal likely fronts many data sources
- strategic fit: how well the country matches Eir’s current Sweden and Finland direction

## Priority Tiers

### Build Now

These countries best fit the current Eir model: one strong patient-facing entry point, browser-based capture is likely sufficient to get started, and the technical path is close to Sweden/Finland.

- Finland
- Denmark
- Estonia
- Poland
- Austria
- Hungary
- Slovenia
- Luxembourg

### Research Next

These countries look promising, but should get a deeper technical pass before implementation. The main risks are backend variation, app spillover, or less certainty about how broad the patient view really is.

- Belgium
- France
- Portugal
- Latvia
- Lithuania
- Malta
- Bulgaria
- Croatia
- Cyprus
- Slovakia
- Greece

### Watchlist

These countries are structurally harder or not mature enough for near-term build work.

- Germany
- Italy
- Spain
- Netherlands
- Ireland
- Czech Republic
- Romania

### Already Covered

- Sweden

## Recommended Rollout Order

If the goal is controlled expansion, this is the order that makes the most sense:

1. Finland
2. Denmark
3. Estonia
4. Poland
5. Austria
6. Hungary
7. Slovenia
8. Luxembourg
9. Belgium
10. France

Reasoning:
- Finland is the closest strategic extension from Sweden and already justified the Kanta recorder work.
- Denmark and Estonia are strong national-digital countries with coherent citizen-facing flows.
- Poland and Austria offer relatively large upside with national entry points.
- Hungary and Slovenia look operationally simpler than the large fragmented countries.
- Luxembourg is small but useful as a clean national-portal case.
- Belgium and France are likely valuable but should follow once the single-portal capture stack is proven.

## Country Backlog

## Tier 1: Build Now

| Country | Why now | Likely build shape | Main risk | Browser recorder enough? | Effort |
|---|---|---|---|---|---|
| Finland | Strong national patient portal, central Kanta repository, closest match to Swedish model | One portal adapter with network-first capture, then schema mapping | Strong auth flow and portal changes | Yes, for research and likely first integration pass | Medium |
| Denmark | One national health portal with broad patient use | One portal adapter plus endpoint-family clustering | Backend diversity behind sundhed.dk | Yes, likely | Medium |
| Estonia | Strong national digital identity and one health portal | One portal adapter | Need live confirmation of response structure breadth | Yes | Medium |
| Poland | Strong national patient account and app ecosystem | One main portal adapter, optional app follow-up later | Some data may be richer in app flows | Yes, to start | Medium |
| Austria | National ELGA citizen flow | One portal adapter | Need live validation of record breadth and document download patterns | Yes | Medium |
| Hungary | National EESZT citizen portal | One portal adapter | Auth and state transitions may be less straightforward than Finland/Sweden | Yes | Medium |
| Slovenia | Coherent national zVEM flow | One portal adapter | Need live validation of data categories and payload consistency | Yes | Medium |
| Luxembourg | Small-country national portal, manageable scope | One portal adapter | Smaller market, so less payoff despite lower complexity | Yes | Low-Medium |

## Tier 2: Research Next

| Country | Why later | What must be researched first | Likely outcome | Effort if greenlit |
|---|---|---|---|---|
| Belgium | Good portal, but likely many backend services | Which patient features share one endpoint family vs several services | Single adapter with heavier endpoint discovery | Medium-High |
| France | Strong national product, but scale and feature set are larger | Whether records are exposed uniformly through one web flow | Single adapter with more mapping work | Medium-High |
| Portugal | Clear citizen entry point, likely fronts multiple SNS systems | How much data comes through one session vs service-by-service calls | Single adapter with clustered endpoints | Medium |
| Latvia | National portal looks coherent, but needs live technical confirmation | Record breadth, payload format, export/document behavior | Probably single adapter | Medium |
| Lithuania | Similar to Latvia, but public docs are less definitive on breadth | How longitudinal the actual patient record flow is | Probably single adapter | Medium |
| Malta | Small and centralized, but needs confirmation of EHR depth | Whether myHealth exposes enough record detail to justify integration | Small single adapter if viable | Low-Medium |
| Bulgaria | Strong national direction, but live patient-flow validation needed | Stability of the portal and response structure | Single adapter if stable | Medium |
| Croatia | National portal looks viable, but needs technical pass | Which services are actually exposed through one patient session | Single adapter if unified enough | Medium |
| Cyprus | Useful but smaller market and less certainty on data breadth | Whether core records are broad enough to support Eir use cases | Single adapter if scope is sufficient | Low-Medium |
| Slovakia | National portal appears promising, but current public info is thinner | Depth of patient-visible record data and session structure | Single adapter if confirmed | Medium |
| Greece | Official web and app flows coexist | Whether meaningful record access is browser-first or app-dominant | Mixed web/app integration | Medium-High |

## Tier 3: Watchlist

| Country | Why not now | Likely future strategy |
|---|---|---|
| Germany | Insurer-based ePA model means no single patient portal target; app-heavy reality | Start with one insurer only if Germany becomes a strategic priority |
| Italy | National framework, but region-by-region portals and apps | Pick one region first instead of “Italy” as a single build |
| Spain | Regional patient portals with national interoperability behind the scenes | Treat each autonomous community as its own adapter family |
| Netherlands | MedMij and PGO ecosystem suggests standards-first is better than portal scraping | Prefer standards/partner path over browser automation |
| Ireland | HSE patient access is still evolving and not yet a mature broad EHR flow | Reassess when national shared care record has broader citizen access |
| Czech Republic | Current patient-facing flow appears narrower than a mature longitudinal record portal | Monitor for wider national patient-record scope |
| Romania | Public patient access exists, but current maturity looks comparatively limited | Monitor until the citizen-facing record surface is broader and more stable |

## Implementation Model By Tier

### Tier 1 countries

For these countries, Eir should follow the same build pattern:

1. Run the browser capture recorder on the official patient portal.
2. Identify the real data endpoints through fetch/XHR traffic.
3. Build a country adapter that maps observed payloads into EIR.
4. Add fixture-based replay tests from captured sessions.
5. Only after the browser path is stable, evaluate whether an official API path exists and is worth pursuing.

### Tier 2 countries

For these countries, do a two-phase process:

1. Technical reconnaissance:
   - auth flow
   - endpoint count
   - whether the main records are browser-visible or app-only
   - whether response payloads are stable enough to map
2. Build only if the portal looks coherent enough for one adapter.

### Tier 3 countries

Do not treat these as normal country integrations.

Instead:
- define one sub-target at a time
- validate user demand first
- assume higher maintenance burden

## Product Strategy Implications

### 1. Eir should optimize for national-portal countries first

That is where one integration can unlock a full country rather than a single region, insurer, or app brand.

### 2. Network-first reverse engineering should be the default

The future integration will almost always be built from the requests and responses that deliver the patient data, not from the DOM that renders it.

### 3. Browser support is necessary but not always sufficient

For some countries, the official patient experience is partly or mostly app-based. Eir should expect to add a second capture strategy later for mobile-heavy systems.

### 4. “Country support” should be defined carefully

For fragmented markets, saying “Germany support” or “Spain support” is misleading unless it means support for specific insurer or region flows.

## Suggested Execution Plan

### Quarter 1

- Finland: complete reverse-engineering capture and first working adapter
- Denmark: capture and endpoint mapping
- Estonia: capture validation and adapter feasibility check

### Quarter 2

- Poland: first capture and adapter
- Austria: first capture and adapter
- Hungary or Slovenia: choose based on capture quality and real-user availability

### Quarter 3

- Luxembourg: fast clean integration
- Belgium: deeper technical reconnaissance
- France: deeper technical reconnaissance

### Quarter 4

- Build one of Belgium or France
- Re-evaluate Portugal, Latvia, Lithuania, and Malta based on demand and technical clarity

## What To Research Before Each New Country

- official patient login route
- whether the main record view is web, app, or mixed
- whether records come as HTML-rendered data or JSON/document downloads
- whether one session exposes all key record types
- whether backend endpoints differ by region, insurer, or provider
- whether the portal uses embedded PDFs, iframes, or API payloads
- whether pagination and historical depth are accessible through one patient flow

## Recommended Next Action

The immediate next step should still be Finland, but after that Eir should choose one “clean national portal” country and one “messier distributed portal” country to test whether the current capture architecture generalizes well.

Best pairing:

- clean case: Estonia or Austria
- messier case: Denmark or Belgium

That gives you a better read on whether Eir’s core integration system is truly reusable across Europe.
