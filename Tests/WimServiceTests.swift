import XCTest
@testable import Flint

final class WimServiceTests: XCTestCase {

    // MARK: Verified constants (Research)

    func testPartSizeIs3800MiB() {
        XCTAssertEqual(WimConstants.partSizeMiB, 3800)
    }

    func testFirstFragmentIsInstallSWM() {
        XCTAssertEqual(WimConstants.firstSWMName, "install.swm")
    }

    // MARK: Fragment names (mandatory Windows Setup convention)

    func testExpectedSWMNaming() {
        XCTAssertEqual(WimService.expectedSWMName(index: 1), "install.swm")
        XCTAssertEqual(WimService.expectedSWMName(index: 2), "install2.swm")
        XCTAssertEqual(WimService.expectedSWMName(index: 3), "install3.swm")
        XCTAssertEqual(WimService.expectedSWMName(index: 0), "install.swm")
    }

    // MARK: Fragment count calculation (CA-6)

    func testMinimumPartCount() {
        let gib: UInt64 = 1024 * 1024 * 1024
        // ~5 GiB with 3800 MiB parts -> 2 fragments.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 5 * gib, partSizeMiB: 3800), 2)
        // 3700 MiB -> 1 fragment.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 3700 * 1024 * 1024, partSizeMiB: 3800), 1)
        // Exactly at the limit of one part (3800 MiB) -> 1.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 3800 * 1024 * 1024, partSizeMiB: 3800), 1)
        // One byte more -> 2.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 3800 * 1024 * 1024 + 1, partSizeMiB: 3800), 2)
    }

    func testMinimumPartCountEdgeCases() {
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 0, partSizeMiB: 3800), 0)
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 1000, partSizeMiB: 0), 0)
    }

    // MARK: Command construction

    func testSplitCommand() {
        let binary = URL(fileURLWithPath: "/Applications/Flint.app/Contents/Resources/wimlib-imagex")
        let wim = URL(fileURLWithPath: "/Volumes/CCCOMA/sources/install.wim")
        let firstSWM = URL(fileURLWithPath: "/Volumes/WIN11/sources/install.swm")

        let cmd = WimService.splitCommand(binary: binary, wim: wim, firstSWM: firstSWM, partSizeMiB: 3800)

        XCTAssertEqual(cmd.launch, binary.path)
        XCTAssertEqual(cmd.args, ["split",
                                  "/Volumes/CCCOMA/sources/install.wim",
                                  "/Volumes/WIN11/sources/install.swm",
                                  "3800"])
    }

    // MARK: No fallback (CLAUDE.md) — if there's no binary, a clear error

    func testSplitThrowsWhenBinaryNotBundled() {
        let service = WimService(binaryURL: nil)
        XCTAssertThrowsError(
            try service.split(wim: URL(fileURLWithPath: "/tmp/install.wim"),
                              intoSourcesDir: URL(fileURLWithPath: "/tmp"))
        ) { error in
            XCTAssertEqual(error as? WimService.WimError, .binaryNotBundled)
        }
    }
}
