import Foundation
import Darwin

/// Thin wrapper over libproc for per-pid metadata. These are direct kernel
/// queries — no subprocess spawns — and they work for processes visible to
/// this user session because the app is not sandboxed. Queries about other
/// users' processes may fail; callers treat nil as "unknown", never an error.
enum ProcessInfoProvider {
    /// Full executable path via `proc_pidpath(2)`.
    static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Process start time via `proc_pidinfo(PROC_PIDTBSDINFO)`; the UI derives
    /// uptime from it.
    static func startDate(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard written == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                    + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }
}
