import SwiftUI
import WebKit

struct PortalAssistView: View {
    @StateObject private var browser = PortalBrowserModel()
    @State private var selectedTopic: PortalGuideTopic = .labs

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

            Spacer()

            Text(browser.currentURLText.isEmpty ? "No page loaded yet" : browser.currentURLText)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
        }
        .padding(14)
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
