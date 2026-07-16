import XCTest
@testable import PortHole

/// Fixtures below are captured from real `lsof -nPw -i… -FpcuLPn` runs on
/// macOS, trimmed for the case under test.
final class LsofParserTests: XCTestCase {
    // MARK: Record parsing

    func testParsesTCPListeners() {
        let fixture = """
        p874
        cControlCenter
        u501
        Ladmin
        f9
        PTCP
        n*:7000
        f11
        PTCP
        n*:5000
        p75323
        cnode
        u501
        Ladmin
        f29
        PTCP
        n[::1]:5173
        """

        let records = LsofParser.records(from: fixture)
        XCTAssertEqual(records.count, 2)

        XCTAssertEqual(records[0].pid, 874)
        XCTAssertEqual(records[0].command, "ControlCenter")
        XCTAssertEqual(records[0].uid, 501)
        XCTAssertEqual(records[0].loginName, "admin")
        XCTAssertEqual(records[0].sockets.count, 2)
        XCTAssertEqual(records[0].sockets[0], LsofRecord.Socket(protocolName: "TCP", rawName: "*:7000"))

        XCTAssertEqual(records[1].pid, 75323)
        XCTAssertEqual(records[1].command, "node")
        XCTAssertEqual(records[1].sockets, [LsofRecord.Socket(protocolName: "TCP", rawName: "[::1]:5173")])
    }

    func testCommandNamesMayContainSpaces() {
        let fixture = """
        p1179
        cSlack Helper
        u501
        Ladmin
        f24
        PUDP
        n*:*
        """

        let records = LsofParser.records(from: fixture)
        XCTAssertEqual(records.first?.command, "Slack Helper")
    }

    func testEmptyOutputYieldsNoRecords() {
        XCTAssertTrue(LsofParser.records(from: "").isEmpty)
        XCTAssertTrue(LsofParser.records(from: "\n\n").isEmpty)
    }

    // MARK: Listening-port extraction

    func testCollapsesDualStackDuplicates() {
        // rapportd listens on *:50266 over both IPv4 and IPv6 — one row.
        let fixture = """
        p779
        crapportd
        u501
        Ladmin
        f10
        PTCP
        n*:50266
        f13
        PTCP
        n*:50266
        """

        let ports = LsofParser.listeningPorts(from: LsofParser.records(from: fixture))
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 50266)
        XCTAssertEqual(ports[0].bindAddress, "*")
        XCTAssertEqual(ports[0].processName, "rapportd")
        XCTAssertEqual(ports[0].user, "admin")
        XCTAssertEqual(ports[0].bindScope, .allInterfaces)
    }

    func testSkipsWildcardUDPAndConnectedSockets() {
        let fixture = """
        p795
        cidentityservicesd
        u501
        Ladmin
        f9
        PUDP
        n*:*
        f12
        PUDP
        n10.0.0.5:123->17.253.2.125:123
        f18
        PUDP
        n*:5353
        """

        let ports = LsofParser.listeningPorts(from: LsofParser.records(from: fixture))
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 5353)
        XCTAssertEqual(ports[0].networkProtocol, .udp)
    }

    func testParseEndpointVariants() throws {
        let wildcard = try XCTUnwrap(LsofParser.parseEndpoint("*:3000"))
        XCTAssertEqual(wildcard.address, "*")
        XCTAssertEqual(wildcard.port, 3000)

        let loopback4 = try XCTUnwrap(LsofParser.parseEndpoint("127.0.0.1:5432"))
        XCTAssertEqual(loopback4.address, "127.0.0.1")
        XCTAssertEqual(loopback4.port, 5432)

        let loopback6 = try XCTUnwrap(LsofParser.parseEndpoint("[::1]:8080"))
        XCTAssertEqual(loopback6.address, "::1")
        XCTAssertEqual(loopback6.port, 8080)

        let scoped = try XCTUnwrap(LsofParser.parseEndpoint("[fe80::1%lo0]:9000"))
        XCTAssertEqual(scoped.address, "fe80::1%lo0")
        XCTAssertEqual(scoped.port, 9000)

        let listenSuffix = try XCTUnwrap(LsofParser.parseEndpoint("*:8080 (LISTEN)"))
        XCTAssertEqual(listenSuffix.port, 8080)

        XCTAssertNil(LsofParser.parseEndpoint("*:*"))
        XCTAssertNil(LsofParser.parseEndpoint("10.0.0.5:123->1.2.3.4:123"))
        XCTAssertNil(LsofParser.parseEndpoint("no-port-here"))
    }

    func testMalformedFieldLinesAreIgnored() {
        let fixture = """
        pnot-a-pid
        cghost
        f1
        PTCP
        n*:1234
        p500
        creal
        f2
        PTCP
        n*:4321
        """

        let records = LsofParser.records(from: fixture)
        // The record with an unparseable pid is dropped entirely.
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].pid, 500)
        XCTAssertEqual(records[0].command, "real")
    }
}
