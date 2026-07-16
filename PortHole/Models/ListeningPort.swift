import Foundation

/// Transport protocol of a listening socket.
enum NetworkProtocol: String, Codable, CaseIterable, Sendable, Identifiable {
    case tcp = "TCP"
    case udp = "UDP"

    var id: String { rawValue }
}

/// Where a socket is bound, from a security point of view.
///
/// A socket bound to a loopback address is reachable only from this Mac.
/// A socket bound to the wildcard address — or to a concrete LAN interface —
/// is reachable from other machines on the network. That is a security-relevant
/// state, so the UI calls it out explicitly rather than burying it in an
/// address string.
enum BindScope: String, Codable, Sendable {
    /// 127.0.0.0/8 or ::1 — local machine only.
    case loopback
    /// The wildcard address (`*`, `0.0.0.0`, `::`) — listening on every interface.
    case allInterfaces
    /// Bound to one concrete interface address (e.g. a LAN IP).
    case specificInterface

    /// Anything that is not loopback can be reached from the network.
    var isExposed: Bool { self != .loopback }

    static func classify(address: String) -> BindScope {
        switch address {
        case "*", "0.0.0.0", "::", "[::]":
            return .allInterfaces
        case "::1", "[::1]":
            return .loopback
        default:
            if address.hasPrefix("127.") { return .loopback }
            return .specificInterface
        }
    }
}

/// One listening socket, mapped to the process that owns it.
struct ListeningPort: Identifiable, Hashable, Sendable {
    let port: Int
    let networkProtocol: NetworkProtocol
    /// The address as reported by the scanner (`*`, `127.0.0.1`, `::1`, a LAN IP, …).
    let bindAddress: String
    let pid: Int32
    let processName: String
    var executablePath: String?
    var user: String?
    var processStartDate: Date?

    var bindScope: BindScope { BindScope.classify(address: bindAddress) }
    var isExposed: Bool { bindScope.isExposed }

    /// Stable identity of a socket across scans: the same protocol + address +
    /// port owned by the same pid is "the same row". Used for diffing and for
    /// preserving selection/first-seen dates between refreshes.
    var id: String { "\(networkProtocol.rawValue):\(bindAddress):\(port):\(pid)" }
}

// MARK: - "Open in browser" heuristics

extension ListeningPort {
    /// Ports that are overwhelmingly likely to speak HTTP on localhost.
    static let commonWebPorts: Set<Int> = [
        80, 443, 1313, 3000, 3001, 4000, 4200, 4321, 5000, 5173, 5174,
        6006, 8000, 8080, 8081, 8443, 8787, 8888, 9000, 9090,
    ]

    /// Process names that usually mean "dev server" when they hold a TCP port.
    private static let devServerProcessHints: [String] = [
        "node", "deno", "bun", "vite", "next", "python", "ruby", "php",
        "rails", "puma", "caddy", "nginx", "httpd", "java", "gunicorn",
        "uvicorn", "flask", "dotnet", "webpack", "parcel", "astro", "hugo",
        "jekyll",
    ]

    /// Best-effort guess that `http://localhost:<port>` will render something.
    /// Used only to decide whether to *offer* the "Open in Browser" action.
    var likelyServesHTTP: Bool {
        guard networkProtocol == .tcp else { return false }
        if Self.commonWebPorts.contains(port) { return true }
        guard port >= 1024 else { return false }
        let name = processName.lowercased()
        return Self.devServerProcessHints.contains { name.contains($0) }
    }

    var localURL: URL? {
        URL(string: "http://localhost:\(port)")
    }
}
