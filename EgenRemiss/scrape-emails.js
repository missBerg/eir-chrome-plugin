#!/usr/bin/env node

// Scrape email addresses from 1177.se clinic detail pages
// Uses the URL field from our clinic data to visit each page and extract emails
//
// Usage:
//   node scrape-emails.js                  # process all targets
//   node scrape-emails.js --test 20        # test with first 20 clinics
//   node scrape-emails.js --resume         # resume from last checkpoint

const fs = require("fs");
const path = require("path");

const TARGETS_FILE = path.join(__dirname, "targets-all.json");
const OUTPUT_FILE = path.join(__dirname, "clinics-with-emails.json");
const CHECKPOINT_FILE = path.join(__dirname, ".scrape-checkpoint.json");
const CONCURRENCY = 5;
const DELAY_MS = 200; // be polite to 1177.se

const args = process.argv.slice(2);
const testMode = args.includes("--test");
const testLimit = testMode
  ? parseInt(args[args.indexOf("--test") + 1]) || 20
  : Infinity;
const resumeMode = args.includes("--resume");

async function fetchClinicEmail(clinic) {
  if (!clinic.url) return null;

  try {
    const res = await fetch(clinic.url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) EgenRemiss-Research/1.0",
        Accept: "text/html",
      },
      signal: AbortSignal.timeout(10000),
    });

    if (!res.ok) return null;

    const html = await res.text();

    // Extract emails from the page
    const emailPattern = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g;
    const emails = [...new Set(html.match(emailPattern) || [])];

    // Filter out generic/irrelevant emails
    const filtered = emails.filter(
      (e) =>
        !e.includes("1177.se") &&
        !e.includes("example.com") &&
        !e.includes("noreply") &&
        !e.endsWith(".png") &&
        !e.endsWith(".jpg")
    );

    return filtered.length > 0 ? filtered : null;
  } catch {
    return null;
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function processInBatches(clinics, batchSize) {
  const results = [];
  let processed = 0;
  let withEmail = 0;

  // Load checkpoint if resuming
  let startIndex = 0;
  if (resumeMode && fs.existsSync(CHECKPOINT_FILE)) {
    const checkpoint = JSON.parse(fs.readFileSync(CHECKPOINT_FILE, "utf8"));
    startIndex = checkpoint.lastIndex + 1;
    results.push(...checkpoint.results);
    withEmail = results.filter((r) => r.emails).length;
    console.log(`Resuming from index ${startIndex} (${results.length} already processed)`);
  }

  for (let i = startIndex; i < clinics.length; i += batchSize) {
    const batch = clinics.slice(i, i + batchSize);
    const batchResults = await Promise.all(
      batch.map(async (clinic) => {
        const emails = await fetchClinicEmail(clinic);
        return { ...clinic, emails };
      })
    );

    results.push(...batchResults);
    processed += batch.length;
    withEmail += batchResults.filter((r) => r.emails).length;

    // Progress
    const pct = ((processed + startIndex) / clinics.length * 100).toFixed(1);
    process.stdout.write(
      `\r  ${processed + startIndex}/${clinics.length} (${pct}%) — ${withEmail} emails found`
    );

    // Save checkpoint every 100
    if ((processed + startIndex) % 100 < batchSize) {
      fs.writeFileSync(
        CHECKPOINT_FILE,
        JSON.stringify({ lastIndex: i + batch.length - 1, results })
      );
    }

    await sleep(DELAY_MS);
  }

  console.log("");
  return results;
}

async function main() {
  if (!fs.existsSync(TARGETS_FILE)) {
    console.error("Run filter-clinics.js first to generate targets-all.json");
    process.exit(1);
  }

  let clinics = JSON.parse(fs.readFileSync(TARGETS_FILE, "utf8"));

  if (testMode) {
    clinics = clinics.slice(0, testLimit);
    console.log(`Test mode: processing ${clinics.length} clinics\n`);
  } else {
    console.log(`Processing ${clinics.length} target clinics...\n`);
  }

  console.log("Scraping emails from 1177.se clinic pages...");
  const results = await processInBatches(clinics, CONCURRENCY);

  const withEmails = results.filter((r) => r.emails);
  const withoutEmails = results.filter((r) => !r.emails);

  console.log(`\n=== Results ===`);
  console.log(`Total processed: ${results.length}`);
  console.log(`With email: ${withEmails.length} (${(withEmails.length / results.length * 100).toFixed(1)}%)`);
  console.log(`Without email: ${withoutEmails.length}`);

  // Save results
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(withEmails, null, 2));
  console.log(`\nSaved ${withEmails.length} clinics with emails to clinics-with-emails.json`);

  // Show sample
  if (withEmails.length > 0) {
    console.log("\nSample clinics with emails:");
    for (const c of withEmails.slice(0, 10)) {
      console.log(`  ${c.name}: ${c.emails.join(", ")}`);
    }
  }

  // Clean up checkpoint
  if (fs.existsSync(CHECKPOINT_FILE)) {
    fs.unlinkSync(CHECKPOINT_FILE);
  }
}

main().catch(console.error);
