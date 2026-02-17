import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "eir" || ext == "yaml" || ext == "yml" {
                NotificationCenter.default.post(
                    name: .openEirFile,
                    object: url
                )
                return
            }
        }
    }
}

extension Notification.Name {
    static let openEirFile = Notification.Name("openEirFile")
}

@main
struct EirViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentVM)
                .environmentObject(chatVM)
                .environmentObject(settingsVM)
                .onAppear {
                    loadFromCommandLine()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openEirFile)) { notification in
                    if let url = notification.object as? URL {
                        documentVM.loadFile(url: url)
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open EIR File...") {
                    documentVM.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsVM)
        }
    }

    private func loadFromCommandLine() {
        let args = CommandLine.arguments
        for arg in args.dropFirst() {
            if arg.hasSuffix(".eir") || arg.hasSuffix(".yaml") || arg.hasSuffix(".yml") {
                let url = URL(fileURLWithPath: arg)
                documentVM.loadFile(url: url)
                return
            }
        }
    }
}
