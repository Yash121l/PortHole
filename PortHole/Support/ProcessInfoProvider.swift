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

    /// Full argv via `sysctl(KERN_PROCARGS2)`. This is what lets the UI label
    /// a bare `node`/`python` process by the tool it is actually running
    /// (vite, next, manage.py, …). Only readable for the current user's
    /// processes — nil otherwise, never an error.
    static func arguments(pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        // Buffer layout: int32 argc | exec_path\0 | \0 padding | argv[0]\0 argv[1]\0 … | environ
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 } // skip exec_path
        while index < size, buffer[index] == 0 { index += 1 } // skip padding

        var arguments: [String] = []
        var current: [UInt8] = []
        while index < size, arguments.count < Int(argc) {
            if buffer[index] == 0 {
                arguments.append(String(decoding: current, as: UTF8.self))
                current = []
            } else {
                current.append(buffer[index])
            }
            index += 1
        }
        return arguments.isEmpty ? nil : arguments
    }

    /// Current working directory via `proc_pidinfo(PROC_PIDVNODEPATHINFO)`.
    /// For dev servers this is the project folder — far more recognizable
    /// than "node" — so the UI surfaces its name next to the process.
    static func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        let written = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard written > 0 else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        return path.isEmpty ? nil : path
    }
}
