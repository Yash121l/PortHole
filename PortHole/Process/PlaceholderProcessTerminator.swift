import Foundation

/// Temporary stand-in wired between milestones 2 and 4, so the real scanner
/// can ship before the real signal path does. Milestone 4 replaces this with
/// `ProcessController` (SIGTERM → grace period → SIGKILL, EPERM handling).
struct PlaceholderProcessTerminator: ProcessTerminating {
    private struct NotYetImplemented: LocalizedError {
        var errorDescription: String? {
            "Killing processes arrives in milestone 4 — this build only observes ports."
        }
    }

    func terminate(pid: Int32, processName: String, gracePeriod: TimeInterval, escalateToSigkill: Bool) async throws -> TerminationOutcome {
        throw NotYetImplemented()
    }

    func forceKill(pid: Int32, processName: String) async throws -> TerminationOutcome {
        throw NotYetImplemented()
    }
}
