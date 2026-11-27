import XCTest
@testable import DisplayCore

final class DisplayIdentityPolicyTests: XCTestCase {
    func testOfflineZeroUUIDFallsBackToKnownPhysicalIdentity() {
        let real = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
        XCTAssertEqual(DisplayIdentityPolicy.stableUUID(["00000000-0000-0000-0000-000000000000", nil, real]), real)
        XCTAssertNil(DisplayIdentityPolicy.stableUUID([nil, "", "invalid", "00000000-0000-0000-0000-000000000000"]))
    }
}
