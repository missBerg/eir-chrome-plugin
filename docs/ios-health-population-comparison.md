# iOS: Jämföra Apple Health med befolkningen

Det här dokumentet beskriver vad som behöver byggas i iOS-appen för att lösa user case i [salgo60/eir-open-apps#7](https://github.com/salgo60/eir-open-apps/issues/7): att låta användaren jämföra sina egna Apple Health-värden med referensdata för befolkningen.

## Kort slutsats

Appen har redan en bra grund för detta:

- Apple Health-data kan redan hämtas via `HealthKitService`
- importerad HealthKit-data kan redan visas i appen
- appen kör på iOS 17 och använder redan `Charts`

Det som saknas är inte främst HealthKit-integrationen, utan ett nytt lager för:

- referensdata för befolkningen
- normalisering mellan egna värden och referensvärden
- percentil- och kohortberäkning
- ett dedikerat jämförelse-UI
- tydlig proveniens och privacy-hantering

## Nuvarande läge i appen

Det som redan finns i koden:

- [HealthKitService.swift](/Users/birger/Community/eir-chrome-plugin/iOS/EirViewer/Sources/EirViewer/Services/HealthKitService.swift) kan läsa flera HealthKit-mått och dagliga aggregat.
- [HealthKitImportViewModel.swift](/Users/birger/Community/eir-chrome-plugin/iOS/EirViewer/Sources/EirViewer/ViewModels/HealthKitImportViewModel.swift) hanterar authorization, import och preview.
- [HealthKitToEirConverter.swift](/Users/birger/Community/eir-chrome-plugin/iOS/EirViewer/Sources/EirViewer/Services/HealthKitToEirConverter.swift) gör om importerade mätningar till appens EIR-format.
- [JournalView.swift](/Users/birger/Community/eir-chrome-plugin/iOS/EirViewer/Sources/EirViewer/Views/Journal/JournalView.swift) använder redan `Charts`, vilket betyder att det inte behövs något nytt chart-bibliotek.
- [ContentView.swift](/Users/birger/Community/eir-chrome-plugin/iOS/EirViewer/Sources/EirViewer/Views/ContentView.swift) och [ActionsView.swift](/Users/birger/Community/eir-chrome-plugin/iOS/EirViewer/Sources/EirViewer/Views/Actions/ActionsView.swift) ger naturliga platser att lägga en ny jämförelsefunktion.

Viktiga begränsningar i nuläget:

- Appen importerar råa eller dagligt aggregerade värden, men beräknar inte percentiler.
- Det finns ingen modell för externa referensdataset.
- Det finns ingen pipeline som mappar ett Apple Health-mått till ett jämförbart populationsmått.
- Det finns inget UI för "du ligger över/under X% av befolkningen".
- Det finns ingen hantering av kohorter som ålder, kön, region eller tidsfönster.

## Vad som behöver byggas

### 1. En tydlig metric-model för jämförbara mått

Först behövs en separat modell för de mått som verkligen går att jämföra mot befolkningsdata. Alla nuvarande `HealthDataCategory` är inte automatiskt lämpliga.

Föreslagen ny modell:

- `ComparableHealthMetric`
- `MetricAggregationWindow`
- `PopulationCohort`
- `MetricComparisonResult`

Exempel på mått för MVP:

- steg per dag
- vilopuls
- aktiv energi per dag
- vikt eller BMI
- sömntid per natt

Det här blir en ny domän ovanpå `HealthDataCategory`, inte en ersättning av den. Skälet är att importformatet och jämförelselogiken har olika behov.

### 2. Utökad HealthKit-läsning för rätt jämförelsemått

Nuvarande `HealthKitService` läser bland annat steg, puls, aktiv energi och vikt, men ett jämförelseflöde behöver mer kontrollerade utdrag:

- explicit stöd för vilopuls i stället för generell puls när referensdataset kräver det
- stöd för sömn om sömn ska ingå i MVP
- beräkning av stabila periodvärden, till exempel:
  - 30-dagars genomsnitt
  - 90-dagars median
  - senaste 7 dagarnas trend

Det behövs därför nya metoder i eller bredvid `HealthKitService` som returnerar "comparison-ready" aggregat, inte bara råa prover.

Exempel på nya ansvar:

- `fetchComparableMetricValue(metric:window:)`
- `fetchTrendSeries(metric:window:)`
- `fetchDemographicInputs()`

### 3. Demografi och cohort matching

För att jämförelsen ska bli meningsfull måste användaren mappas till rätt kohort.

Minimikrav:

- ålder eller åldersspann
- biologiskt kön eller annan tillgänglig könskategori om referensdataset kräver det
- land eller region när dataset är geografiskt uppdelade

Detta kräver:

- läsning av födelsedata och biologiskt kön från HealthKit där möjligt
- fallback i UI om värdet inte finns eller inte får användas
- lokal modell för hur appen väljer kohort

Föreslagna modeller:

- `UserComparisonProfile`
- `PopulationCohortKey`

Viktigt: kohortvalet måste vara transparent i UI:t, till exempel "Jämfört med kvinnor 40-49 år i Sverige".

### 4. Referensdata-lager

Det här är den största nya byggstenen. Appen behöver ett strukturerat sätt att hämta, lagra och versionera populationsdata.

Det behövs:

- en källa för referensdata, exempelvis JSON från backend, statiska bundlade filer eller nedladdad cache
- ett gemensamt format för mått, kohorter, percentiler och metadata
- versionshantering så att appen vet vilken datasetversion som används
- datumstämplar och proveniens för varje jämförelse

Föreslagna modeller:

- `PopulationDataset`
- `PopulationMetricDefinition`
- `PopulationPercentileBand`
- `PopulationStatistic`
- `PopulationDataSourceMetadata`

Föreslagen service:

- `PopulationReferenceService`

Ansvar:

- ladda dataset
- cacha dataset lokalt
- validera versionsnummer
- exponera rätt referensserie för ett visst mått och en viss kohort

Tekniskt val för MVP:

- börja med lokalt cachad JSON
- håll all beräkning på enheten
- skicka inte upp rå HealthKit-data till servern

Det ger en mycket enklare privacy-berättelse.

### 5. Jämförelsemotor

När både användarens aggregerade mått och rätt referensdata finns behövs en separat jämförelsemotor.

Föreslagen service:

- `MetricComparisonEngine`

Ansvar:

- mappa HealthKit-mått till datasetmått
- kontrollera att enheterna är jämförbara
- beräkna percentil
- skapa en textvänlig tolkning
- leverera data till grafer och kort

Output från motorn bör vara något i stil med:

- användarens värde
- referensmedian
- percentil
- avvikelse från median
- trend mot egen historik
- osäkerhets- eller kvalitetsflagga

Exempel:

- "Du ligger i percentil 68 för steg per dag jämfört med män 40-49 år i Sverige."
- "Ditt värde bygger på 27 av de senaste 30 dagarna."

### 6. Jämförelse-UI i SwiftUI

Det behövs en egen vyhierarki för detta, inte bara en extra graf i journalvyn.

Föreslagna nya views:

- `HealthComparisonOverviewView`
- `MetricComparisonDetailView`
- `ComparisonCohortPicker`
- `ComparisonInsightCard`
- `PopulationReferenceDisclosureView`

UI:t bör innehålla:

- metric picker
- tydlig kohortetikett
- graf med eget värde mot referensfördelning
- enkel texttolkning
- "hur räknas detta?"-sektion
- källa och uppdateringsdatum

Bra första visualiseringar:

- percentil-kort
- box plot eller percentile band
- linjegraf med egen trend mot referensmedian

Eftersom `Charts` redan används i appen kan detta byggas med befintlig stack.

### 7. Placering i appens navigation

Det finns tre rimliga alternativ:

- lägg funktionen under `For You` som en insiktsdriven upplevelse
- lägg den under `State` nära nuvarande hälsodata
- skapa en separat "Compare"-yta

Min rekommendation för den här kodbasen:

- visa 1-2 insiktskort i `For You`
- ha en full jämförelsevy under `State`

Det matchar nuvarande struktur bäst:

- `For You` passar för tolkningar och motiverande kort
- `State` passar för datanära analys

### 8. Persistence och cache

Resultat bör kunna återanvändas utan att appen gör om allt vid varje öppning.

Det behövs lokal lagring för:

- senast hämtade referensdataset
- senaste jämförelser per profil
- beräkningsmetadata som tidsfönster och kohort

Föreslagna komponenter:

- `HealthComparisonStore`
- `CachedPopulationDatasetStore`

Det här kan initialt byggas med JSON-filer eller `UserDefaults`/lokala filer, men bör hållas separat från EIR-journalfilerna eftersom det är derived data.

### 9. Proveniens, transparens och safety

Det här behöver synas i produkten, inte bara i koden.

Appen bör för varje jämförelse kunna visa:

- vilket dataset som användes
- vilken version datasetet hade
- när det senast uppdaterades
- vilken kohort som användes
- hur användarens värde räknades fram

Appen bör också undvika kliniskt hårda formuleringar. Den här funktionen ska uttryckas som kontext och självförståelse, inte diagnos.

### 10. Testning

Det här behöver egna tester eftersom feltolkade percentiler snabbt blir missvisande.

Föreslagna tester:

- enhetstester för percentilberäkning
- tester för metric mapping mellan HealthKit och dataset
- tester för kohortval
- snapshot- eller view tests för jämförelsekort
- tester för fallback när referensdata saknas

## Föreslagen filstruktur

Ett rimligt första upplägg i iOS-appen:

- `iOS/EirViewer/Sources/EirViewer/Models/ComparableHealthMetric.swift`
- `iOS/EirViewer/Sources/EirViewer/Models/PopulationDataset.swift`
- `iOS/EirViewer/Sources/EirViewer/Models/MetricComparisonResult.swift`
- `iOS/EirViewer/Sources/EirViewer/Services/PopulationReferenceService.swift`
- `iOS/EirViewer/Sources/EirViewer/Services/MetricComparisonEngine.swift`
- `iOS/EirViewer/Sources/EirViewer/Services/HealthComparisonCache.swift`
- `iOS/EirViewer/Sources/EirViewer/ViewModels/HealthComparisonViewModel.swift`
- `iOS/EirViewer/Sources/EirViewer/Views/HealthComparison/HealthComparisonOverviewView.swift`
- `iOS/EirViewer/Sources/EirViewer/Views/HealthComparison/MetricComparisonDetailView.swift`

Möjliga ändringar i befintliga filer:

- `HealthKitService.swift`
- `ContentView.swift`
- `JournalView.swift`
- `ActionsView.swift`
- `EirViewerApp.swift`

## Rekommenderad MVP

För att hålla det byggbart bör första versionen vara mindre än visionen i issuet.

MVP-förslag:

- endast 3 mått: steg, vilopuls, sömn
- endast en geografi: Sverige
- endast nationella kohorter
- endast ålder + kön som segmentering
- endast lokal cache av ett färdigt referensdataset
- endast jämförelse på 30 dagar

Det ger en fullt begriplig första release utan att appen först behöver bli en generell open-data-plattform.

## Frågor som måste avgöras innan implementation

Följande är produkt- och databeslut, inte bara iOS-bygge:

- vilka referensdataset är tillräckligt bra för varje mått
- vilka mått ska ingå i MVP
- ska all jämförelse ske helt lokalt eller via backend
- hur ska region väljas om dataset finns på flera nivåer
- hur ska avsaknad av kön eller ålder hanteras
- hur ofta får referensdata uppdateras

## Praktisk implementation i denna kodbas

Den snabbaste realistiska vägen i just den här appen är:

1. Utöka `HealthKitService` med comparison-ready aggregat och demografi.
2. Lägg till modeller och services för referensdata och percentilberäkning.
3. Bygg en ny `HealthComparisonViewModel`.
4. Lägg en första jämförelsevy under `State`.
5. Återanvänd `Charts` för percentile band och trendgraf.
6. Lägg senare till sammanfattande insiktskort i `For You`.

## Slutbedömning

För att lösa issue #7 i iOS-appen behöver man inte bygga om hela appen. Det som behövs är främst ett nytt "comparison layer" ovanpå befintlig HealthKit-import:

- ett referensdata-lager
- en kohort- och percentilmotor
- ett tydligt SwiftUI-gränssnitt för jämförelser
- transparens kring källa, kohort och beräkning

Det är alltså mer en data- och produktarkitekturfråga än en ren HealthKit-fråga.
