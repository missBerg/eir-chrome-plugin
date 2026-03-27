#!/usr/bin/env node

// Filter healthcare clinics to those relevant for EgenRemiss outreach
// Input: ../healthcare-clinics.json (17,802 clinics from 1177.se)
// Output: filtered lists by category

const fs = require("fs");
const path = require("path");

const clinics = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "healthcare-clinics.json"), "utf8")
);

// --- Classification rules ---

const EXCLUDE_KEYWORDS = [
  "tandvård",
  "folktandvård",
  "tandläkar",
  "tandhygien",
  "tandregler",
  "vaccination ",
  "vaccinationsmottagning",
  "mammografi",
  "cellprov",
  "blodcentral",
  "blodgivning",
  "laboratori",
  "röntgen",
  "ambulans",
  "tolkförmedling",
  "hjälpmedel",
  "1177",
  "rådgivning sexuell",
  "familjecentral",
  "asyl",
  "smittskydd",
  "donationsmottagning",
];

const VARDCENTRAL_KEYWORDS = [
  "vårdcentral",
  "hälsocentral",
  "husläkar",
  "familjeläkar",
  "primärvård",
  "hälsoval",
  "närhälsa",
  "capio",
  "doktor24",
  "min doktor",
  "kry ",
];

const SPECIALIST_KEYWORDS = [
  "ortoped",
  "ögon",
  "öron",
  "hud",
  "dermatolog",
  "psykiatri",
  "psykolog",
  "gynekolog",
  "kirurg",
  "neurolog",
  "kardiolog",
  "urolog",
  "reumatolog",
  "allergolog",
  "gastro",
  "endokrin",
  "onkolog",
  "smärt",
  "rehab",
  "fysioterapi",
  "sjukgymnast",
  "logoped",
  "dietist",
  "habilitering",
  "geriatrik",
  "palliativ",
  "infektions",
  "lungmottagning",
  "lung ",
  "njur",
  "diabetes",
  "stroke",
  "sömnmottagning",
];

const HOSPITAL_KEYWORDS = [
  "sjukhus",
  "lasarett",
  "universitetssjukhus",
  "akutmottagning",
  "jourmottagning",
  "närakut",
];

function classify(clinic) {
  const name = clinic.name.toLowerCase();

  // Exclude irrelevant clinic types
  for (const kw of EXCLUDE_KEYWORDS) {
    if (name.includes(kw)) return "excluded";
  }

  for (const kw of VARDCENTRAL_KEYWORDS) {
    if (name.includes(kw)) return "vardcentral";
  }

  for (const kw of SPECIALIST_KEYWORDS) {
    if (name.includes(kw)) return "specialist";
  }

  for (const kw of HOSPITAL_KEYWORDS) {
    if (name.includes(kw)) return "hospital";
  }

  // Generic "mottagning" that didn't match anything specific
  if (name.includes("mottagning")) return "other_mottagning";

  return "uncategorized";
}

// --- Classify all clinics ---

const categories = {};
for (const clinic of clinics) {
  const cat = classify(clinic);
  if (!categories[cat]) categories[cat] = [];
  categories[cat].push(clinic);
}

// --- Print summary ---

console.log("=== EgenRemiss Clinic Filtering ===\n");
console.log(`Total clinics in database: ${clinics.length}\n`);

const TARGET_CATEGORIES = ["vardcentral", "specialist", "hospital"];
let totalTargets = 0;

for (const [cat, list] of Object.entries(categories).sort(
  (a, b) => b[1].length - a[1].length
)) {
  const isTarget = TARGET_CATEGORIES.includes(cat);
  const marker = isTarget ? " <-- TARGET" : "";
  console.log(`  ${cat}: ${list.length}${marker}`);
  if (isTarget) totalTargets += list.length;
}

console.log(`\nTotal target clinics: ${totalTargets}`);
console.log(
  `Excluded: ${clinics.length - totalTargets} (${(((clinics.length - totalTargets) / clinics.length) * 100).toFixed(1)}%)\n`
);

// --- Export target lists ---

const outputDir = __dirname;

for (const cat of TARGET_CATEGORIES) {
  const list = categories[cat] || [];
  const outPath = path.join(outputDir, `targets-${cat}.json`);
  fs.writeFileSync(outPath, JSON.stringify(list, null, 2));
  console.log(`Wrote ${list.length} clinics to targets-${cat}.json`);
}

// Combined target list
const allTargets = TARGET_CATEGORIES.flatMap((cat) => categories[cat] || []);
const outPath = path.join(outputDir, "targets-all.json");
fs.writeFileSync(outPath, JSON.stringify(allTargets, null, 2));
console.log(`Wrote ${allTargets.length} clinics to targets-all.json`);

// CSV export for easy review
const csvHeader = "name,address,phone,url,category\n";
const csvRows = allTargets.map((c) => {
  const cat = classify(c);
  return `"${c.name}","${c.address || ""}","${c.phone || ""}","${c.url || ""}","${cat}"`;
});
fs.writeFileSync(
  path.join(outputDir, "targets-all.csv"),
  csvHeader + csvRows.join("\n")
);
console.log(`Wrote ${allTargets.length} clinics to targets-all.csv`);

// --- Show some uncategorized for review ---

const uncat = categories["uncategorized"] || [];
const otherMott = categories["other_mottagning"] || [];
console.log(
  `\n--- Review needed: ${uncat.length} uncategorized + ${otherMott.length} other_mottagning ---`
);
console.log("Sample uncategorized:");
for (const c of uncat.slice(0, 15)) {
  console.log(`  ${c.name}`);
}
console.log("\nSample other_mottagning:");
for (const c of otherMott.slice(0, 15)) {
  console.log(`  ${c.name}`);
}
