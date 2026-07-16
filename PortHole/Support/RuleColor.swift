import SwiftUI

/// Fixed palette for port-label rules. Stored by name so rules stay `Codable`
/// and render correctly in both light and dark appearances.
enum RuleColor {
    static let allNames: [String] = [
        "red", "orange", "yellow", "green", "mint", "teal", "cyan",
        "blue", "indigo", "purple", "pink", "brown", "gray",
    ]

    static func color(named name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray": return .gray
        default: return .accentColor
        }
    }
}
