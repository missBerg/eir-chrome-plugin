import SwiftUI
import WebKit
import AppKit
import Yams

struct PortalAssistView: View {
    @EnvironmentObject var profileStore: ProfileStore

    @StateObject private var browser = PortalBrowserModel()
    @State private var selectedTopic: PortalGuideTopic = .labs
    @State private var actionStatus: String?

    private let quickLinks: [(title: String, url: String)] = [
        ("MyChart", "https://www.mychart.org"),
        ("Kaiser Sign In", "https://healthy.kaiserpermanente.org"),
        ("Kaiser Support", "https://healthy.kaiserpermanente.org/support"),
    ]

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                browserBar
                Divider()
                quickLinkBar
                Divider()
                EmbeddedPortalWebView(
                    browser: browser,
                    initialURL: URL(string: "https://www.mychart.org")!
                )
            }
            .frame(minWidth: 620, idealWidth: 760)

            guidePanel
                .frame(minWidth: 320, idealWidth: 360)
                .background(AppColors.background)
        }
    }

    private var browserBar: some View {
        HStack(spacing: 8) {
            Button {
                browser.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!browser.canGoBack)
            .buttonStyle(.plain)
            .help("Back")

            Button {
                browser.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!browser.canGoForward)
            .buttonStyle(.plain)
            .help("Forward")

            Button {
                browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Reload")

            TextField("Enter portal URL", text: $browser.addressBarText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    browser.openAddressBar()
                }

            Button("Go") {
                browser.openAddressBar()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primary)

            if browser.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(AppColors.card)
    }

    private var quickLinkBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(quickLinks.enumerated()), id: \.offset) { _, item in
                    Button(item.title) {
                        browser.open(item.url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(AppColors.background)
    }

    private var guidePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Portal Assist")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppColors.text)

            Text("Navigate portals and extract records without leaving Eir Viewer.")
                .font(.callout)
                .foregroundColor(AppColors.textSecondary)

            HStack {
                Text("Guide topic")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Picker("Guide topic", selection: $selectedTopic) {
                    ForEach(PortalGuideTopic.allCases) { topic in
                        Text(topic.rawValue).tag(topic)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            GroupBox("Where to click") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(selectedTopic.routeSteps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(.callout)
                            .foregroundColor(AppColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 2)
            }

            HStack(spacing: 8) {
                Button("Try auto-open section") {
                    Task {
                        actionStatus = await browser.tryAutoOpen(topic: selectedTopic)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primary)

                Button("Capture this view") {
                    Task {
                        actionStatus = await browser.captureCurrentView(topic: selectedTopic)
                    }
                }
                .buttonStyle(.bordered)
            }

            if let actionStatus {
                Text(actionStatus)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            GroupBox("Export checklist") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(selectedTopic.exportChecklist.enumerated()), id: \.offset) { _, item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundColor(AppColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 2)
            }

            GroupBox("Import note") {
                Text("Eir Viewer currently imports .eir/.yaml files. If the portal export is PDF/HTML, convert or map it to EIR format before import.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Captured pages") {
                if browser.captures.isEmpty {
                    Text("No captures yet. Use \"Capture this view\" on each portal page you want to keep.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(browser.captures.prefix(4)) { capture in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(capture.title.isEmpty ? capture.url : capture.title)
                                    .font(.caption)
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(1)
                                Text("\(capture.topic.rawValue) • \(capture.dateText)")
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button("Create EIR profile from captures") {
                do {
                    if let profile = try browser.createCapturedProfile(using: profileStore) {
                        profileStore.selectProfile(profile.id)
                        actionStatus = "Created profile \"\(profile.displayName)\" from \(browser.captures.count) captured pages."
                    } else {
                        actionStatus = "Could not create profile from captures."
                    }
                } catch {
                    actionStatus = "Failed to create EIR: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primary)
            .disabled(browser.captures.isEmpty)

            Spacer()

            Text(browser.currentURLText.isEmpty ? "No page loaded yet" : browser.currentURLText)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
        }
        .padding(14)
    }
}

private struct PortalCapture: Identifiable {
    let id: String
    let topic: PortalGuideTopic
    let capturedAt: Date
    let title: String
    let heading: String
    let url: String
    let bodyText: String
    let buttonLabels: [String]
    let snapshotPath: String?

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: capturedAt)
    }
}

private enum PortalGuideTopic: String, CaseIterable, Identifiable {
    case labs = "Labs"
    case visits = "Visits"
    case documents = "Documents"
    case fullExport = "Full export"
    case importToEir = "Import to EIR"

    var id: String { rawValue }

    var routeSteps: [String] {
        switch self {
        case .labs:
            return [
                "Open Menu (or Your Menu).",
                "Select Test Results.",
                "Filter by date range.",
                "Open each result to review details and reference ranges."
            ]
        case .visits:
            return [
                "Open Menu.",
                "Go to Visits > Past Visits.",
                "Open a visit.",
                "Download the After Visit Summary."
            ]
        case .documents:
            return [
                "Open Menu.",
                "Go to Document Center (or My Record > Documents).",
                "Open available clinical documents.",
                "Download or print each document."
            ]
        case .fullExport:
            return [
                "Start at Menu or My Record.",
                "Export labs, medications, immunizations, visits, and documents.",
                "Use date filters to limit scope.",
                "If sections are missing, request full records from ROI/HIM."
            ]
        case .importToEir:
            return [
                "Export portal records by section.",
                "Organize files by date and category.",
                "Convert structured data to EIR YAML.",
                "Import .eir/.yaml in Eir Viewer."
            ]
        }
    }

    var exportChecklist: [String] {
        switch self {
        case .labs:
            return [
                "Capture all lab panels in the target date range.",
                "Include result details, values, and reference ranges.",
                "Save files with date markers."
            ]
        case .visits:
            return [
                "Download visit summaries for each encounter.",
                "Include provider name and date for each visit.",
                "Track missing visits in a notes list."
            ]
        case .documents:
            return [
                "Download clinical letters and document attachments.",
                "Keep original filenames and add date prefixes.",
                "Note document type for EIR mapping."
            ]
        case .fullExport:
            return [
                "Labs, medications, immunizations, visits, documents.",
                "Record any missing section in a gap checklist.",
                "Submit ROI request when portal export is incomplete."
            ]
        case .importToEir:
            return [
                "Normalize dates to YYYY-MM-DD.",
                "Map records to EIR entry fields and categories.",
                "Validate YAML and then import into Eir Viewer."
            ]
        }
    }
}

private final class PortalBrowserModel: ObservableObject {
    @Published var addressBarText: String = "https://www.mychart.org"
    @Published var currentURLText: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var captures: [PortalCapture] = []

    private weak var webView: WKWebView?
    private var queuedURL: URL?

    func attach(webView: WKWebView) {
        self.webView = webView
        if let queuedURL {
            load(queuedURL)
            self.queuedURL = nil
        }
    }

    func openAddressBar() {
        open(addressBarText)
    }

    func open(_ input: String) {
        guard let url = normalizedURL(from: input) else { return }
        addressBarText = url.absoluteString
        load(url)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func tryAutoOpen(topic: PortalGuideTopic) async -> String {
        guard let webView else {
            return "Open a portal page first."
        }

        let config = autoClickConfig(for: topic)
        let script = """
        (() => {
          const textTokens = \(jsonArray(config.textTokens));
          const hrefTokens = \(jsonArray(config.hrefTokens));
          const normalize = (v) => (v || "").toLowerCase().replace(/\\s+/g, " ").trim();
          const candidates = Array.from(document.querySelectorAll('a,button,[role="button"],[aria-label],[data-testid]'));
          for (const el of candidates) {
            const text = normalize(el.innerText || el.textContent || el.getAttribute('aria-label') || '');
            const href = normalize(el.getAttribute('href') || '');
            if (textTokens.some(t => t && text.includes(t))) {
              el.scrollIntoView({block: "center", inline: "center"});
              el.click();
              return { ok: true, matchedBy: "text", target: text.slice(0, 120) };
            }
            if (hrefTokens.some(t => t && href.includes(t))) {
              el.scrollIntoView({block: "center", inline: "center"});
              el.click();
              return { ok: true, matchedBy: "href", target: href.slice(0, 120) };
            }
          }
          return { ok: false, count: candidates.length };
        })();
        """

        let result = await evaluateJavaScript(script, on: webView)
        if let dict = result as? [String: Any],
           let ok = dict["ok"] as? Bool {
            if ok {
                let mode = (dict["matchedBy"] as? String) ?? "unknown"
                let target = (dict["target"] as? String) ?? "unknown target"
                return "Clicked a likely \(topic.rawValue.lowercased()) button (\(mode): \(target))."
            }
            let count = (dict["count"] as? Int) ?? 0
            return "Could not auto-click \(topic.rawValue.lowercased()) on this page. Tried \(count) clickable elements. You may need to open the section manually first."
        }

        return "Could not auto-click on this page."
    }

    func captureCurrentView(topic: PortalGuideTopic) async -> String {
        guard let webView else {
            return "Open a page before capturing."
        }

        let captureScript = """
        (() => {
          const title = document.title || "";
          const heading = (document.querySelector('h1,h2')?.innerText || "").trim();
          const bodyText = (document.body?.innerText || "")
            .replace(/\\u00a0/g, " ")
            .replace(/[ \\t]+\\n/g, "\\n")
            .replace(/\\n{3,}/g, "\\n\\n")
            .trim()
            .slice(0, 20000);
          const labels = Array.from(document.querySelectorAll('a,button,[role="button"],[aria-label]'))
            .map(el => (el.innerText || el.textContent || el.getAttribute('aria-label') || "").replace(/\\s+/g, " ").trim())
            .filter(Boolean)
            .slice(0, 50);
          return {
            title,
            heading,
            url: location.href,
            bodyText,
            buttonLabels: labels
          };
        })();
        """

        guard let payload = await evaluateJavaScript(captureScript, on: webView) as? [String: Any] else {
            return "Failed to capture page content."
        }

        let now = Date()
        let snapshotPath = await saveSnapshot(from: webView)?.path
        let entry = PortalCapture(
            id: "capture_\(UUID().uuidString)",
            topic: topic,
            capturedAt: now,
            title: (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            heading: (payload["heading"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            url: (payload["url"] as? String) ?? currentURLText,
            bodyText: (payload["bodyText"] as? String) ?? "",
            buttonLabels: payload["buttonLabels"] as? [String] ?? [],
            snapshotPath: snapshotPath
        )

        captures.insert(entry, at: 0)
        return "Captured \(entry.topic.rawValue.lowercased()) view: \(entry.title.isEmpty ? entry.url : entry.title)"
    }

    func createCapturedProfile(using profileStore: ProfileStore) throws -> PersonProfile? {
        guard !captures.isEmpty else { return nil }
        let eirURL = try saveCapturesAsEIR()
        return profileStore.addProfile(displayName: "Portal Capture", fileURL: eirURL)
    }

    private func load(_ url: URL) {
        guard let webView else {
            queuedURL = url
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let withScheme = URL(string: trimmed), withScheme.scheme != nil {
            return withScheme
        }

        return URL(string: "https://\(trimmed)")
    }

    private func autoClickConfig(for topic: PortalGuideTopic) -> (textTokens: [String], hrefTokens: [String]) {
        switch topic {
        case .labs:
            return (
                ["test results", "lab results", "results", "labs", "provsvar"],
                ["/test-results", "/results", "/labs", "lab"]
            )
        case .visits:
            return (
                ["past visits", "visits", "encounters", "after visit summary"],
                ["/visits", "/appointments", "/encounters"]
            )
        case .documents:
            return (
                ["document center", "documents", "letters", "clinical document"],
                ["/documents", "/letters", "/document-center"]
            )
        case .fullExport:
            return (
                ["download my record", "request records", "medical records", "share my record", "export"],
                ["/medical-record", "/records", "/download", "/share"]
            )
        case .importToEir:
            return (
                ["download", "export", "documents", "results"],
                ["/download", "/documents", "/results"]
            )
        }
    }

    private func jsonArray(_ strings: [String]) -> String {
        let quoted = strings.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\"").lowercased())\"" }
        return "[\(quoted.joined(separator: ","))]"
    }

    private func evaluateJavaScript(_ script: String, on webView: WKWebView) async -> Any? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }

    private func saveSnapshot(from webView: WKWebView) async -> URL? {
        await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, _ in
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let url = try Self.exportDirectory()
                        .appendingPathComponent("portal-snapshot-\(UUID().uuidString).png")
                    try pngData.write(to: url)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveCapturesAsEIR() throws -> URL {
        let sorted = captures.sorted { $0.capturedAt < $1.capturedAt }
        let iso = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let providers = Array(Set(sorted.map { capture in
            URL(string: capture.url)?.host ?? "Portal"
        })).sorted()

        let entries: [EirEntry] = sorted.enumerated().map { index, capture in
            let notes = [
                "Source URL: \(capture.url)",
                "Captured at: \(iso.string(from: capture.capturedAt))",
                capture.heading.isEmpty ? nil : "Heading: \(capture.heading)",
                capture.buttonLabels.isEmpty ? nil : "Visible actions: \(capture.buttonLabels.joined(separator: " | "))",
            ].compactMap { $0 }

            return EirEntry(
                id: "portal_capture_\(String(format: "%03d", index + 1))",
                date: dateFormatter.string(from: capture.capturedAt),
                time: nil,
                category: "Portal Capture",
                type: capture.topic.rawValue,
                provider: EirProvider(
                    name: URL(string: capture.url)?.host ?? "Portal",
                    region: nil,
                    location: capture.url
                ),
                status: "Captured",
                responsiblePerson: nil,
                content: EirContent(
                    summary: capture.title.isEmpty ? "Captured portal page" : capture.title,
                    details: capture.bodyText,
                    notes: notes
                ),
                attachments: capture.snapshotPath.map { [$0] },
                tags: ["portal", "capture", capture.topic.rawValue.lowercased()]
            )
        }

        let startDate = sorted.first.map { dateFormatter.string(from: $0.capturedAt) }
        let endDate = sorted.last.map { dateFormatter.string(from: $0.capturedAt) }

        let document = EirDocument(
            metadata: EirMetadata(
                formatVersion: "1.0",
                createdAt: iso.string(from: Date()),
                source: "Portal Assist Capture",
                patient: EirPatient(name: "Portal Capture", birthDate: nil, personalNumber: nil),
                exportInfo: EirExportInfo(
                    totalEntries: entries.count,
                    dateRange: EirDateRange(start: startDate, end: endDate),
                    healthcareProviders: providers
                )
            ),
            entries: entries
        )

        let yaml = try YAMLEncoder().encode(document)
        let fileURL = try Self.exportDirectory().appendingPathComponent(
            "portal-capture-\(Int(Date().timeIntervalSince1970)).eir"
        )
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func exportDirectory() throws -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("EirViewer", isDirectory: true)
            .appendingPathComponent("PortalCaptures", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }
}

private struct EmbeddedPortalWebView: NSViewRepresentable {
    @ObservedObject var browser: PortalBrowserModel
    let initialURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        browser.attach(webView: webView)
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let browser: PortalBrowserModel

        init(browser: PortalBrowserModel) {
            self.browser = browser
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            browser.isLoading = true
            sync(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            browser.isLoading = false
            sync(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            browser.isLoading = false
            sync(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            browser.isLoading = false
            sync(webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func sync(_ webView: WKWebView) {
            browser.canGoBack = webView.canGoBack
            browser.canGoForward = webView.canGoForward
            browser.currentURLText = webView.url?.absoluteString ?? ""
            if !browser.currentURLText.isEmpty {
                browser.addressBarText = browser.currentURLText
            }
        }
    }
}
