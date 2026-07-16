import Foundation

/// In-memory scanner used for milestone 1 UI development and for SwiftUI
/// previews. Behaves like the real thing — including "kill removes the rows"
/// — without touching the system.
actor MockPortScanner: PortScanning {
    private var sample: [ListeningPort]

    init() {
        let now = Date()
        sample = [
            ListeningPort(port: 3000, networkProtocol: .tcp, bindAddress: "*",
                          pid: 4821, processName: "node",
                          executablePath: "/usr/local/bin/node", user: "admin",
                          processStartDate: now.addingTimeInterval(-7_500)),
            ListeningPort(port: 5173, networkProtocol: .tcp, bindAddress: "127.0.0.1",
                          pid: 5077, processName: "node",
                          executablePath: "/usr/local/bin/node", user: "admin",
                          processStartDate: now.addingTimeInterval(-1_260)),
            ListeningPort(port: 5432, networkProtocol: .tcp, bindAddress: "127.0.0.1",
                          pid: 812, processName: "postgres",
                          executablePath: "/opt/homebrew/bin/postgres", user: "admin",
                          processStartDate: now.addingTimeInterval(-86_400 * 3)),
            ListeningPort(port: 6379, networkProtocol: .tcp, bindAddress: "127.0.0.1",
                          pid: 830, processName: "redis-server",
                          executablePath: "/opt/homebrew/bin/redis-server", user: "admin",
                          processStartDate: now.addingTimeInterval(-86_400)),
            ListeningPort(port: 8000, networkProtocol: .tcp, bindAddress: "0.0.0.0",
                          pid: 6210, processName: "python3.12",
                          executablePath: "/opt/homebrew/bin/python3.12", user: "admin",
                          processStartDate: now.addingTimeInterval(-300)),
            ListeningPort(port: 7000, networkProtocol: .tcp, bindAddress: "*",
                          pid: 519, processName: "ControlCenter",
                          executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
                          user: "admin",
                          processStartDate: now.addingTimeInterval(-86_400 * 7)),
            ListeningPort(port: 5353, networkProtocol: .udp, bindAddress: "*",
                          pid: 289, processName: "mDNSResponder",
                          executablePath: "/usr/sbin/mDNSResponder", user: "_mdnsresponder",
                          processStartDate: now.addingTimeInterval(-86_400 * 7)),
        ]
    }

    func scan() async throws -> [ListeningPort] {
        sample
    }

    /// Lets the mock terminator simulate a successful kill.
    func removeProcess(pid: Int32) {
        sample.removeAll { $0.pid == pid }
    }
}
