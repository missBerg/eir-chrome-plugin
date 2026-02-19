# Eir - 1177 Journal Downloader

A Chrome extension that downloads and structures your Swedish medical records from [1177.se](https://journalen.1177.se) (Journalen) into portable, machine-readable files.

**Your data never leaves your device.**

## Features

- **One-click download** - A floating button on 1177.se exports all your journal entries
- **Structured EIR format** - Exports to both plain text (.txt) and the open EIR format (.eir/YAML)
- **Complete history** - Automatically loads all available entries by expanding the full timeline
- **Privacy-first** - All processing happens locally in your browser. No servers, no tracking, no analytics
- **Transfer to Eir.Space** - Optionally view your records in the [Eir.Space](https://eir.space) viewer for AI-powered health insights
- **Draggable UI** - The floating button can be repositioned anywhere on the page

## Installation

This extension isn't on the Chrome Web Store. Install it manually:

1. **Download** - Clone this repo or download the [latest release](https://github.com/BirgerMoell/eir-chrome-plugin/releases/latest)
2. Open Chrome and go to `chrome://extensions/`
3. Enable **Developer mode** (toggle in the top right)
4. Click **"Load unpacked"** and select this folder
5. Navigate to [journalen.1177.se](https://journalen.1177.se), log in with BankID, and click the floating "Download Journals" button

## How It Works

1. The extension injects a floating button on `journalen.1177.se` pages
2. When clicked, it automatically clicks "Load More" to fetch your complete history
3. It expands each journal entry and extracts structured data (dates, categories, providers, diagnoses, notes)
4. Downloads two files:
   - `journal-content.txt` - Human-readable text export
   - `journal-content.eir` - Structured YAML in the EIR format

## The EIR Format

The `.eir` file is a YAML-based format designed for medical records:

```yaml
metadata:
  format_version: "1.0"
  source: "1177.se Journal"
  patient:
    name: "Your Name"
  export_info:
    total_entries: 25
    date_range:
      start: "2001-02-26"
      end: "2025-03-17"

entries:
  - id: "entry_001"
    date: "2025-03-17"
    category: "Vaccinationer"
    provider:
      name: "Your Healthcare Provider"
      region: "Region Uppsala"
    content:
      summary: "TBE-vaccination"
      notes:
        - "Dos: 0.5 ml"
```

See [eir-format-specification.md](eir-format-specification.md) for the full specification.

## Files

| File | Purpose |
|------|---------|
| `manifest.json` | Chrome extension configuration (Manifest V3) |
| `content.js` | Main content script - button injection, journal scraping, EIR generation |
| `data-transfer.js` | Secure data transfer to Eir.Space via PostMessage API |
| `styles.css` | Floating button styling |
| `popup.html` | Extension popup UI |
| `privacy-policy.html` | Privacy policy |
| `EirViewer/` | Native macOS desktop app (Swift/SwiftUI) |
| `releases/` | Pre-built app bundle (.zip) |

## Permissions

| Permission | Why |
|------------|-----|
| `activeTab` | Access the current 1177.se journal page |
| `storage` | Store user preferences |
| `tabs` | Open the journal page from the popup |
| `https://journalen.1177.se/*` | Only runs on the 1177.se journal site |

## Privacy

- All data processing happens locally in your browser
- No data is sent to external servers (except optionally to Eir.Space, which you initiate)
- No cookies, analytics, or tracking
- Downloaded files are saved to your device only
- GDPR compliant

See the full [Privacy Policy](privacy-policy.html).

## Eir Viewer — Desktop App for macOS

A native Swift/SwiftUI app that opens `.eir` files locally on your Mac. No server, no cloud — your records stay on your device.

**[Download latest release](https://github.com/BirgerMoell/eir-chrome-plugin/releases/latest)**

### Features

- **Timeline view** — entries grouped by month with colored category badges
- **Search & filter** — by category (Vårdkontakter, Diagnoser, Vaccinationer, Anteckningar), provider, or free text
- **Entry detail** — full view with provider info, responsible person, notes, and tags
- **"Explain with AI"** — one-click button on each journal entry to get an AI explanation of medical terms and what happened
- **Chat threads** — persistent per-person conversations with auto-generated titles, shown in the sidebar
- **Markdown rendering** — AI responses render bold, italic, code, and other formatting
- **Journal references** — AI can link to specific journal entries; click to jump to that entry
- **Multi-profile** — manage records for multiple people, each with their own chat history
- **AI chat** — ask questions about your records using OpenAI, Anthropic, Groq, or any OpenAI-compatible provider
- **Drag & drop** — drop `.eir` or `.yaml` files onto the window
- **Default file handler** — double-click `.eir` files in Finder to open them

### Install

1. Download `EirViewer-macOS.dmg` from [Releases](https://github.com/BirgerMoell/eir-chrome-plugin/releases/latest)
2. Open the `.dmg` and drag **EirViewer** to the **Applications** folder
3. If macOS says the app is "damaged", open Terminal and run: `xattr -cr /Applications/EirViewer.app`
4. Double-click to open

### Build from Source

```bash
cd EirViewer
swift build -c release
# Binary at .build/release/EirViewer
```

Requires macOS 14 (Sonoma) and Xcode Command Line Tools.

### Configure AI Chat

Open **Settings** (Cmd+,) to add your API key:

| Provider | Default Model | Endpoint |
|----------|---------------|----------|
| OpenAI | gpt-4o | api.openai.com |
| Anthropic | claude-sonnet-4-5 | api.anthropic.com |
| Groq | llama-3.3-70b | api.groq.com |
| Custom | (your choice) | (your URL) |

API keys are stored in macOS Keychain.

## Browser Compatibility

- Chrome (Manifest V3)
- Edge (Chromium-based)
- Other Chromium-based browsers (Brave, Arc, Opera, etc.)

## Getting Records from Kaiser Permanente Georgia

This repo currently automates downloads from **1177.se** only.  
For **Kaiser Georgia**, use Eir Viewer as a records-request assistant:

1. Open Eir Viewer chat
2. Ask: **"Help me request my medical records from Kaiser Georgia"**
3. The assistant can now provide:
   - A step-by-step Kaiser Georgia request workflow
   - A HIPAA right-of-access request template you can copy/paste
   - A checklist of what details to include (date range, record types, delivery method)

If you request records from a different provider, ask with provider + state (for example:  
"Help me request records from Emory in Georgia"), and Eir Viewer will fall back to a generic HIPAA workflow.

## Extracting Data from MyChart

Eir Viewer can now guide users through **MyChart page navigation** and export prep.

Use the native app's **Portal Assist** tab to open an embedded browser with:
- Back/forward/reload controls + URL bar
- Quick links (MyChart + Kaiser portal)
- Step-by-step navigation checklists for labs, visits, documents, full export, and EIR import prep
- **Auto-open helper** that attempts to click likely section buttons (labs/visits/documents)
- **Capture this view** to save page content + screenshot locally
- **Create EIR profile from captures** so users can import directly without manual file upload

Ask in chat:
- **"Guide me to MyChart lab results and how to download them"**
- **"Help me export MyChart records for labs, visits, meds, immunizations, and documents"**
- **"Create a checklist to prepare MyChart exports for .eir import"**

The assistant provides:
- Click-by-click page paths (for example `Menu -> Test Results` for labs)
- A full export checklist by section
- Import prep guidance for Eir (`.eir` / `.yaml`)

Note: Eir Viewer currently imports structured EIR/YAML files. If your MyChart exports are PDF/HTML, convert/map them to EIR before importing.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

MIT
