import XCTest
@testable import UsbFromMac

final class RawImageWriterTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    }

    /// Writing an image reproduces the EXACT bytes at the destination (what a
    /// `dd` would do to the device).
    func testWriteReproducesBytesExactly() throws {
        let src = tempURL("src"); let dst = tempURL("dst")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        // 10 MiB + a remainder, to force several 4 MiB blocks and one partial block.
        let bytes = (0..<(10 * 1024 * 1024 + 777)).map { UInt8($0 & 0xFF) }
        let payload = Data(bytes)
        try payload.write(to: src)

        let writer = RawImageWriter()
        try writer.write(imageURL: src, to: dst)

        XCTAssertEqual(try Data(contentsOf: dst), payload)
    }

    /// Progress ends at 100% and is monotonically increasing.
    func testProgressReachesTotal() throws {
        let src = tempURL("src"); let dst = tempURL("dst")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        let payload = Data((0..<(5 * 1024 * 1024)).map { UInt8($0 & 0xFF) })
        try payload.write(to: src)

        var last: UInt64 = 0
        var total: UInt64 = 0
        try RawImageWriter(blockSize: 1024 * 1024).write(imageURL: src, to: dst, progress: { p in
            XCTAssertGreaterThanOrEqual(p.bytesWritten, last)
            last = p.bytesWritten
            total = p.totalBytes
        })
        XCTAssertEqual(last, UInt64(payload.count))
        XCTAssertEqual(total, UInt64(payload.count))
    }

    /// Cancelling midway throws `.cancelled` and does not complete.
    func testCancellationStops() throws {
        let src = tempURL("src"); let dst = tempURL("dst")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        let payload = Data((0..<(8 * 1024 * 1024)).map { UInt8($0 & 0xFF) })
        try payload.write(to: src)

        var calls = 0
        XCTAssertThrowsError(
            try RawImageWriter(blockSize: 1024 * 1024).write(imageURL: src, to: dst,
                progress: { _ in }, isCancelled: { calls += 1; return calls > 2 })
        ) { error in
            XCTAssertEqual(error as? RawImageWriter.RawWriteError, .cancelled)
        }
    }

    func testMissingSourceThrows() {
        let writer = RawImageWriter()
        XCTAssertThrowsError(try writer.write(imageURL: tempURL("nope"), to: tempURL("dst")))
    }
}
