import XCTest
@testable import UsbFromMac

final class ISOServiceTests: XCTestCase {

    private var tempFiles: [URL] = []

    override func tearDownWithError() throws {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles.removeAll()
    }

    private func writeTemp(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("isotest-\(UUID().uuidString).bin")
        try content.data(using: .utf8)!.write(to: url)
        tempFiles.append(url)
        return url
    }

    // MARK: SHA-256 (CA-3) — vectores conocidos, valida el streaming

    func testSHA256OfKnownVectorABC() throws {
        let url = try writeTemp("abc")
        let hash = try ISOService().sha256(of: url)
        XCTAssertEqual(hash, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testSHA256OfEmptyFile() throws {
        let url = try writeTemp("")
        let hash = try ISOService().sha256(of: url)
        XCTAssertEqual(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testSHA256ReportsProgressToOne() throws {
        let url = try writeTemp("hola mundo")
        var last = 0.0
        _ = try ISOService().sha256(of: url, progress: { last = $0 })
        XCTAssertEqual(last, 1.0, accuracy: 0.0001)
    }

    func testSHA256CancellationThrows() throws {
        let url = try writeTemp("abc")
        XCTAssertThrowsError(try ISOService().sha256(of: url, isCancelled: { true })) { error in
            XCTAssertEqual(error as? ISOServiceError, .cancelled)
        }
    }

    func testHashesMatchIsCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(ISOService.hashesMatch("  BA7816BF ", "ba7816bf"))
        XCTAssertFalse(ISOService.hashesMatch("abc", "abd"))
    }

    // MARK: Secure Boot (S-7) — clasificador puro

    func testSecureBootClassifyModern() {
        let recent = SecureBootConcern.cutoff2023.addingTimeInterval(86_400)
        XCTAssertEqual(SecureBootConcern.classify(newestBootFileDate: recent), .likelyModern)
    }

    func testSecureBootClassifyOutdated() {
        let old = SecureBootConcern.cutoff2023.addingTimeInterval(-86_400)
        XCTAssertEqual(SecureBootConcern.classify(newestBootFileDate: old), .possiblyOutdated)
    }

    func testSecureBootClassifyUnknownWhenNoDate() {
        XCTAssertEqual(SecureBootConcern.classify(newestBootFileDate: nil), .unknown)
    }

    // MARK: Lógica de split FAT32

    func testRequiresSplitWhenWIMOverFourGiB() {
        let info = makeISOInfo(wimSize: ISOInfo.fat32FileLimit + 1)
        XCTAssertTrue(info.requiresWIMSplit)
    }

    func testNoSplitWhenWIMUnderFourGiB() {
        let info = makeISOInfo(wimSize: 3_500_000_000)
        XCTAssertFalse(info.requiresWIMSplit)
    }

    func testNoSplitWhenNoWIM() {
        let info = makeISOInfo(wimSize: nil)
        XCTAssertFalse(info.requiresWIMSplit)
    }

    // MARK: Normalización de dev node

    func testWholeDevNodeStripsPartition() {
        XCTAssertEqual(ISOService.wholeDevNode(from: "/dev/disk7s1"), "/dev/disk7")
        XCTAssertEqual(ISOService.wholeDevNode(from: "/dev/disk12"), "/dev/disk12")
    }

    // MARK: Helpers

    private func makeISOInfo(wimSize: UInt64?) -> ISOInfo {
        ISOInfo(url: URL(fileURLWithPath: "/tmp/x.iso"), sizeBytes: 5_000_000_000,
                volumeName: "CCCOMA", isWindowsInstaller: true,
                installWIMSizeBytes: wimSize, usesESD: false, newestBootFileDate: nil)
    }
}
