#!/usr/bin/env node

// Scrape clinic's OWN website domains from 1177.se pages, then generate
// likely email patterns for each clinic.
//
// Each 1177.se "kontaktkort" page can contain:
//   1. A <dt>Webbplats:</dt> section with a link to the clinic's own site
//   2. Structured LD+JSON with a "url" field pointing to the clinic's site
//   3. External links (href) not on 1177.se
//
// We extract the clinic's own domain and then suggest common Swedish
// healthcare email patterns: info@, kontakt@, reception@, etc.
//
// Usage:
//   node scrape-clinic-websites.js                   # process all clinics
//   node scrape-clinic-websites.js --test 30         # test with first 30
//   node scrape-clinic-websites.js --test 30 --spread # test 30 spread across dataset
//   node scrape-clinic-websites.js --resume          # resume from checkpoint
//   node scrape-clinic-websites.js --offset 500      # start from index 500
//   node scrape-clinic-websites.js --analyze         # analyze results only

const fs = require("fs");
const path = require("path");

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const CONCURRENCY = 5;
const DELAY_MS = 300; // polite crawling — 1177.se is a public health service

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
const testMode = args.includes("--test");
const testLimit = testMode
  ? parseInt(args[args.indexOf("--test") + 1]) || 30
  : Infinity;
const resumeMode = args.includes("--resume");
const analyzeOnly = args.includes("--analyze");
const offsetArg = args.includes("--offset")
  ? parseInt(args[args.indexOf("--offset") + 1]) || 0
  : 0;
const fileArg = args.includes("--file")
  ? args[args.indexOf("--file") + 1]
  : null;

const TARGETS_FILE = fileArg
  ? path.resolve(fileArg)
  : path.join(__dirname, "targets-all.json");
const baseName = path.basename(TARGETS_FILE, ".json").replace("targets-", "");
const suffix = baseName === "all" ? "" : `-${baseName}`;
const OUTPUT_FILE = path.join(__dirname, `clinics-with-websites${suffix}.json`);
const CHECKPOINT_FILE = path.join(__dirname, `.website-scrape-checkpoint-targets-${baseName}.json`);

// ---------------------------------------------------------------------------
// Known brand → domain mappings (large chains with predictable domains)
// ---------------------------------------------------------------------------
const BRAND_DOMAINS = {
  capio: "capio.se",
  aleris: "aleris.se",
  "praktikertjänst": "ptj.se",
  "kry": "kry.se",
  "doktor.se": "doktor.se",
  achima: "achima.se",
  helsa: "helsa.se",
  feelgood: "feelgood.se",
  närhälsan: "narhalsan.se",
  "bra liv": "rjl.se",
  wetterhälsan: "wetterhalsan.se",
  curera: "curera.se",
};

// Common Swedish healthcare email prefixes
const EMAIL_PREFIXES = [
  "info",
  "kontakt",
  "reception",
  "bokning",
  "vardcentral",
  "mottagning",
];

