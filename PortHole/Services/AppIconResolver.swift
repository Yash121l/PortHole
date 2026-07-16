import AppKit
import UniformTypeIdentifiers

/// Resolves the icon shown next to each row.
///
/// Resolution order:
/// 1. `NSRunningApplication(processIdentifier:)` — regular GUI apps report
///    their real icon directly.
/// 2. Walk the executable path upward to an enclosing `.app` bundle and ask
///    NSWorkspace for that bundle's icon — this covers helper binaries living
///    inside an app wrapper (e.g. `Slack Helper`).
/// 3. The file icon of the executable itself, else the generic Unix
///    executable icon (daemons like postgres land here).
///
/// Icons are cached by executable path; resolution happens on first display
/// of a row and is cheap thereafter.
@MainActor
final class AppIconResolver {
    static let shared = AppIconResolver()

    private var cache: [String: NSImage] = [:]

    func icon(pid: Int32, executablePath: String?) -> NSImage {
        let key = executablePath ?? "?generic"
        if let cached = cache[key] {
            return cached
        }
        let resolved = resolve(pid: pid, executablePath: executablePath)
        cache[key] = resolved
        return resolved
    }

    private func resolve(pid: Int32, executablePath: String?) -> NSImage {
        if let running = NSRunningApplication(processIdentifier: pid),
           let icon = running.icon {
            return icon
        }

        if let executablePath {
            var url = URL(fileURLWithPath: executablePath)
            while url.path != "/" {
                if url.pathExtension == "app" {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
                url.deleteLastPathComponent()
            }
            if FileManager.default.fileExists(atPath: executablePath) {
                return NSWorkspace.shared.icon(forFile: executablePath)
            }
        }

        return NSWorkspace.shared.icon(for: .unixExecutable)
    }
}
