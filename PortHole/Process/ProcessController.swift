import Foundation
import Darwin

/// Sends termination signals via `kill(2)` and reports honestly what happened.
///
/// Escalation policy (security-relevant): SIGTERM goes first — a well-behaved
/// process gets the chance to flush state and exit cleanly. Only after the
/// user-configurable grace period expires do we optionally send SIGKILL,
/// which cannot be caught or ignored. Auto-escalation is off by default; the
/// UI offers an explicit Force Kill instead.
///
/// Privilege handling: signalling our own processes works. `kill(2)` on a
/// process owned by another user — or a SIP-protected system process — fails
/// with EPERM, which is detected and surfaced as a clear message instead of a
/// silent failure. TODO(privileged helper): a later milestone can add an
/// SMAppService daemon + Authorization Services flow to stop root-owned
/// processes; deliberately not built in v1 rather than shipping a fragile
/// half-version.
struct ProcessController: ProcessTerminating {

    func terminate(pid: Int32, processName: String, gracePeriod: TimeInterval, escalateToSigkill: Bool) async throws -> TerminationOutcome {
        try sendSignal(SIGTERM, to: pid, processName: processName)

        // Poll for exit instead of sleeping out the whole grace period —
        // most processes exit within milliseconds and the UI should say so.
        if await waitForExit(pid: pid, timeout: gracePeriod) {
            return .terminated
        }

        guard escalateToSigkill else {
            return .stillRunning
        }

        try sendSignal(SIGKILL, to: pid, processName: processName)
        // SIGKILL can't be handled; give the kernel a beat to reap.
        if await waitForExit(pid: pid, timeout: 0.5) {
            return .forceKilled
        }
        return .stillRunning
    }

    func forceKill(pid: Int32, processName: String) async throws -> TerminationOutcome {
        try sendSignal(SIGKILL, to: pid, processName: processName)
        if await waitForExit(pid: pid, timeout: 0.5) {
            return .forceKilled
        }
        return .stillRunning
    }

    // MARK: Internals

    private func sendSignal(_ signal: Int32, to pid: Int32, processName: String) throws {
        guard Darwin.kill(pid, signal) != 0 else { return }
        switch errno {
        case EPERM:
            throw TerminationError.permissionDenied(processName: processName)
        case ESRCH:
            throw TerminationError.processNotFound
        default:
            throw TerminationError.sendFailed(errno: errno)
        }
    }

    /// Polls until the process disappears or the timeout elapses. Returns
    /// true when the process exited.
    private func waitForExit(pid: Int32, timeout: TimeInterval) async -> Bool {
        let pollInterval: TimeInterval = 0.15
        var waited: TimeInterval = 0
        while waited < timeout {
            try? await Task.sleep(for: .seconds(pollInterval))
            waited += pollInterval
            if !isAlive(pid) { return true }
        }
        return !isAlive(pid)
    }

    /// `kill(pid, 0)` delivers no signal but performs the existence and
    /// permission checks — the canonical liveness probe.
    private func isAlive(_ pid: Int32) -> Bool {
        if Darwin.kill(pid, 0) == 0 { return true }
        // EPERM means "exists, but you may not signal it" — still alive.
        return errno == EPERM
    }
}
