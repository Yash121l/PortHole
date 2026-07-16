import XCTest
@testable import PortHole

final class PortDifferTests: XCTestCase {
    private func port(_ number: Int, pid: Int32 = 100, address: String = "*",
                      networkProtocol: NetworkProtocol = .tcp, name: String = "test",
                      path: String? = nil) -> ListeningPort {
        ListeningPort(port: number, networkProtocol: networkProtocol,
                      bindAddress: address, pid: pid, processName: name,
                      executablePath: path, user: "admin", processStartDate: nil)
    }

    func testNoChangesIsEmpty() {
        let scan = [port(3000), port(5432, pid: 200)]
        let diff = PortDiff.between(previous: scan, current: scan)
        XCTAssertTrue(diff.isEmpty)
    }

    func testDetectsAdditionsAndRemovals() {
        let previous = [port(3000), port(5432, pid: 200)]
        let current = [port(3000), port(8080, pid: 300)]

        let diff = PortDiff.between(previous: previous, current: current)
        XCTAssertEqual(diff.added.map(\.port), [8080])
        XCTAssertEqual(diff.removed.map(\.port), [5432])
        XCTAssertTrue(diff.updated.isEmpty)
    }

    func testSamePortDifferentPidIsAddAndRemove() {
        // A dev server restarting keeps the port but changes pid — that's a
        // different socket owner, so it must read as remove + add.
        let diff = PortDiff.between(previous: [port(3000, pid: 100)],
                                    current: [port(3000, pid: 999)])
        XCTAssertEqual(diff.added.count, 1)
        XCTAssertEqual(diff.removed.count, 1)
    }

    func testMetadataChangeIsUpdate() {
        let before = port(3000)
        let after = port(3000, path: "/usr/local/bin/node")

        let diff = PortDiff.between(previous: [before], current: [after])
        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertEqual(diff.updated.map(\.executablePath), ["/usr/local/bin/node"])
    }

    func testEmptyPreviousMarksEverythingAdded() {
        let current = [port(3000), port(5432, pid: 200)]
        let diff = PortDiff.between(previous: [], current: current)
        XCTAssertEqual(diff.added.count, 2)
        XCTAssertTrue(diff.removed.isEmpty)
    }
}
