import SwiftUI
import Observation

/// Observable, UserDefaults-backed settings. Every property persists on write,
/// so views can bind to it directly and everything survives relaunch.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    // MARK: Option types

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "Follow System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum AccentTint: String, CaseIterable, Identifiable {
        case system, blue, purple, pink, red, orange, yellow, green, teal, indigo, graphite
        var id: String { rawValue }
        var title: String { rawValue == "system" ? "System Accent" : rawValue.capitalized }
        /// nil means "use the user's system accent color".
        var color: Color? {
            switch self {
            case .system: return nil
            case .blue: return .blue
            case .purple: return .purple
            case .pink: return .pink
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .teal: return .teal
            case .indigo: return .indigo
            case .graphite: return .gray
            }
        }
    }

    enum RowDensity: String, CaseIterable, Identifiable {
        case comfortable, compact
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum RefreshInterval: Int, CaseIterable, Identifiable {
        case oneSecond = 1
        case twoSeconds = 2
        case fiveSeconds = 5
        case manual = 0

        var id: Int { rawValue }
        var seconds: TimeInterval { TimeInterval(rawValue) }
        var title: String {
            switch self {
            case .oneSecond: return "Every second"
            case .twoSeconds: return "Every 2 seconds"
            case .fiveSeconds: return "Every 5 seconds"
            case .manual: return "Manual only"
            }
        }
    }

    enum MenuBarIconStyle: String, CaseIterable, Identifiable {
        case network, bolt, radar, terminal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .network: return "Network"
            case .bolt: return "Bolt"
            case .radar: return "Radar"
            case .terminal: return "Terminal"
            }
        }
        var symbol: String {
            switch self {
            case .network: return "network"
            case .bolt: return "bolt.horizontal.circle"
            case .radar: return "dot.radiowaves.left.and.right"
            case .terminal: return "apple.terminal"
            }
        }
        /// Variant used when an exposed (all-interfaces) port exists and the
        /// user has the menu-bar warning enabled.
        var exposedSymbol: String {
            switch self {
            case .network: return "network.badge.shield.half.filled"
            case .bolt: return "bolt.horizontal.circle.fill"
            case .radar: return "dot.radiowaves.left.and.right"
            case .terminal: return "apple.terminal.fill"
            }
        }
    }

    // MARK: Appearance

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var accentTint: AccentTint {
        didSet { defaults.set(accentTint.rawValue, forKey: Keys.accentTint) }
    }
    var rowDensity: RowDensity {
        didSet { defaults.set(rowDensity.rawValue, forKey: Keys.rowDensity) }
    }
    var showPID: Bool {
        didSet { defaults.set(showPID, forKey: Keys.showPID) }
    }
    var showPath: Bool {
        didSet { defaults.set(showPath, forKey: Keys.showPath) }
    }
    var showUser: Bool {
        didSet { defaults.set(showUser, forKey: Keys.showUser) }
    }
    var showUptime: Bool {
        didSet { defaults.set(showUptime, forKey: Keys.showUptime) }
    }
    var showProtocolBadge: Bool {
        didSet { defaults.set(showProtocolBadge, forKey: Keys.showProtocolBadge) }
    }

    // MARK: Behavior

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }
    var confirmBeforeKill: Bool {
        didSet { defaults.set(confirmBeforeKill, forKey: Keys.confirmBeforeKill) }
    }
    /// Seconds to wait after SIGTERM before deciding the process survived.
    var killGracePeriod: Double {
        didSet { defaults.set(killGracePeriod, forKey: Keys.killGracePeriod) }
    }
    var autoEscalateToSigkill: Bool {
        didSet { defaults.set(autoEscalateToSigkill, forKey: Keys.autoEscalateToSigkill) }
    }
    var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            NSApp?.setActivationPolicy(showDockIcon ? .regular : .accessory)
        }
    }

    // MARK: Menu bar

    var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle) }
    }
    var showPortCountBadge: Bool {
        didSet { defaults.set(showPortCountBadge, forKey: Keys.showPortCountBadge) }
    }
    var warnExposedInMenuBar: Bool {
        didSet { defaults.set(warnExposedInMenuBar, forKey: Keys.warnExposedInMenuBar) }
    }

    // MARK: Labels & pins

    var labelRules: [PortLabelRule] {
        didSet {
            if let data = try? JSONEncoder().encode(labelRules) {
                defaults.set(data, forKey: Keys.labelRules)
            }
        }
    }
    var pinnedPorts: Set<Int> {
        didSet { defaults.set(Array(pinnedPorts).sorted(), forKey: Keys.pinnedPorts) }
    }

    // MARK: Notifications

    var notifyOnNewPort: Bool {
        didSet { defaults.set(notifyOnNewPort, forKey: Keys.notifyOnNewPort) }
    }
    var notifyOnExposedPort: Bool {
        didSet { defaults.set(notifyOnExposedPort, forKey: Keys.notifyOnExposedPort) }
    }

    // MARK: Helpers

    func rule(for port: ListeningPort) -> PortLabelRule? {
        labelRules.first { $0.matches(port) }
    }

    func isPinned(_ port: Int) -> Bool {
        pinnedPorts.contains(port)
    }

    func togglePin(_ port: Int) {
        if pinnedPorts.contains(port) {
            pinnedPorts.remove(port)
        } else {
            pinnedPorts.insert(port)
        }
    }

    /// Whether the app needs to keep scanning while the panel is closed
    /// (the menu-bar badge/warning and notifications go stale otherwise).
    var needsBackgroundScanning: Bool {
        showPortCountBadge || warnExposedInMenuBar || notifyOnNewPort || notifyOnExposedPort
    }

    // MARK: Persistence

    private enum Keys {
        static let appearance = "appearance"
        static let accentTint = "accentTint"
        static let rowDensity = "rowDensity"
        static let showPID = "showPID"
        static let showPath = "showPath"
        static let showUser = "showUser"
        static let showUptime = "showUptime"
        static let showProtocolBadge = "showProtocolBadge"
        static let refreshInterval = "refreshInterval"
        static let confirmBeforeKill = "confirmBeforeKill"
        static let killGracePeriod = "killGracePeriod"
        static let autoEscalateToSigkill = "autoEscalateToSigkill"
        static let showDockIcon = "showDockIcon"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let showPortCountBadge = "showPortCountBadge"
        static let warnExposedInMenuBar = "warnExposedInMenuBar"
        static let labelRules = "labelRules"
        static let pinnedPorts = "pinnedPorts"
        static let notifyOnNewPort = "notifyOnNewPort"
        static let notifyOnExposedPort = "notifyOnExposedPort"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        accentTint = AccentTint(rawValue: defaults.string(forKey: Keys.accentTint) ?? "") ?? .system
        rowDensity = RowDensity(rawValue: defaults.string(forKey: Keys.rowDensity) ?? "") ?? .comfortable
        showPID = defaults.object(forKey: Keys.showPID) as? Bool ?? true
        showPath = defaults.object(forKey: Keys.showPath) as? Bool ?? false
        showUser = defaults.object(forKey: Keys.showUser) as? Bool ?? false
        showUptime = defaults.object(forKey: Keys.showUptime) as? Bool ?? true
        showProtocolBadge = defaults.object(forKey: Keys.showProtocolBadge) as? Bool ?? true
        refreshInterval = RefreshInterval(rawValue: defaults.object(forKey: Keys.refreshInterval) as? Int ?? 2) ?? .twoSeconds
        confirmBeforeKill = defaults.object(forKey: Keys.confirmBeforeKill) as? Bool ?? true
        killGracePeriod = defaults.object(forKey: Keys.killGracePeriod) as? Double ?? 3.0
        autoEscalateToSigkill = defaults.object(forKey: Keys.autoEscalateToSigkill) as? Bool ?? false
        showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false
        menuBarIconStyle = MenuBarIconStyle(rawValue: defaults.string(forKey: Keys.menuBarIconStyle) ?? "") ?? .network
        showPortCountBadge = defaults.object(forKey: Keys.showPortCountBadge) as? Bool ?? false
        warnExposedInMenuBar = defaults.object(forKey: Keys.warnExposedInMenuBar) as? Bool ?? true
        notifyOnNewPort = defaults.object(forKey: Keys.notifyOnNewPort) as? Bool ?? false
        notifyOnExposedPort = defaults.object(forKey: Keys.notifyOnExposedPort) as? Bool ?? false

        if let data = defaults.data(forKey: Keys.labelRules),
           let rules = try? JSONDecoder().decode([PortLabelRule].self, from: data) {
            labelRules = rules
        } else {
            labelRules = PortLabelRule.defaultRules
        }
        pinnedPorts = Set(defaults.array(forKey: Keys.pinnedPorts) as? [Int] ?? [])
    }
}
