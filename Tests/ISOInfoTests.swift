import XCTest
@testable import UsbFromMac

final class ISOInfoTests: XCTestCase {

    private func make(bootType: ISOBootType) -> ISOInfo {
        ISOInfo(url: URL(fileURLWithPath: "/tmp/x.iso"),
                sizeBytes: 1_000,
                volumeName: "X",
                isWindowsInstaller: bootType == .windows,
                installWIMSizeBytes: nil,
                usesESD: false,
                newestBootFileDate: nil,
                bootType: bootType)
    }

    // MARK: bootIsSupported deriva de bootType

    func testSupportedBootTypes() {
        XCTAssertTrue(make(bootType: .windows).bootIsSupported)
        XCTAssertTrue(make(bootType: .hybridRaw).bootIsSupported)
    }

    func testUnsupportedBootTypes() {
        XCTAssertFalse(make(bootType: .elToritoOnly).bootIsSupported)
        XCTAssertFalse(make(bootType: .notBootable).bootIsSupported)
    }

    // MARK: Equatable incluye bootType

    func testEqualityDistinguishesBootType() {
        XCTAssertNotEqual(make(bootType: .windows), make(bootType: .hybridRaw))
        XCTAssertEqual(make(bootType: .hybridRaw), make(bootType: .hybridRaw))
    }
}
