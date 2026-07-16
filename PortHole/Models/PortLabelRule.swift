import Foundation

/// A user-editable rule that attaches a human-readable label (and a color)
/// to a port number, optionally narrowed by a process-name substring.
///
/// Example: port 5173 → "Vite", or port 5000 + process hint "python" → "Flask".
struct PortLabelRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var port: Int
    var label: String
    /// One of the fixed palette names in `RuleColor.allNames`.
    var colorName: String
    /// Optional case-insensitive substring the process name must contain.
    /// Empty means "match on port alone".
    var processHint: String

    init(id: UUID = UUID(), port: Int, label: String, colorName: String = "blue", processHint: String = "") {
        self.id = id
        self.port = port
        self.label = label
        self.colorName = colorName
        self.processHint = processHint
    }

    func matches(_ candidate: ListeningPort) -> Bool {
        guard port == candidate.port else { return false }
        guard !processHint.isEmpty else { return true }
        return candidate.processName.localizedCaseInsensitiveContains(processHint)
    }
}

extension PortLabelRule {
    /// Best-effort defaults for well-known development ports. Fully editable
    /// (and deletable) in Settings → Port Labels.
    static let defaultRules: [PortLabelRule] = [
        PortLabelRule(port: 3000, label: "Next.js / Node dev", colorName: "green"),
        PortLabelRule(port: 3001, label: "Node dev", colorName: "green"),
        PortLabelRule(port: 4200, label: "Angular dev", colorName: "red"),
        PortLabelRule(port: 4321, label: "Astro dev", colorName: "orange"),
        PortLabelRule(port: 5000, label: "Flask / AirPlay", colorName: "teal"),
        PortLabelRule(port: 5173, label: "Vite", colorName: "purple"),
        PortLabelRule(port: 5432, label: "Postgres", colorName: "blue"),
        PortLabelRule(port: 6006, label: "Storybook", colorName: "pink"),
        PortLabelRule(port: 6379, label: "Redis", colorName: "red"),
        PortLabelRule(port: 8000, label: "Django / uvicorn", colorName: "green"),
        PortLabelRule(port: 8080, label: "HTTP (alt)", colorName: "orange"),
        PortLabelRule(port: 8888, label: "Jupyter", colorName: "orange"),
        PortLabelRule(port: 9092, label: "Kafka", colorName: "gray"),
        PortLabelRule(port: 9200, label: "Elasticsearch", colorName: "yellow"),
        PortLabelRule(port: 11434, label: "Ollama", colorName: "indigo"),
        PortLabelRule(port: 3306, label: "MySQL", colorName: "blue"),
        PortLabelRule(port: 27017, label: "MongoDB", colorName: "green"),
        PortLabelRule(port: 5353, label: "mDNS / Bonjour", colorName: "gray"),
    ]
}