// Domains to skip (not real clinic websites — common false positives)
const SKIP_DOMAINS = [
  "1177.se",
  "google.se",
  "google.com",
  "funktionstjanster.se",
  "youtube.com",
  "facebook.com",
  "instagram.com",
  "twitter.com",
  "linkedin.com",
  "apple.com",
  "play.google.com",
  "svenskakyrkan.se",    // Swedish Church — linked from many pages but not a clinic
  "umo.se",              // Youth health info site — not a clinic domain
  "youmo.se",            // Youth health info (multilingual)
  "vardguiden.se",       // Old health guide
  "socialstyrelsen.se",  // Government agency
  "folkhalsomyndigheten.se", // Public Health Agency
  "ivo.se",              // Health Inspectorate
  "patientnamnd.se",     // Patient advisory
  "inera.se",            // E-health infrastructure
  "klara.nu",            // Booking system
  "mittval.se",          // Choice of provider system
  "regionvasterbotten.se", // Sometimes generic region link
  "skr.se",              // Sveriges Kommuner och Regioner (association)
  "vantetider.se",       // Wait times portal
  "patientforsakring.se",// Patient insurance
  "lof.se",              // Patient insurance (Löf)
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function extractDomain(urlStr) {
  try {
    const u = new URL(urlStr);
    let host = u.hostname.replace(/^www\./, "");
    return host;
  } catch {
    return null;
  }
}

function isSkippedDomain(domain) {
  return SKIP_DOMAINS.some((s) => domain === s || domain.endsWith("." + s));
}

function detectBrand(clinicName) {
  const lower = clinicName.toLowerCase();
  for (const [brand, domain] of Object.entries(BRAND_DOMAINS)) {
    if (lower.includes(brand)) {
      return { brand, domain };
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Core: Fetch a single 1177 page and extract the clinic's own website
// ---------------------------------------------------------------------------
async function fetchClinicWebsite(clinic) {
  if (!clinic.url) return null;

  try {
    const res = await fetch(clinic.url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) EgenRemiss-Research/1.0",
        Accept: "text/html",
      },
      signal: AbortSignal.timeout(15000),
      redirect: "follow",
    });

    if (!res.ok) return { error: `HTTP ${res.status}` };

    const html = await res.text();
    const result = { sources: [] };

    // ---------------------------------------------------------------
    // Strategy 1: LD+JSON structured data (most reliable)
    // ---------------------------------------------------------------
    const ldMatch = html.match(
      /<script type="application\/ld\+json">([\s\S]*?)<\/script>/
    );
    if (ldMatch) {
      try {
        const ld = JSON.parse(ldMatch[1]);
        if (ld.mainEntity && Array.isArray(ld.mainEntity)) {
          for (const entity of ld.mainEntity) {
            if (entity.url) {
              const domain = extractDomain(entity.url);
              if (domain && !isSkippedDomain(domain)) {
                result.websiteUrl = entity.url;
                result.domain = domain;
                result.sources.push("ld+json");
                break;
              }
            }
          }
        }
      } catch {
        // LD+JSON parse error — continue with other strategies
      }
    }

    // ---------------------------------------------------------------
    // Strategy 2: <dt>Webbplats:</dt><dd><a href="..."> pattern
    // ---------------------------------------------------------------
    if (!result.domain) {
      const webbplatsMatch = html.match(
        /Webbplats:<\/dt>\s*<dd[^>]*>\s*<a[^>]+href="([^"]+)"/
      );
      if (webbplatsMatch) {
        const domain = extractDomain(webbplatsMatch[1]);
        if (domain && !isSkippedDomain(domain)) {
          result.websiteUrl = webbplatsMatch[1];
          result.domain = domain;
          result.sources.push("webbplats-label");
        }
      }
    }

    // ---------------------------------------------------------------
    // Strategy 3: find-us__webpage CSS class
    // ---------------------------------------------------------------
    if (!result.domain) {
      const classMatch = html.match(
        /class="find-us__webpage[^"]*"[^>]*href="([^"]+)"/
      );
      if (classMatch) {
        const domain = extractDomain(classMatch[1]);
        if (domain && !isSkippedDomain(domain)) {
          result.websiteUrl = classMatch[1];
          result.domain = domain;
          result.sources.push("css-class");
        }
      }
    }

    // ---------------------------------------------------------------
    // Strategy 4: External links (fallback — pick most likely)
    // ---------------------------------------------------------------
    if (!result.domain) {
      const extLinks = [
        ...html.matchAll(/href="(https?:\/\/[^"]+)"/g),
      ]
        .map((m) => m[1])
        .map((u) => u.replace(/&amp;/g, "&"))
        .filter((u) => {
          const d = extractDomain(u);
          return d && !isSkippedDomain(d);
        });

      // Deduplicate by domain
      const domainMap = {};
      for (const link of extLinks) {
        const d = extractDomain(link);
        if (d && !domainMap[d]) domainMap[d] = link;
      }

      // Pick the most likely clinic domain (prefer .se, avoid booking systems)
      const candidates = Object.entries(domainMap).filter(
        ([d]) =>
          !d.includes("online.") &&
          !d.includes("booking.") &&
          !d.includes("idp.")
      );

      if (candidates.length === 1) {
        result.websiteUrl = candidates[0][1];
        result.domain = candidates[0][0];
        result.sources.push("external-link-only");
      } else if (candidates.length > 1) {
        // Prefer .se domains
        const seDomain = candidates.find(([d]) => d.endsWith(".se"));
        if (seDomain) {
          result.websiteUrl = seDomain[1];
          result.domain = seDomain[0];
          result.sources.push("external-link-se");
        } else {
          result.websiteUrl = candidates[0][1];
          result.domain = candidates[0][0];
          result.sources.push("external-link-first");
        }
      }
    }

    // ---------------------------------------------------------------
    // Also extract any emails found directly on the 1177 page
    // ---------------------------------------------------------------
    const emailPattern =
      /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g;
    const emails = [
      ...new Set(
        (html.match(emailPattern) || []).filter(
          (e) =>
            !e.includes("1177.se") &&
            !e.includes("example.com") &&
            !e.includes("noreply") &&
            !e.endsWith(".png") &&
            !e.endsWith(".jpg") &&
            !e.endsWith(".svg")
        )
      ),
    ];
    if (emails.length > 0) result.foundEmails = emails;

    return result;
  } catch (err) {
    return { error: err.message };
  }
}

