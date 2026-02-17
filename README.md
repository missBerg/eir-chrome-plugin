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

## Browser Compatibility

- Chrome (Manifest V3)
- Edge (Chromium-based)
- Other Chromium-based browsers (Brave, Arc, Opera, etc.)

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

MIT
