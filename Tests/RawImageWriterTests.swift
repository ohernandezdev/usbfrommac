import XCTest
@testable import UsbFromMac

final class RawImageWriterTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    }

    /// Escribir una imagen reproduce los bytes EXACTOS en el destino (lo que un
    /// `dd` haría sobre el device).
    func testWriteReproducesBytesExactly() throws {
        let src = tempURL("src"); let dst = tempURL("dst")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        // 10 MiB + un resto, para forzar varios bloques de 4 MiB y un bloque parcial.
        let bytes = (0..<(10 * 1024 * 1024 + 777)).map { UInt8($0 & 0xFF) }
        let payload = Data(bytes)
        try payload.write(to: src)

        let writer = RawImageWriter()
        try writer.write(imageURL: src, to: dst)

        XCTAssertEqual(try Data(contentsOf: dst), payload)
    }

    /// El progreso termina en 100% y es monótono creciente.
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

    /// Cancelar a mitad lanza `.cancelled` y no completa.
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
