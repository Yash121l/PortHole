import XCTest
@testable import PortHole

/// End-to-end checks against the live system: spawn a real listener, watch
/// the real scanner find it, kill it through the real controller, and watch
/// it disappear. These run in the (non-sandboxed) test host, so lsof and
/// kill(2) behave exactly as they do in the shipping app.
final class ScannerKillIntegrationTests: XCTestCase {
    func testScannerSeesListenerAndControllerKillsIt() async throws {
        let port = 39_471
        let listenerProcess = Process()
        listenerProcess.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        listenerProcess.arguments = ["-l", "127.0.0.1", String(port)]
        try listenerProcess.run()
        defer { if listenerProcess.isRunning { listenerProcess.terminate() } }

        let scanner = LsofPortScanner()

        var found: ListeningPort?
        for _ in 0..<25 { // allow up to ~5s for nc to bind and lsof to see it
            let ports = try await scanner.scan()
            if let match = ports.first(where: { $0.port == port && $0.pid == listenerProcess.processIdentifier }) {
                found = match
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        let listener = try XCTUnwrap(found, "scanner never reported the nc listener on port \(port)")
        XCTAssertEqual(listener.networkProtocol, .tcp)
        XCTAssertEqual(listener.bindScope, .loopback)
        XCTAssertEqual(listener.processName, "nc")
        XCTAssertNotNil(listener.executablePath, "libproc enrichment should resolve the executable path")

        let controller = ProcessController()
        let outcome = try await controller.terminate(pid: listener.pid,
                                                     processName: listener.processName,
                                                     gracePeriod: 3,
                                                     escalateToSigkill: true)
        XCTAssertTrue(outcome == .terminated || outcome == .forceKilled,
                      "unexpected outcome \(outcome)")

        for _ in 0..<15 {
            let ports = try await scanner.scan()
            if !ports.contains(where: { $0.pid == listener.pid }) {
                return // gone — success
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("listener still visible in scans after kill")
    }

    func testSignallingRootOwnedProcessReportsPermissionDenied() async throws {
        // Never run this as root — pid 1 is launchd and the signal would land.
        try XCTSkipIf(geteuid() == 0, "test must not run with root privileges")

        let controller = ProcessController()
        do {
            _ = try await controller.terminate(pid: 1, processName: "launchd",
                                               gracePeriod: 0.1, escalateToSigkill: false)
            XCTFail("expected EPERM signalling launchd")
        } catch let error as TerminationError {
            XCTAssertEqual(error, .permissionDenied(processName: "launchd"))
            XCTAssertEqual(error.errorDescription,
                           "launchd is owned by another user and requires elevated privileges to stop.")
        }
    }
}
