import Foundation

enum AppRuntimeContext {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Base URL for the Eir backend (Cloud Run / load balancer). Debug builds talk to dev.
    static var eirBackendURL: URL {
        #if DEBUG
        return URL(string: "https://eir-app-dev-sgdkssgksa-uc.a.run.app")!
        #else
        return URL(string: "https://app.eir.space")!
        #endif
    }
}
