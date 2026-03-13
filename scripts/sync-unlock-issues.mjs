import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const ROOT = process.cwd();
const REPO = process.env.UNLOCK_GITHUB_REPO || "BirgerMoell/eir-open-apps";
const [OWNER, NAME] = REPO.split("/");
const DATA_PATH = path.join(ROOT, "docs", "unlock-countries.json");
const OUTPUT_PATH = path.join(ROOT, "docs", "unlock-issues.json");

const STATUS_LABELS = {
  unlocked: "unlock-unlocked",
  pilot: "unlock-pilot",
  ready: "unlock-ready",
  research: "unlock-research",
  watch: "unlock-watch"
};

const countries = JSON.parse(await fs.readFile(DATA_PATH, "utf8"));
const token = process.env.GITHUB_TOKEN || getGhToken();

if (!token) {
  throw new Error("Missing GitHub token. Set GITHUB_TOKEN or log in with gh auth.");
}

await ensureLabels();
const existingIssues = await listAllIssues();
const issuesByCode = new Map();

for (const issue of existingIssues) {
  const code = extractCountryCode(issue.title);
  if (code) {
    issuesByCode.set(code, issue);
  }
}

for (const country of countries) {
  const expectedTitle = issueTitle(country);
  const expectedLabels = ["unlock-country", STATUS_LABELS[country.status]].filter(Boolean);
  const body = issueBody(country);
  const existing = issuesByCode.get(country.code);

  if (!existing) {
    const created = await github("/issues", {
      method: "POST",
      body: {
        title: expectedTitle,
        body,
        labels: expectedLabels
      }
    });
    issuesByCode.set(country.code, created);
    continue;
  }

  const currentLabels = (existing.labels || []).map(label => typeof label === "string" ? label : label.name).sort();
  const sortedExpectedLabels = [...expectedLabels].sort();
  const needsUpdate =
    existing.title !== expectedTitle ||
    existing.body !== body ||
    JSON.stringify(currentLabels) !== JSON.stringify(sortedExpectedLabels);

  if (needsUpdate) {
    const updated = await github(`/issues/${existing.number}`, {
      method: "PATCH",
      body: {
        title: expectedTitle,
        body,
        labels: expectedLabels
      }
    });
    issuesByCode.set(country.code, updated);
  }
}

const output = {
  generatedAt: new Date().toISOString(),
  repo: REPO,
  countries: {}
};

for (const country of countries) {
  const issue = issuesByCode.get(country.code);
  if (!issue) {
    continue;
  }

  const comments = await listComments(issue.number);
  const claim = parseClaim(comments);

  output.countries[country.code] = {
    number: issue.number,
    url: issue.html_url,
    title: issue.title,
    state: issue.state,
    labels: (issue.labels || []).map(label => typeof label === "string" ? label : label.name),
    comments: issue.comments,
    claimant: claim?.login || null,
    claimedAt: claim?.claimedAt || null,
    claimUrl: claim?.url || null,
    updatedAt: issue.updated_at
  };
}

await fs.writeFile(OUTPUT_PATH, `${JSON.stringify(output, null, 2)}\n`);

console.log(`Synced ${countries.length} countries to ${OUTPUT_PATH}`);

function getGhToken() {
  try {
    return execFileSync("gh", ["auth", "token"], { encoding: "utf8" }).trim();
  } catch (error) {
    return "";
  }
}

function issueTitle(country) {
  return `[Unlock:${country.code}] ${country.name} healthcare data integration`;
}

function issueBody(country) {
  return [
    `## Unlock ${country.name}`,
    ``,
    `Help Eir unlock patient-facing healthcare data access for **${country.name}**.`,
    ``,
    `### Current patient access route`,
    `- Portal: **${country.portal}**`,
    `- Portal URL: ${country.portalUrl}`,
    `- Login path: ${country.login}`,
    `- Integration shape: ${country.scope}`,
    ``,
    `### What citizens use today`,
    `${country.summary}`,
    ``,
    `### How to contribute`,
    `- Run the official patient flow yourself.`,
    `- Capture records, prescriptions, labs, vaccinations, visits, and document/export behavior when available.`,
    `- Note anything unusual about regional variation, PDFs, iframes, or app-only behavior.`,
    ``,
    `### Claim this country`,
    `Comment **\`/claim\`** on this issue to claim the country integration mission.`,
    `Comment **\`/release\`** if you want to give it up later.`,
    `The Unlock site reads claim state from these comments and shows the active claimant publicly.`,
    ``,
    `### Useful links`,
    `- Country access guide: ${country.portalUrl}`,
    `- Unlock site: https://unlock.eir.space/`,
    `- Repository: https://github.com/${REPO}`,
    ``,
    `### Suggested first pass`,
    `1. Verify the main patient login route.`,
    `2. Identify the records overview page.`,
    `3. Identify how detailed record pages load data.`,
    `4. Check prescriptions, labs, and downloads.`,
    `5. Share findings or capture bundles back through Eir.`,
    ``,
    `_This issue is managed by the Unlock country sync script._`
  ].join("\n");
}

function extractCountryCode(title) {
  const match = /^\[Unlock:([A-Z]{2})\]/.exec(title || "");
  return match ? match[1] : null;
}

async function ensureLabels() {
  const labels = [
    { name: "unlock-country", color: "0f8a5f", description: "Country unlock mission for patient-facing healthcare data" },
    { name: "unlock-unlocked", color: "067647", description: "Country is already unlocked or live in Eir" },
    { name: "unlock-pilot", color: "d97706", description: "Country is in active pilot or capture phase" },
    { name: "unlock-ready", color: "2563eb", description: "Country is a strong near-term build target" },
    { name: "unlock-research", color: "4f46e5", description: "Country needs technical reconnaissance" },
    { name: "unlock-watch", color: "6b7280", description: "Country is fragmented or not ready yet" }
  ];

  const existing = await github("/labels?per_page=100");
  const byName = new Map(existing.map(label => [label.name, label]));

  for (const label of labels) {
    if (!byName.has(label.name)) {
      await github("/labels", {
        method: "POST",
        body: label
      });
    }
  }
}

async function listAllIssues() {
  const issues = await github("/issues?state=all&labels=unlock-country&per_page=100");
  return issues.filter(issue => !issue.pull_request);
}

async function listComments(issueNumber) {
  return github(`/issues/${issueNumber}/comments?per_page=100`);
}

function parseClaim(comments) {
  let active = null;

  for (const comment of comments) {
    const body = String(comment.body || "").trim().toLowerCase();
    const isClaim = /(^|\s)(\/claim|claim)(\s|$)/.test(body);
    const isRelease = /(^|\s)(\/release|release)(\s|$)/.test(body);

    if (isClaim && !active) {
      active = {
        login: comment.user?.login || "unknown",
        claimedAt: comment.created_at,
        url: comment.html_url
      };
      continue;
    }

    if (isRelease && active && comment.user?.login === active.login) {
      active = null;
    }
  }

  return active;
}

async function github(pathname, options = {}) {
  const response = await fetch(`https://api.github.com/repos/${OWNER}/${NAME}${pathname}`, {
    method: options.method || "GET",
    headers: {
      "Accept": "application/vnd.github+json",
      "Authorization": `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28"
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`GitHub API ${response.status} ${pathname}: ${text}`);
  }

  return response.json();
}
