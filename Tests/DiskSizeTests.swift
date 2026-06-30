import XCTest
@testable import UsbFromMac

/// USB size rules per build flow.
///
/// - Windows (FAT32 copy): fixed thresholds 8 GB (hard) / 16 GB (recommended).
/// - Linux/raw (`dd`): the ONLY criterion is USB >= ISO size; a smaller USB makes
///   `dd` fail halfway and leaves the USB broken (A2).
final class DiskSizeTests: XCTestCase {

    private func disk(_ size: UInt64) -> Disk {
        Disk(id: "disk4", volumeName: nil, model: "USB", sizeBytes: size, busProtocol: "USB")
    }

    // MARK: A2 — the USB must fit the whole raw image

    func testFitsRawImageWhenLargerThanISO() {
        XCTAssertTrue(disk(8_000_000_000).fitsRawImage(ofBytes: 5_000_000_000))
    }

    func testFitsRawImageWhenExactlyISOSize() {
        // Edge: a USB exactly the ISO size still fits (>=, not >).
        XCTAssertTrue(disk(5_000_000_000).fitsRawImage(ofBytes: 5_000_000_000))
    }

    func testDoesNotFitRawImageWhenSmallerThanISO() {
        XCTAssertFalse(disk(4_000_000_000).fitsRawImage(ofBytes: 5_000_000_000))
    }

    // MARK: B4 — flow-dependent size verdict

    // Windows flow: fixed thresholds, the ISO size is irrelevant.
    func testWindowsVerdictTooSmallUnder8GB() {
        XCTAssertEqual(disk(7_000_000_000).sizeVerdict(imageBytes: 0, isRawFlow: false), .tooSmall)
    }

    func testWindowsVerdictRecommendBetween8And16GB() {
        XCTAssertEqual(disk(12_000_000_000).sizeVerdict(imageBytes: 0, isRawFlow: false), .recommend)
    }

    func testWindowsVerdictOKAtOrAbove16GB() {
        XCTAssertEqual(disk(16_000_000_000).sizeVerdict(imageBytes: 0, isRawFlow: false), .ok)
    }

    // Raw flow: the only criterion is USB >= ISO; there is no "recommend" state.
    func testRawVerdictOKWhenFitsISO() {
        // A 4 GB USB that fits a 3 GB ISO is fine, even though Windows would warn.
        XCTAssertEqual(disk(4_000_000_000).sizeVerdict(imageBytes: 3_000_000_000, isRawFlow: true), .ok)
    }

    func testRawVerdictTooSmallWhenBelowISO() {
        XCTAssertEqual(disk(4_000_000_000).sizeVerdict(imageBytes: 5_000_000_000, isRawFlow: true), .tooSmall)
    }

    func testRawVerdictNeverRecommends() {
        // A large USB that fits a small ISO is OK, not "recommend".
        XCTAssertEqual(disk(64_000_000_000).sizeVerdict(imageBytes: 2_000_000_000, isRawFlow: true), .ok)
    }
}
