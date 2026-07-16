import Foundation

/// One process block from `lsof -F` output: the process-level fields plus
/// every network file (socket) it holds.
struct LsofRecord: Equatable, Sendable {
    struct Socket: Equatable, Sendable {
        /// `P` field — "TCP" or "UDP".
        var protocolName: String = ""
        /// `n` field — the raw name, e.g. `*:3000`, `127.0.0.1:5432`,
        /// `[::1]:8080`, `*:*`, or `10.0.0.5:123->1.2.3.4:123`.
        var rawName: String = ""
    }

    var pid: Int32
    var command: String = "?"
    var uid: Int32?
    var loginName: String?
    var sockets: [Socket] = []
}

/// Parser for `lsof -F` field output (`lsof -nPw -i… -FpcuLPn`).
///
/// The `-F` format is one field per line: the first character names the field,
/// the rest is the value. A `p` line starts a new process set; an `f` line
/// starts a new file set within it. This is far more reliable than parsing the
/// human-readable columnar output, which reflows with content width.
enum LsofParser {
    // MARK: Raw records

    static func records(from output: String) -> [LsofRecord] {
        var records: [LsofRecord] = []
        var current: LsofRecord?
        var socket: LsofRecord.Socket?

        func flushSocket() {
            if let finished = socket {
                current?.sockets.append(finished)
            }
            socket = nil
        }
        func flushRecord() {
            flushSocket()
            if let finished = current {
                records.append(finished)
            }
            current = nil
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flushRecord()
                current = LsofRecord(pid: Int32(value) ?? -1)
            case "c":
                current?.command = value
            case "u":
                current?.uid = Int32(value)
            case "L":
                current?.loginName = value
            case "f":
                flushSocket()
                socket = LsofRecord.Socket()
            case "P":
                socket?.protocolName = value
            case "n":
                socket?.rawName = value
            default:
                break // unrequested fields (t, g, R, …) are ignored
            }
        }
        flushRecord()
        return records.filter { $0.pid > 0 }
    }

    // MARK: Listening ports

    /// Flattens records into `ListeningPort` values. Skips sockets that are
    /// not actually listening endpoints (`*:*` UDP placeholders, connected
    /// sockets with a `->` peer) and collapses IPv4/IPv6 duplicates of the
    /// same address string (e.g. a server listening on `*:3000` over both
    /// stacks shows up once, not twice).
    static func listeningPorts(from records: [LsofRecord]) -> [ListeningPort] {
        var seen = Set<String>()
        var result: [ListeningPort] = []

        for record in records {
            for socket in record.sockets {
                guard let networkProtocol = NetworkProtocol(rawValue: socket.protocolName.uppercased()) else { continue }
                guard let endpoint = parseEndpoint(socket.rawName) else { continue }

                let port = ListeningPort(
                    port: endpoint.port,
                    networkProtocol: networkProtocol,
                    bindAddress: endpoint.address,
                    pid: record.pid,
                    processName: record.command,
                    executablePath: nil,
                    user: record.loginName,
                    processStartDate: nil
                )
                if seen.insert(port.id).inserted {
                    result.append(port)
                }
            }
        }
        return result
    }

    /// Parses an `n` field value into (address, port). Returns nil for
    /// anything that isn't a plain listening endpoint.
    static func parseEndpoint(_ rawName: String) -> (address: String, port: Int)? {
        var name = rawName

        // Defensive: columnar lsof appends " (LISTEN)"; -F output shouldn't,
        // but stripping it costs nothing.
        if let range = name.range(of: " (") {
            name = String(name[..<range.lowerBound])
        }

        // A "->" means a connected socket (UDP with a peer) — not a listener.
        guard !name.contains("->") else { return nil }

        // Split address:port at the *last* colon so IPv6 survives.
        guard let colon = name.lastIndex(of: ":") else { return nil }
        var address = String(name[..<colon])
        let portString = String(name[name.index(after: colon)...])

        // "*:*" — a UDP socket with no fixed local port; not a listener.
        guard let port = Int(portString), port > 0 else { return nil }

        // "[::1]" → "::1"
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        guard !address.isEmpty else { return nil }

        return (address, port)
    }
}
