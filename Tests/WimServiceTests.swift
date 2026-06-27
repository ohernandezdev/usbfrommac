import XCTest
@testable import UsbFromMac

final class WimServiceTests: XCTestCase {

    // MARK: Constantes verificadas (Investigación)

    func testPartSizeIs3800MiB() {
        XCTAssertEqual(WimConstants.partSizeMiB, 3800)
    }

    func testFirstFragmentIsInstallSWM() {
        XCTAssertEqual(WimConstants.firstSWMName, "install.swm")
    }

    // MARK: Nombres de fragmentos (convención obligatoria de Windows Setup)

    func testExpectedSWMNaming() {
        XCTAssertEqual(WimService.expectedSWMName(index: 1), "install.swm")
        XCTAssertEqual(WimService.expectedSWMName(index: 2), "install2.swm")
        XCTAssertEqual(WimService.expectedSWMName(index: 3), "install3.swm")
        XCTAssertEqual(WimService.expectedSWMName(index: 0), "install.swm")
    }

    // MARK: Cálculo de fragmentos (CA-6)

    func testMinimumPartCount() {
        let gib: UInt64 = 1024 * 1024 * 1024
        // ~5 GiB con partes de 3800 MiB -> 2 fragmentos.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 5 * gib, partSizeMiB: 3800), 2)
        // 3700 MiB -> 1 fragmento.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 3700 * 1024 * 1024, partSizeMiB: 3800), 1)
        // Justo en el límite de una parte (3800 MiB) -> 1.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 3800 * 1024 * 1024, partSizeMiB: 3800), 1)
        // Un byte más -> 2.
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 3800 * 1024 * 1024 + 1, partSizeMiB: 3800), 2)
    }

    func testMinimumPartCountEdgeCases() {
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 0, partSizeMiB: 3800), 0)
        XCTAssertEqual(WimService.minimumPartCount(wimSizeBytes: 1000, partSizeMiB: 0), 0)
    }

    // MARK: Construcción del comando

    func testSplitCommand() {
        let binary = URL(fileURLWithPath: "/Applications/UsbFromMac.app/Contents/Resources/wimlib-imagex")
        let wim = URL(fileURLWithPath: "/Volumes/CCCOMA/sources/install.wim")
        let firstSWM = URL(fileURLWithPath: "/Volumes/WIN11/sources/install.swm")

        let cmd = WimService.splitCommand(binary: binary, wim: wim, firstSWM: firstSWM, partSizeMiB: 3800)

        XCTAssertEqual(cmd.launch, binary.path)
        XCTAssertEqual(cmd.args, ["split",
                                  "/Volumes/CCCOMA/sources/install.wim",
                                  "/Volumes/WIN11/sources/install.swm",
                                  "3800"])
    }

    // MARK: Sin fallback (CLAUDE.md) — si no hay binario, error claro

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
