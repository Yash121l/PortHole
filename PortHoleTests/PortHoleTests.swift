import XCTest
@testable import PortHole

final class BindScopeTests: XCTestCase {
    func testLoopbackAddresses() {
        XCTAssertEqual(BindScope.classify(address: "127.0.0.1"), .loopback)
        XCTAssertEqual(BindScope.classify(address: "127.1.2.3"), .loopback)
        XCTAssertEqual(BindScope.classify(address: "::1"), .loopback)
        XCTAssertEqual(BindScope.classify(address: "[::1]"), .loopback)
        XCTAssertFalse(BindScope.loopback.isExposed)
    }

    func testWildcardAddressesAreExposed() {
        XCTAssertEqual(BindScope.classify(address: "*"), .allInterfaces)
        XCTAssertEqual(BindScope.classify(address: "0.0.0.0"), .allInterfaces)
        XCTAssertEqual(BindScope.classify(address: "::"), .allInterfaces)
        XCTAssertTrue(BindScope.allInterfaces.isExposed)
    }

    func testConcreteInterfaceAddressesAreExposed() {
        XCTAssertEqual(BindScope.classify(address: "192.168.1.20"), .specificInterface)
        XCTAssertEqual(BindScope.classify(address: "fe80::1%en0"), .specificInterface)
        XCTAssertTrue(BindScope.specificInterface.isExposed)
    }
}

final class PortLabelRuleTests: XCTestCase {
    private func port(_ number: Int, name: String) -> ListeningPort {
        ListeningPort(port: number, networkProtocol: .tcp, bindAddress: "*",
                      pid: 1, processName: name, executablePath: nil,
                      user: nil, processStartDate: nil)
    }

    func testMatchesOnPortAlone() {
        let rule = PortLabelRule(port: 5173, label: "Vite")
        XCTAssertTrue(rule.matches(port(5173, name: "node")))
        XCTAssertFalse(rule.matches(port(5174, name: "node")))
    }

    func testProcessHintNarrowsTheMatch() {
        let rule = PortLabelRule(port: 5000, label: "Flask", processHint: "python")
        XCTAssertTrue(rule.matches(port(5000, name: "Python3.12")))
        XCTAssertFalse(rule.matches(port(5000, name: "ControlCenter")))
    }

    func testRulesSurviveJSONRoundTrip() throws {
        let original = PortLabelRule.defaultRules
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([PortLabelRule].self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class HTTPHeuristicTests: XCTestCase {
    private func port(_ number: Int, name: String,
                      networkProtocol: NetworkProtocol = .tcp) -> ListeningPort {
        ListeningPort(port: number, networkProtocol: networkProtocol,
                      bindAddress: "127.0.0.1", pid: 1, processName: name,
                      executablePath: nil, user: nil, processStartDate: nil)
    }

    func testWellKnownWebPortsQualify() {
        XCTAssertTrue(port(3000, name: "whatever").likelyServesHTTP)
        XCTAssertTrue(port(5173, name: "node").likelyServesHTTP)
    }

    func testDevServerProcessOnUnknownHighPortQualifies() {
        XCTAssertTrue(port(1300, name: "node").likelyServesHTTP)
        XCTAssertFalse(port(1300, name: "mDNSResponder").likelyServesHTTP)
    }

    func testUDPAndLowPortsNeverQualify() {
        XCTAssertFalse(port(5353, name: "node", networkProtocol: .udp).likelyServesHTTP)
        XCTAssertFalse(port(22, name: "node").likelyServesHTTP)
    }

    func testLocalURL() {
        XCTAssertEqual(port(3000, name: "node").localURL?.absoluteString,
                       "http://localhost:3000")
    }
}

final class FormattingTests: XCTestCase {
    func testUptimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Formatting.uptime(since: now.addingTimeInterval(-42), now: now), "42s")
        XCTAssertEqual(Formatting.uptime(since: now.addingTimeInterval(-12 * 60), now: now), "12m")
        XCTAssertEqual(Formatting.uptime(since: now.addingTimeInterval(-3 * 3600 - 5 * 60), now: now), "3h 05m")
        XCTAssertEqual(Formatting.uptime(since: now.addingTimeInterval(-6 * 86400 - 4 * 3600), now: now), "6d 4h")
    }

    func testFutureStartDateDoesNotCrash() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Formatting.uptime(since: now.addingTimeInterval(60), now: now), "—")
    }
}

final class ProcessInfoProviderTests: XCTestCase {
    func testResolvesOwnProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = ProcessInfoProvider.executablePath(pid: pid)
        XCTAssertNotNil(path)
        XCTAssertTrue(path?.hasPrefix("/") == true)

        let start = ProcessInfoProvider.startDate(pid: pid)
        XCTAssertNotNil(start)
        // Started in the past, but not absurdly long ago (this test process).
        XCTAssertLessThan(start ?? .distantFuture, Date())
        XCTAssertGreaterThan(start ?? .distantPast, Date().addingTimeInterval(-86_400))
    }

    func testUnknownPidReturnsNil() {
        XCTAssertNil(ProcessInfoProvider.executablePath(pid: 99_999_999))
        XCTAssertNil(ProcessInfoProvider.startDate(pid: 99_999_999))
        XCTAssertNil(ProcessInfoProvider.arguments(pid: 99_999_999))
        XCTAssertNil(ProcessInfoProvider.workingDirectory(pid: 99_999_999))
    }

    func testArgumentsAndCwdForOwnProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier

        let arguments = ProcessInfoProvider.arguments(pid: pid)
        XCTAssertNotNil(arguments)
        XCTAssertFalse(arguments?.first?.isEmpty ?? true)

        let cwd = ProcessInfoProvider.workingDirectory(pid: pid)
        XCTAssertNotNil(cwd)
        XCTAssertTrue(cwd?.hasPrefix("/") == true)
    }
}
