import Foundation

enum Formatting {
    /// Compact process uptime, e.g. "42s", "12m", "3h 05m", "6d 4h".
    static func uptime(since start: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        guard seconds >= 0 else { return "—" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return String(format: "%dh %02dm", hours, minutes % 60) }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
