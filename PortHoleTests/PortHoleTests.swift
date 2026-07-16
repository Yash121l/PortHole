import XCTest
@testable import PortHole

/// Placeholder suite so the test target builds from milestone 1. Real parser
/// and diffing tests land in milestone 6.
final class PortHoleTests: XCTestCase {
    func testBindScopeClassification() {
        XCTAssertEqual(BindScope.classify(address: "127.0.0.1"), .loopback)
        XCTAssertEqual(BindScope.classify(address: "::1"), .loopback)
        XCTAssertEqual(BindScope.classify(address: "*"), .allInterfaces)
        XCTAssertEqual(BindScope.classify(address: "0.0.0.0"), .allInterfaces)
        XCTAssertEqual(BindScope.classify(address: "192.168.1.20"), .specificInterface)
    }
}
