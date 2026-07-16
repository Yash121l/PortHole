import Foundation
import UserNotifications

/// Posts local notifications when the port landscape changes while the user
/// isn't looking: a new listener appearing, or — the security-relevant case —
/// a listener bound beyond localhost.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Called when the user enables a notification toggle. Authorization is
    /// requested lazily — never at launch.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Turns a scan diff into notifications, respecting the user's toggles.
    /// A port that becomes exposed changes bind address, therefore identity,
    /// therefore arrives in `diff.added` — one code path covers both cases.
    func scanDidChange(diff: PortDiff, settings: SettingsStore) {
        guard settings.notifyOnNewPort || settings.notifyOnExposedPort else { return }
        guard !diff.added.isEmpty else { return }

        let exposed = diff.added.filter(\.isExposed)
        let interesting = settings.notifyOnNewPort ? diff.added : exposed
        guard !interesting.isEmpty else { return }

        // Wake-from-sleep or a big compose-up can add dozens of ports at
        // once; collapse those into one summary instead of a storm.
        if interesting.count > 5 {
            post(title: "\(interesting.count) new listening ports",
                 body: exposed.isEmpty
                    ? "Several processes started listening. Open PortHole for details."
                    : "\(exposed.count) of them are exposed to the network. Open PortHole for details.")
            return
        }

        for port in interesting {
            if port.isExposed, settings.notifyOnExposedPort {
                post(title: "Port \(port.port) is exposed to the network",
                     body: "\(port.processName) (PID \(port.pid)) is listening on \(port.bindAddress):\(port.port) — reachable from other machines.")
            } else if settings.notifyOnNewPort {
                post(title: "New listening port \(port.port)",
                     body: "\(port.processName) (PID \(port.pid)) started listening on \(port.networkProtocol.rawValue) port \(port.port).")
            }
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
