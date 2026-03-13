# EU Patient-Facing EHR Integration Map

Research date: March 13, 2026

Purpose: map how patients in each EU country currently access their own healthcare data electronically, and what that implies for an Eir-style integration that follows the same patient-facing flow.

Scope:
- Focus is the same flow used by patients: web portals, citizen portals, official apps, or insurer apps.
- This is not a map of provider-to-provider exchange.
- When a row says `Inference`, that part is a technical interpretation of the official patient portal setup rather than a directly documented public API contract.

Integration-shape legend:
- `Single national portal`: one main national web/app entry point for patients.
- `National portal over distributed systems`: one patient entry point, but records likely come from regional, hospital, insurer, or provider systems.
- `Regional or insurer fragmented`: patients use multiple regional portals, insurer apps, or personal health environments rather than one national patient portal.
- `Partial / evolving`: there is official patient access, but not yet a broad longitudinal EHR flow.

Recommended-adapter legend:
- `Single adapter`: one main browser or app capture target.
- `Single adapter + endpoint discovery`: one main target, but expect several backend endpoint families behind it.
- `Multi-adapter`: separate regional, insurer, or app adapters likely needed.
- `Watch`: patient flow exists but current scope is too partial or unstable for immediate integration work.

## Summary Matrix

| Country | Patient-facing service | Typical patient login | Observed patient flow | Integration shape | Recommended adapter | Notes for Eir | Sources |
|---|---|---|---|---|---|---|---|
| Austria | ELGA via `gesundheit.gv.at` | National eID / ID Austria | Patients access documents and records through ELGA’s citizen services. | Single national portal | Single adapter | Good candidate for browser-first reverse engineering. | [gesundheit.gv.at](https://www.gesundheit.gv.at/service/elektronische-gesundheitsakte/), [ELGA](https://www.elga.gv.at/) |
| Belgium | Myhealth web portal and mobile app | eID / itsme / Belgian citizen auth stack | Patients use Myhealth to view prescriptions, vaccinations, summaries, results, and documents in the shared health record. | National portal over distributed systems | Single adapter + endpoint discovery | Good target, but expect multiple backend services behind the portal. | [INAMI Myhealth](https://www.inami.fgov.be/fr/themes/myhealth-view-and-manage-your-health-data-online-and-via-our-mobile-app), [myhealth.belgium.be](https://www.myhealth.belgium.be/) |
| Bulgaria | National Health Information System, `my.his.bg`, eZdrave | National digital identity methods | Patients access health records through the national HIS portal and app. | Single national portal | Single adapter | Strong candidate if the patient web flow is stable. | [HIS Bulgaria](https://his.bg/en), [my.his.bg](https://my.his.bg/) |
| Croatia | Portal Zdravlja through e-Građani / CEZIH services | Croatian e-Citizens identity | Patients use Portal Zdravlja to view data from national eHealth services. | Single national portal | Single adapter | Good candidate for portal automation. | [Portal Zdravlja](https://portalzdravlja.hr/), [e-Građani](https://gov.hr/en/e-citizens/1474) |
| Cyprus | GESY Beneficiary Portal | GESY beneficiary account / national beneficiary flow | Patients use the GESY portal to view encounters, referrals, prescriptions, and test-related data. | Single national portal | Single adapter | Useful target, but verify whether key data is richer on web or app. | [GESY Beneficiary Portal](https://www.beneficiaryportal.gesy.org.cy/), [GESY](https://www.gesy.org.cy/) |
| Czech Republic | Citizen Portal / National Patient Summary / medication services | Citizen Identity | Patients can access national patient-summary and medication-related data via the Citizen Portal. | Partial / evolving | Watch or narrow-scope single adapter | Current patient-facing scope appears narrower than a full longitudinal EHR. | [Citizen Portal](https://obcan.portal.gov.cz/), [Czech eGovernment](https://info.identitaobcana.cz/en/) |
| Denmark | sundhed.dk / Sundhedsjournalen | MitID | Patients access records and health data through the national health portal. | National portal over distributed systems | Single adapter + endpoint discovery | High-priority target. One citizen entry point, but backend feeds are likely diverse. | [sundhed.dk](https://www.sundhed.dk/), [Sundhedsjournalen](https://www.sundhed.dk/sundhedsjournalen/) |
| Estonia | Terviseportaal (Health Portal) | National eID | Patients use the official Health Portal to view personal health information. | Single national portal | Single adapter | Strong candidate; Estonia usually has coherent national digital flows. | [Terviseportaal](https://terviseportaal.ee/en), [Health Portal info](https://www.tervisekassa.ee/en/people/e-services/health-portal) |
| Finland | MyKanta | Online banking codes, mobile certificate, eID card via Suomi.fi | Patients log in to MyKanta to see records, prescriptions, and stored health data. | Single national portal over central repository | Single adapter now; official integration later | Highest-priority target for Nordic expansion. | [MyKanta](https://www.kanta.fi/en/mykanta), [Kanta Services](https://www.kanta.fi/en/what-are-kanta-services) |
| France | Mon espace sante | FranceConnect and health-insurance onboarding flows | Patients access documents, messages, and shared health-space data through the national service. | Single national portal | Single adapter | Good candidate; likely one of the better large-country targets. | [Mon espace sante](https://www.monespacesante.fr/), [ameli](https://www.ameli.fr/assure/sante/mon-espace-sante) |
| Germany | Electronic patient record (ePA) through insurer apps and portals | Health ID / insurer onboarding / eGK-related flows | Patients generally access ePA through their statutory health insurer’s app or portal rather than one national citizen portal. | Regional or insurer fragmented | Multi-adapter | Harder target. Browser-only automation may miss major app-only flows. | [BMG ePA](https://www.bundesgesundheitsministerium.de/epa-von-den-krankenkassen.html), [gematik ePA](https://www.gematik.de/anwendungen/epa) |
| Greece | Electronic National Health Record / myHealth flows | National health or gov identity flows | Patients access EHR-related services through official government health services and the myHealth app. | Single national portal / app ecosystem | Single adapter + app follow-up | Viable target, but confirm how much data is only exposed in the mobile app. | [gov.gr health records](https://www.gov.gr/en/service/ugeia-kai-pronoia/iatrikoi-phakeloi-kai-bebaioseis/elektronikos-phakelos-ugeias), [MyHealth app](https://www.gov.gr/en/upourgeia/upourgeio-ugeias) |
| Hungary | EESZT Lakossagi Portal | Ügyfélkapu+ / national citizen auth | Patients access the national EESZT citizen portal for health records and e-prescription-related data. | Single national portal | Single adapter | Strong target if web flow is accessible and stable. | [EESZT Lakossági Portál](https://www.eeszt.gov.hu/hu/lakossagi-portal), [EESZT](https://www.eeszt.gov.hu/) |
| Ireland | HSE Health App | Verified MyGovID | Patients currently use the HSE Health App for vaccines, medicines, referrals, waiting-list information, and some program data. The broader shared record is still rolling out. | Partial / evolving | Watch | Important market, but patient-facing record access is not yet a mature single EHR flow. | [HSE Health App](https://www2.hse.ie/health-app/about-your-hse-health-app/), [NSCR](https://about.hse.ie/our-work/technology/national-shared-care-record-nscr/), [National EHR](https://about.hse.ie/our-work/technology/electronic-health-record-ehr/) |
| Italy | Fascicolo Sanitario Elettronico (FSE) | SPID / CIE / regional auth paths | Patients access FSE through regional portals and apps under the national FSE framework. | Regional or insurer fragmented | Multi-adapter | Good target long term, but likely requires region-by-region adapters. | [FSE](https://www.fascicolosanitario.gov.it/), [Ministero della Salute](https://www.salute.gov.it/portale/fse/homeFse.jsp) |
| Latvia | eVeselība | National eID / Latvija.lv identity flow | Patients access records, prescriptions, and related services through the national eHealth portal. | Single national portal | Single adapter | Good candidate if the web portal exposes stable APIs or document feeds. | [eVeselība](https://www.eveseliba.gov.lv/), [Latvija.lv](https://latvija.gov.lv/) |
| Lithuania | eSveikata | National e-identity methods | Patients use eSveikata to access official electronic health services and records. | Single national portal | Single adapter | Promising target; verify actual patient record breadth in live flow. | [eSveikata](https://www.esveikata.lt/), [eSveikata login](https://www.ipr.esveikata.lt/) |
| Luxembourg | DSP through eSanté / MyGuichet | LuxTrust / eID / eIDAS-compatible flows | Patients access the shared care record through official eHealth services and government identity flows. | Single national portal | Single adapter | Good small-country candidate with manageable scope. | [eSanté DSP](https://www.esante.lu/portal/en/espace-patient/dsp), [MyGuichet DSP](https://guichet.public.lu/en/citoyens/sante-social/dossier-medical/dsp/consulter-dsp.html) |
| Malta | myHealth | Maltese e-ID | Patients access health records and appointments through the government myHealth service. | Single national portal | Single adapter | Good candidate if record depth is sufficient. | [myHealth](https://myhealth.gov.mt/), [digital services](https://www.servizz.gov.mt/en/Pages/Health-and-Community-Care/Health/Health-Services/WEB048/default.aspx) |
| Netherlands | PGO ecosystem via MedMij, plus provider portals | DigiD | Patients typically use a personal health environment (PGO) of their choice or provider portals rather than one state portal for all records. | Regional or insurer fragmented | Multi-adapter or standards-first | Best strategy is likely standards-first around MedMij, not browser automation against one portal. | [MedMij](https://www.medmij.nl/en/what-is-medmij), [Volgjezorg](https://www.volgjezorg.nl/english) |
| Poland | Internetowe Konto Pacjenta (IKP) / mojeIKP | Trusted Profile, e-ID, bank or mObywatel flows | Patients use the national patient account to access e-prescriptions, referrals, and other health data. | Single national portal | Single adapter | Strong candidate for a single-country adapter. | [IKP](https://pacjent.gov.pl/internetowe-konto-pacjenta), [mojeIKP](https://pacjent.gov.pl/aplikacja-mojeikp) |
| Portugal | SNS 24 Personal Area / app | SNS digital identity and citizen-auth flows | Patients use SNS 24 personal area and app for records and health-service interactions. | Single national portal over distributed systems | Single adapter + endpoint discovery | Good target; likely one citizen-facing shell over several SNS systems. | [SNS 24 Personal Area](https://www.sns24.gov.pt/guia/area-pessoal/), [SNS 24](https://www.sns24.gov.pt/) |
| Romania | DES / national digital-health and citizen-ID flows | ROeID and official patient-account flows | Official patient digital access exists, but public patient-facing scope still appears partial and evolving compared with mature national portals elsewhere. | Partial / evolving | Watch or narrow-scope pilot | Monitor before committing to a full-country integration. | [DES CNAS](https://www.des-cnas.ro/), [ROeID / EU app](https://ro.eu.gov.ro/) |
| Slovakia | National Health Portal / Electronic Health Book | National eID | Patients use the National Health Portal to access eHealth information. | Single national portal | Single adapter | Good candidate if the citizen flow is broad enough in practice. | [National Health Portal](https://www.npz.sk/), [eHealth Slovakia](https://www.ezdravotnictvo.sk/) |
| Slovenia | zVEM portal and app | SI-PASS / digital certificate / mobile identity flows | Patients use zVEM to access health records and related electronic services. | Single national portal | Single adapter | Strong candidate with coherent national flow. | [zVEM](https://zvem.ezdrav.si/), [eZdrav](https://www.ezdrav.si/) |
| Spain | Regional health portals plus national interoperable history services | Cl@ve / certificate / regional auth | Patients often access records through regional portals, while the national system supports interoperable clinical-history exchange. | Regional or insurer fragmented | Multi-adapter | Spain likely needs region-first adapters, not one national browser integration. | [HCDSNS](https://www.sanidad.gob.es/areas/saludDigital/interoperabilidadSemantica/HCDSNS.htm), [Carpeta Ciudadana](https://carpetaciudadana.gob.es/) |
| Sweden | 1177 Journalen | BankID or Freja+ | Patients use 1177 and Journalen to view records made available by regions and providers. | National portal over distributed systems | Single adapter + endpoint discovery | Already aligned with Eir’s current Swedish flow. | [1177 Journalen](https://www.1177.se/Stockholm/sa-fungerar-varden/e-tjanster/journalen/), [Inera Journalen](https://www.inera.se/tjanster/alla-tjanster-a-o/journalen/) |

## Practical Interpretation For Eir

### Tier 1: best near-term targets

These countries look most suitable for the current Eir model: patient signs in, portal shows data in a stable national flow, and a browser-based capture or extraction workflow is plausible.

- Finland
- Denmark
- Estonia
- Poland
- Austria
- Hungary
- Slovenia
- Luxembourg
- Latvia
- Malta

### Tier 2: viable, but expect more backend variation

These countries still have a strong citizen entry point, but the patient portal likely fronts several underlying systems or mixes web and app access.

- Belgium
- Portugal
- France
- Greece
- Sweden
- Bulgaria
- Croatia
- Cyprus
- Slovakia
- Lithuania

### Tier 3: fragmented or structurally harder

These countries are less likely to fit a single patient-portal automation model.

- Germany: insurer-app model rather than one national portal
- Italy: region-by-region FSE access
- Spain: region-by-region patient portals with national interoperability layer
- Netherlands: PGO ecosystem and provider portals instead of one state portal

### Tier 4: monitor, do not prioritize yet

- Ireland: patient app exists, but the full shared-care and longitudinal patient record flow is still being built out
- Czech Republic: patient-facing national scope appears narrower than a mature full longitudinal EHR
- Romania: official patient access exists, but current public patient-facing flow still looks comparatively partial

## Integration Strategy By Archetype

### 1. Single national portal

Best fit for the current Eir direction.

What to build:
- one browser recorder / extractor
- one canonical mapping layer into EIR
- per-country auth-flow handling
- per-country selector and endpoint fixtures

Countries:
- Austria
- Bulgaria
- Croatia
- Estonia
- Finland
- Hungary
- Latvia
- Lithuania
- Luxembourg
- Malta
- Poland
- Slovakia
- Slovenia

### 2. National portal over distributed systems

Still strong targets, but expect more than one data endpoint family behind the same patient portal.

What to build:
- one main browser integration
- network-first capture tooling
- endpoint clustering by feature area
- stronger fixture coverage because backend payloads may differ by provider or region

Countries:
- Belgium
- Denmark
- Portugal
- Sweden
- France
- Greece
- Cyprus

### 3. Regional or insurer fragmented

These countries need a different strategy.

What to build:
- start with one priority region, insurer, or PGO
- build adapter families, not one country-wide adapter
- treat “country support” as a bundle of supported portals

Countries:
- Germany
- Italy
- Netherlands
- Spain

### 4. Partial / evolving patient access

These should be tracked, but not treated as immediate extraction priorities.

What to build:
- a light monitoring document
- no full extraction build until the patient flow exposes stable record access

Countries:
- Czech Republic
- Ireland
- Romania

## Working Assumptions

- “Same flow as the patient” means Eir should generally prefer browser or app-observed interaction over unofficial backend integrations.
- In countries with a single strong national portal, reverse engineering should start network-first, not DOM-first.
- In countries with regional or insurer fragmentation, product planning should treat each portal family as a separate integration target.
- Mobile-app-only countries or app-dominant flows may require a second capture path beyond the current Chrome extension.

## Gaps

- Some countries expose both a web portal and an official app, but public documentation is clearer on the portal than on app transport details.
- Several official pages describe the patient service well but do not publicly document the exact backend architecture. In those rows, the integration-shape classification is an inference from the patient flow.
- Spain, Germany, Italy, the Netherlands, Ireland, and Romania deserve a second-pass deep dive before implementation decisions.