// ---------------------------------------------------------------------------
// Generate email suggestions for a clinic
// ---------------------------------------------------------------------------
function generateEmailSuggestions(clinic, scrapeResult) {
  const suggestions = [];
  let domain = scrapeResult?.domain;

  // If we did not find a domain from scraping, check brand mapping
  if (!domain) {
    const brand = detectBrand(clinic.name);
    if (brand) {
      domain = brand.domain;
    }
  }

  if (!domain) return { domain: null, suggestions: [] };

  // Add common prefix patterns
  for (const prefix of EMAIL_PREFIXES) {
    suggestions.push(`${prefix}@${domain}`);
  }

  return { domain, suggestions };
}

// ---------------------------------------------------------------------------
// Batch processor with checkpoint/resume
// ---------------------------------------------------------------------------
async function processInBatches(clinics, batchSize) {
  const results = [];
  let processed = 0;
  let withDomain = 0;
  let withEmail = 0;

  // Load checkpoint if resuming
  let startIndex = 0;
  if (resumeMode && fs.existsSync(CHECKPOINT_FILE)) {
    const checkpoint = JSON.parse(fs.readFileSync(CHECKPOINT_FILE, "utf8"));
    startIndex = checkpoint.lastIndex + 1;
    results.push(...checkpoint.results);
    withDomain = results.filter((r) => r.domain).length;
    withEmail = results.filter((r) => r.foundEmails?.length).length;
    console.log(
      `  Resuming from index ${startIndex} (${results.length} already done)`
    );
  }

  if (offsetArg > startIndex) {
    startIndex = offsetArg;
    console.log(`  Starting from offset ${startIndex}`);
  }

  for (let i = startIndex; i < clinics.length; i += batchSize) {
    const batch = clinics.slice(i, Math.min(i + batchSize, clinics.length));
    const batchResults = await Promise.all(
      batch.map(async (clinic) => {
        const scrapeResult = await fetchClinicWebsite(clinic);
        const emailInfo = generateEmailSuggestions(clinic, scrapeResult);
        const brand = detectBrand(clinic.name);

        return {
          hsaId: clinic.hsaId,
          name: clinic.name,
          address: clinic.address,
          phone: clinic.phone,
          url1177: clinic.url,
          brand: brand?.brand || null,
          websiteUrl: scrapeResult?.websiteUrl || null,
          domain: scrapeResult?.domain || emailInfo.domain || null,
          domainSource: scrapeResult?.sources?.join(",") || (brand ? "brand-mapping" : null),
          foundEmails: scrapeResult?.foundEmails || null,
          suggestedEmails: emailInfo.suggestions.length > 0 ? emailInfo.suggestions : null,
          error: scrapeResult?.error || null,
        };
      })
    );

    results.push(...batchResults);
    processed += batch.length;
    withDomain += batchResults.filter((r) => r.domain).length;
    withEmail += batchResults.filter((r) => r.foundEmails?.length).length;

    // Progress
    const total = clinics.length;
    const done = i + batch.length;
    const pct = ((done / total) * 100).toFixed(1);
    process.stdout.write(
      `\r  ${done}/${total} (${pct}%) — ${withDomain} domains, ${withEmail} emails found`
    );

    // Save checkpoint every 50 clinics
    if (done % 50 < batchSize && !testMode) {
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

// ---------------------------------------------------------------------------
// Analyze existing results
// ---------------------------------------------------------------------------
function analyzeResults(results) {
  console.log("\n══════════════════════════════════════════════════════");
  console.log("  ANALYSIS");
  console.log("══════════════════════════════════════════════════════\n");

  const total = results.length;
  const withDomain = results.filter((r) => r.domain);
  const withEmails = results.filter((r) => r.foundEmails?.length);
  const withErrors = results.filter((r) => r.error);

  console.log(`Total clinics processed: ${total}`);
  console.log(
    `With own website domain: ${withDomain.length} (${((withDomain.length / total) * 100).toFixed(1)}%)`
  );
  console.log(
    `With emails on 1177 page: ${withEmails.length} (${((withEmails.length / total) * 100).toFixed(1)}%)`
  );
  console.log(`Errors: ${withErrors.length}`);

  // Domain source breakdown
  console.log("\n--- Domain source breakdown ---");
  const sources = {};
  withDomain.forEach((r) => {
    const src = r.domainSource || "unknown";
    sources[src] = (sources[src] || 0) + 1;
  });
  Object.entries(sources)
    .sort((a, b) => b[1] - a[1])
    .forEach(([k, v]) => console.log(`  ${k}: ${v}`));

  // Top domains
  console.log("\n--- Top domains found ---");
  const domains = {};
  withDomain.forEach((r) => {
    domains[r.domain] = (domains[r.domain] || 0) + 1;
  });
  Object.entries(domains)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 25)
    .forEach(([k, v]) => console.log(`  ${k}: ${v} clinics`));

  // Brand vs independent
  console.log("\n--- Brand coverage ---");
  const brands = {};
  results.forEach((r) => {
    const b = r.brand || "(independent/unknown)";
    if (!brands[b]) brands[b] = { total: 0, withDomain: 0 };
    brands[b].total++;
    if (r.domain) brands[b].withDomain++;
  });
  Object.entries(brands)
    .sort((a, b) => b[1].total - a[1].total)
    .forEach(([k, v]) =>
      console.log(
        `  ${k}: ${v.total} total, ${v.withDomain} with domain (${((v.withDomain / v.total) * 100).toFixed(0)}%)`
      )
    );

  // Domain TLD analysis
  console.log("\n--- Domain TLD distribution ---");
  const tlds = {};
  withDomain.forEach((r) => {
    const parts = r.domain.split(".");
    const tld = "." + parts[parts.length - 1];
    tlds[tld] = (tlds[tld] || 0) + 1;
  });
  Object.entries(tlds)
    .sort((a, b) => b[1] - a[1])
    .forEach(([k, v]) => console.log(`  ${k}: ${v}`));

  // Sample results
  console.log("\n--- Sample clinics with domains ---");
  withDomain.slice(0, 15).forEach((r) => {
    console.log(`  ${r.name}`);
    console.log(`    Domain: ${r.domain} (via ${r.domainSource})`);
    if (r.foundEmails) console.log(`    Emails: ${r.foundEmails.join(", ")}`);
    if (r.suggestedEmails)
      console.log(`    Suggested: ${r.suggestedEmails.slice(0, 3).join(", ")}`);
    console.log("");
  });

  // Clinics without domain
  console.log("--- Sample clinics WITHOUT domain ---");
  results
    .filter((r) => !r.domain)
    .slice(0, 10)
    .forEach((r) => {
      console.log(`  ${r.name} — ${r.error || "no website found"}`);
    });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  if (!fs.existsSync(TARGETS_FILE)) {
    console.error("Missing targets-all.json. Run filter-clinics.js first.");
    process.exit(1);
  }

  // Analyze-only mode
  if (analyzeOnly) {
    if (!fs.existsSync(OUTPUT_FILE)) {
      console.error("No results file found. Run the scraper first.");
      process.exit(1);
    }
    const results = JSON.parse(fs.readFileSync(OUTPUT_FILE, "utf8"));
    analyzeResults(results);
    return;
  }

  let clinics = JSON.parse(fs.readFileSync(TARGETS_FILE, "utf8"));

  if (testMode && args.includes("--spread")) {
    // Spread sampling: pick N clinics evenly across the dataset
    const step = Math.floor(clinics.length / testLimit);
    const sampled = [];
    for (let i = 0; i < clinics.length && sampled.length < testLimit; i += step) {
      sampled.push(clinics[i]);
    }
    clinics = sampled;
    console.log(`\n  Test mode (spread): processing ${clinics.length} clinics from across the dataset\n`);
  } else if (testMode) {
    clinics = clinics.slice(0, testLimit);
    console.log(`\n  Test mode: processing ${clinics.length} clinics\n`);
  } else {
    console.log(`\n  Processing ${clinics.length} clinics...\n`);
  }

  console.log("Scraping clinic websites from 1177.se pages...\n");
  const results = await processInBatches(clinics, CONCURRENCY);

  // Save results
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(results, null, 2));
  console.log(`\nSaved results to ${path.basename(OUTPUT_FILE)}`);

  // Run analysis
  analyzeResults(results);

  // Clean up checkpoint on successful completion
  if (fs.existsSync(CHECKPOINT_FILE)) {
    fs.unlinkSync(CHECKPOINT_FILE);
    console.log("\nCheckpoint cleaned up.");
  }
}

main().catch(console.error);
