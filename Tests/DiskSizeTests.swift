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
}
