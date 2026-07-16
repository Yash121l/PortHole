import Foundation

/// Diff between two scans, keyed by `ListeningPort.id`. The view model skips
/// UI writes entirely when a scan changed nothing (no invalidation → no
/// flicker), and milestone 6 uses `added` to drive notifications.
struct PortDiff: Equatable, Sendable {
    var added: [ListeningPort] = []
    var removed: [ListeningPort] = []
    /// Same socket identity, changed metadata (e.g. executable path resolved
    /// on a later scan).
    var updated: [ListeningPort] = []

    var isEmpty: Bool { added.isEmpty && removed.isEmpty && updated.isEmpty }

    static func between(previous: [ListeningPort], current: [ListeningPort]) -> PortDiff {
        let previousByID = Dictionary(previous.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(current.map(\.id))

        var diff = PortDiff()
        for port in current {
            if let existing = previousByID[port.id] {
                if existing != port {
                    diff.updated.append(port)
                }
            } else {
                diff.added.append(port)
            }
        }
        diff.removed = previous.filter { !currentIDs.contains($0.id) }
        return diff
    }
}
