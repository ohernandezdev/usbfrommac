import XCTest
@testable import UsbFromMac

final class ISOBootDetectorTests: XCTestCase {

    // MARK: MBR signature (sector 0, offset 510-511 = 0x55AA)

    func testMBRSignaturePresent() {
        var s = Data(repeating: 0, count: 512)
        s[510] = 0x55; s[511] = 0xAA
        XCTAssertTrue(ISOBootDetector.hasMBRSignature(sector0: s))
    }

    func testMBRSignatureAbsent() {
        let s = Data(repeating: 0, count: 512)
        XCTAssertFalse(ISOBootDetector.hasMBRSignature(sector0: s))
    }

    func testMBRSignatureTooShort() {
        XCTAssertFalse(ISOBootDetector.hasMBRSignature(sector0: Data(repeating: 0, count: 100)))
    }

    // MARK: El Torito descriptor (sector 17)

    func testElToritoRecognized() {
        var b = [UInt8](repeating: 0, count: 64)
        b[0] = 0x00
        b.replaceSubrange(1...5, with: Array("CD001".utf8))
        b[6] = 0x01
        b.replaceSubrange(7..<(7 + 23), with: Array("EL TORITO SPECIFICATION".utf8))
        XCTAssertTrue(ISOBootDetector.hasElTorito(sector17: Data(b)))
    }

    func testElToritoRejectsPlainISO9660() {
        // A normal primary descriptor starts with 0x01 "CD001"; it's not a boot record.
        var b = [UInt8](repeating: 0, count: 64)
        b[0] = 0x01
        b.replaceSubrange(1...5, with: Array("CD001".utf8))
        XCTAssertFalse(ISOBootDetector.hasElTorito(sector17: Data(b)))
    }

    // MARK: Classification (strategy priority)

    func testClassifyWindowsWins() {
        XCTAssertEqual(ISOBootDetector.classify(isWindows: true, hasMBR: true, hasElTorito: true), .windows)
    }

    func testClassifyHybridRawForLinux() {
        // Not Windows but with a hybrid MBR → raw write.
        XCTAssertEqual(ISOBootDetector.classify(isWindows: false, hasMBR: true, hasElTorito: true), .hybridRaw)
    }

    func testClassifyElToritoOnly() {
        XCTAssertEqual(ISOBootDetector.classify(isWindows: false, hasMBR: false, hasElTorito: true), .elToritoOnly)
    }

    func testClassifyNotBootable() {
        XCTAssertEqual(ISOBootDetector.classify(isWindows: false, hasMBR: false, hasElTorito: false), .notBootable)
    }

    func testSupportability() {
        XCTAssertTrue(ISOBootType.windows.isSupportable)
        XCTAssertTrue(ISOBootType.hybridRaw.isSupportable)
        XCTAssertFalse(ISOBootType.elToritoOnly.isSupportable)
        XCTAssertFalse(ISOBootType.notBootable.isSupportable)
    }

    // MARK: End-to-end detection reading a synthetic file

    func testDetectHybridFromSyntheticFile() throws {
        // Build a minimal "ISO": 18 sectors; MBR 0x55AA + El Torito in sector 17.
        var data = Data(count: ISOBootDetector.bootRecordOffset + 64)
        data[510] = 0x55; data[511] = 0xAA
        let off = ISOBootDetector.bootRecordOffset
        data[off] = 0x00
        data.replaceSubrange((off + 1)...(off + 5), with: Array("CD001".utf8))
        data[off + 6] = 0x01
        data.replaceSubrange((off + 7)..<(off + 7 + 23), with: Array("EL TORITO SPECIFICATION".utf8))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poc-\(UUID().uuidString).iso")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(ISOBootDetector.detect(isoAt: url, isWindows: false), .hybridRaw)
        XCTAssertEqual(ISOBootDetector.detect(isoAt: url, isWindows: true), .windows)
    }

    func testDetectNotBootableFromEmptyFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).iso")
        try Data(count: 4096).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ISOBootDetector.detect(isoAt: url, isWindows: false), .notBootable)
    }
}
