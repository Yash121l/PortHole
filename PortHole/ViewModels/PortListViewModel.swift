import SwiftUI
import Observation
import os.log

/// Drives the menu-bar panel. Owns scan scheduling, filtering/sorting, and the
/// kill flow; views stay declarative and observe this object.
@MainActor
@Observable
final class PortListViewModel {
    enum SortOrder: String, CaseIterable, Identifiable {
        case port, process, pid, recent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .port: return "Port"
            case .process: return "Process Name"
            case .pid: return "PID"
            case .recent: return "Recently Appeared"
            }
        }
    }

    /// A process and the ports it holds, for the grouped-by-app view.
    struct ProcessGroup: Identifiable {
        let pid: Int32
        let processName: String
        let executablePath: String?
        let ports: [ListeningPort]
        var id: Int32 { pid }
    }

    // MARK: Scan state

    private(set) var ports: [ListeningPort] = []
    /// True only during *user-initiated* scans — background auto-refreshes
    /// stay silent so the panel doesn't re-render (and the spinner doesn't
    /// flicker) every polling tick.
    private(set) var isScanning = false
    private(set) var scanError: String?
    private(set) var lastRefresh: Date?
    /// Bumped only when rows appear or disappear. Views key their insert/
    /// remove animations to this instead of the whole array, so metadata
    /// updates never trigger a list-wide animation pass.
    private(set) var structuralChanges = 0

    // MARK: Filter / sort state

    var searchText = ""
    var sortOrder: SortOrder = .port
    var showTCP = true
    var showUDP = true
    var exposedOnly = false
    var groupByProcess = false
    var selection: ListeningPort.ID?

    // MARK: Kill flow state

    /// Non-nil while the confirm-before-kill dialog is showing.
    var pendingKill: ListeningPort?
    /// Outcome or error message surfaced in an alert.
    var killMessage: String?
    /// Rows whose SIGTERM survived, so the UI can offer explicit Force Kill.
    private(set) var survivedSigterm: Set<ListeningPort.ID> = []

    // MARK: Internals

    private var firstSeen: [ListeningPort.ID: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var panelIsOpen = false
    private var hasCompletedInitialScan = false
    /// Reentrancy guard, deliberately separate from the UI-facing
    /// `isScanning` so silent scans don't touch observed state.
    private var scanInFlight = false

    private let scanner: any PortScanning
    private let terminator: any ProcessTerminating
    let settings: SettingsStore
    /// Audit trail for the kill flow — an app whose job is signalling other
    /// processes should leave a record of what it signalled and why.
    private let log = Logger(subsystem: "io.github.yash121l.PortHole", category: "kill")

    init(scanner: any PortScanning, terminator: any ProcessTerminating, settings: SettingsStore) {
        self.scanner = scanner
        self.terminator = terminator
        self.settings = settings
    }

    // MARK: - Derived collections

    var filteredPorts: [ListeningPort] {
        var result = ports

        if !showTCP { result.removeAll { $0.networkProtocol == .tcp } }
        if !showUDP { result.removeAll { $0.networkProtocol == .udp } }
        if exposedOnly { result.removeAll { !$0.isExposed } }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                String($0.port).contains(query)
                    || $0.processName.localizedCaseInsensitiveContains(query)
                    || String($0.pid).contains(query)
            }
        }

        result.sort { lhs, rhs in
            // Pinned ports always sort to the top.
            let lhsPinned = settings.isPinned(lhs.port)
            let rhsPinned = settings.isPinned(rhs.port)
            if lhsPinned != rhsPinned { return lhsPinned }

            switch sortOrder {
            case .port:
                if lhs.port != rhs.port { return lhs.port < rhs.port }
                return lhs.processName < rhs.processName
            case .process:
                let name = lhs.processName.localizedCaseInsensitiveCompare(rhs.processName)
                if name != .orderedSame { return name == .orderedAscending }
                return lhs.port < rhs.port
            case .pid:
                if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
                return lhs.port < rhs.port
            case .recent:
                let lhsSeen = firstSeen[lhs.id] ?? .distantPast
                let rhsSeen = firstSeen[rhs.id] ?? .distantPast
                if lhsSeen != rhsSeen { return lhsSeen > rhsSeen }
                return lhs.port < rhs.port
            }
        }
        return result
    }

    var groupedPorts: [ProcessGroup] {
        let filtered = filteredPorts
        var order: [Int32] = []
        var byPid: [Int32: [ListeningPort]] = [:]
        for port in filtered {
            if byPid[port.pid] == nil { order.append(port.pid) }
            byPid[port.pid, default: []].append(port)
        }
        return order.map { pid in
            let ports = byPid[pid] ?? []
            return ProcessGroup(pid: pid,
                                processName: ports.first?.processName ?? "?",
                                executablePath: ports.first?.executablePath,
                                ports: ports)
        }
    }

    var selectedPort: ListeningPort? {
        guard let selection else { return nil }
        return ports.first { $0.id == selection }
    }

    var portCount: Int { ports.count }
    var hasExposedPorts: Bool { ports.contains { $0.isExposed } }

    func firstSeenDate(for port: ListeningPort) -> Date? {
        firstSeen[port.id]
    }

    // MARK: - Scanning

    func refresh(userInitiated: Bool = false) async {
        guard !scanInFlight else { return }
        scanInFlight = true
        if userInitiated { isScanning = true }
        defer {
            scanInFlight = false
            if userInitiated { isScanning = false }
        }
        do {
            let scanned = try await scanner.scan()
            let now = Date()
            // Diff against the previous scan and skip the UI write entirely
            // when nothing changed — no invalidation, no flicker. Inserts and
            // removals animate because rows are keyed by stable ids.
            let diff = PortDiff.between(previous: ports, current: scanned)
            for port in diff.added {
                firstSeen[port.id] = now
            }
            if !diff.isEmpty {
                let scannedIDs = Set(scanned.map(\.id))
                firstSeen = firstSeen.filter { scannedIDs.contains($0.key) }
                survivedSigterm = survivedSigterm.intersection(scannedIDs)
                // If the process being confirmed died on its own, retract the
                // dialog instead of offering a kill against a recycled PID.
                if let pending = pendingKill, !scannedIDs.contains(pending.id) {
                    pendingKill = nil
                }
                if !diff.added.isEmpty || !diff.removed.isEmpty {
                    // Same transaction as the ports write → the list animates
                    // exactly this change and nothing else.
                    structuralChanges += 1
                }
                ports = scanned
            }
            // The first scan after launch "adds" everything — never notify
            // about it. Only genuine arrivals afterwards are interesting.
            if hasCompletedInitialScan {
                NotificationManager.shared.scanDidChange(diff: diff, settings: settings)
            }
            hasCompletedInitialScan = true
            // Observable writes are guarded — an unconditional `scanError =
            // nil` every 2s would re-render the whole content area for nothing.
            if scanError != nil { scanError = nil }
            lastRefresh = now
        } catch {
            scanError = error.localizedDescription
        }
    }

    /// Called when the menu-bar panel opens: do an immediate scan and start
    /// the auto-refresh loop.
    func panelAppeared() {
        panelIsOpen = true
        Task { await refresh(userInitiated: true) }
        rescheduleRefreshLoop()
    }

    /// Called when the panel closes. Polling pauses (or drops to a slow
    /// background cadence if the menu-bar badge/notifications need data).
    func panelDisappeared() {
        panelIsOpen = false
        // Don't let a confirmation outlive the panel: by the time it reopens
        // the PID may belong to a different process.
        pendingKill = nil
        rescheduleRefreshLoop()
    }

    /// (Re)starts the polling loop to match the current interval setting and
    /// panel visibility. Panel closed → slow background cadence only if some
    /// feature (badge, exposed warning, notifications) needs fresh data.
    func rescheduleRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil

        let interval: TimeInterval
        if panelIsOpen {
            let configured = settings.refreshInterval.seconds
            guard configured > 0 else { return } // manual only
            interval = configured
        } else {
            guard settings.needsBackgroundScanning else { return }
            interval = max(settings.refreshInterval.seconds * 5, 10)
        }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    // MARK: - Kill flow

    /// Entry point for every kill gesture. Routes through the confirmation
    /// dialog when the user has confirmation enabled.
    func requestKill(_ port: ListeningPort) {
        log.info("kill requested: \(port.processName, privacy: .public) pid \(port.pid) port \(port.port) (confirm=\(self.settings.confirmBeforeKill))")
        if settings.confirmBeforeKill {
            pendingKill = port
        } else {
            Task { await kill(port) }
        }
    }

    func confirmPendingKill() {
        guard let port = pendingKill else { return }
        log.info("kill confirmed: \(port.processName, privacy: .public) pid \(port.pid)")
        pendingKill = nil
        Task { await kill(port) }
    }

    func kill(_ port: ListeningPort) async {
        do {
            let outcome = try await terminator.terminate(
                pid: port.pid,
                processName: port.processName,
                gracePeriod: settings.killGracePeriod,
                escalateToSigkill: settings.autoEscalateToSigkill
            )
            log.info("terminate finished: \(port.processName, privacy: .public) pid \(port.pid) outcome=\(String(describing: outcome), privacy: .public)")
            if outcome == .stillRunning {
                survivedSigterm.insert(port.id)
                killMessage = settings.autoEscalateToSigkill
                    ? "\(port.processName) survived SIGTERM and SIGKILL — it may be stuck in the kernel."
                    : "\(port.processName) is still running after SIGTERM. Use Force Kill to stop it immediately."
            }
        } catch TerminationError.processNotFound {
            // Already gone; the refresh below drops the row.
            log.info("terminate skipped: pid \(port.pid) already exited")
        } catch {
            log.error("terminate failed: pid \(port.pid) — \(error.localizedDescription, privacy: .public)")
            killMessage = error.localizedDescription
        }
        await refresh()
    }

    func forceKill(_ port: ListeningPort) async {
        log.info("force kill: \(port.processName, privacy: .public) pid \(port.pid)")
        do {
            _ = try await terminator.forceKill(pid: port.pid, processName: port.processName)
            survivedSigterm.remove(port.id)
        } catch TerminationError.processNotFound {
            survivedSigterm.remove(port.id)
        } catch {
            killMessage = error.localizedDescription
        }
        await refresh()
    }

    /// Resets every way rows can be hidden (search, protocol chips, exposed
    /// toggle) — the "Clear Filters" escape hatch in the no-matches state.
    func clearFilters() {
        searchText = ""
        showTCP = true
        showUDP = true
        exposedOnly = false
    }

    // MARK: - Row actions

    func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func openInBrowser(_ port: ListeningPort) {
        guard let url = port.localURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ port: ListeningPort) {
        guard let path = port.executablePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
