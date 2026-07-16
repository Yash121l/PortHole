import Foundation

/// How a termination attempt ended.
enum TerminationOutcome: Sendable, Equatable {
    /// The process exited after SIGTERM within the grace period.
    case terminated
    /// SIGTERM was not enough; the process exited only after SIGKILL.
    case forceKilled
    /// The process survived SIGTERM and escalation was disabled (or SIGKILL
    /// has not taken effect yet). The UI offers an explicit Force Kill.
    case stillRunning
}

/// Errors surfaced when a signal cannot be delivered.
enum TerminationError: LocalizedError, Sendable, Equatable {
    /// `kill(2)` returned EPERM. On macOS this means the target is owned by
    /// another user (or is a protected system process); killing it would need
    /// elevated privileges. v1 surfaces this clearly instead of failing
    /// silently — a privileged-helper flow is a documented later milestone.
    case permissionDenied(processName: String)
    /// `kill(2)` returned ESRCH — the process is already gone.
    case processNotFound
    /// Any other errno from `kill(2)`.
    case sendFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let name):
            return "\(name) is owned by another user and requires elevated privileges to stop."
        case .processNotFound:
            return "The process has already exited."
        case .sendFailed(let code):
            return "Failed to signal the process (errno \(code))."
        }
    }
}

/// Abstraction over "stop the process that owns this port". The real
/// implementation (`ProcessController`) sends SIGTERM and escalates to
/// SIGKILL; the mock just edits the mock scanner's data.
protocol ProcessTerminating: Sendable {
    /// Polite termination: SIGTERM, wait up to `gracePeriod`, then optionally
    /// escalate to SIGKILL.
    func terminate(pid: Int32, processName: String, gracePeriod: TimeInterval, escalateToSigkill: Bool) async throws -> TerminationOutcome

    /// Immediate SIGKILL, used by the explicit "Force Kill" action.
    func forceKill(pid: Int32, processName: String) async throws -> TerminationOutcome
}

/// Milestone-1 stand-in that "kills" rows in the mock scanner.
struct MockProcessTerminator: ProcessTerminating {
    let scanner: MockPortScanner

    func terminate(pid: Int32, processName: String, gracePeriod: TimeInterval, escalateToSigkill: Bool) async throws -> TerminationOutcome {
        await scanner.removeProcess(pid: pid)
        return .terminated
    }

    func forceKill(pid: Int32, processName: String) async throws -> TerminationOutcome {
        await scanner.removeProcess(pid: pid)
        return .forceKilled
    }
}
