import Foundation
import PostHog

/// Anonymous product analytics via PostHog.
///
/// Release builds only, and switchable off in Settings → General. Events carry
/// counts, outcomes and the inferred dev-tool label ("Vite", "Postgres"),
/// never process names, command lines, paths, project folders or users.
@MainActor
enum Analytics {
    /// Public PostHog project key (phc_ client key, safe to ship in the binary).
    private static let projectKey = "phc_oLm8fb7L4CXDqGdJcc7a6boCtR8rVjf6dNx7G995eGdy"
    static let enabledDefaultsKey = "analyticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    private static var started = false

    static func start() {
        #if !DEBUG
        guard !started else { return }
        let config = PostHogConfig(projectToken: projectKey, host: "https://us.i.posthog.com")
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        config.errorTrackingConfig.autoCapture = true
        // A choice persisted by the SDK wins on later launches; setEnabled
        // keeps it in step with the Settings toggle.
        config.optOut = !isEnabled
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["app": "porthole"])
        started = true
        #endif
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledDefaultsKey)
        guard started else { return }
        if on { PostHogSDK.shared.optIn() } else { PostHogSDK.shared.optOut() }
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard started else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    /// Shared, non-identifying description of a port row.
    static func props(for port: ListeningPort) -> [String: Any] {
        [
            "port": port.port,
            "protocol": port.networkProtocol.rawValue,
            "exposed": port.isExposed,
            "tool": port.inferredTool?.label ?? "unknown",
        ]
    }
}
