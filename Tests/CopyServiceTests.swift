import XCTest
@testable import Flint

final class CopyServiceTests: XCTestCase {

    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for url in temps { try? FileManager.default.removeItem(at: url) }
        temps.removeAll()
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("copytest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temps.append(url)
        return url
    }

    private func write(_ root: URL, _ rel: String, _ content: String) throws {
        let dest = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: dest)
    }

    private func read(_ root: URL, _ rel: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
    }

    private func exists(_ root: URL, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(rel).path)
    }

    private func makeSourceTree() throws -> URL {
        let src = makeTempDir()
        try write(src, "setup.exe", "SETUP")                 // 5 bytes
        try write(src, "sources/install.wim", "THIS_IS_BIG") // 11 bytes — EXCLUDED
        try write(src, "sources/boot.wim", "BOOT")           // 4 bytes
        try write(src, "efi/boot/bootx64.efi", "EFI")        // 3 bytes
        return src
    }

    func testCopiesEverythingExceptInstallWIM() throws {
        let src = try makeSourceTree()
        let dst = makeTempDir()

        try CopyService().copy(from: src, to: dst)

        XCTAssertEqual(read(dst, "setup.exe"), "SETUP")
        XCTAssertEqual(read(dst, "sources/boot.wim"), "BOOT")
        XCTAssertEqual(read(dst, "efi/boot/bootx64.efi"), "EFI")
        // The large file is NEVER copied (RF-7).
        XCTAssertFalse(exists(dst, "sources/install.wim"))
    }

    func testProgressTotalExcludesTheExcludedFile() throws {
        let src = try makeSourceTree()
        let dst = makeTempDir()

        var last: CopyProgress?
        try CopyService().copy(from: src, to: dst, progress: { last = $0 })

        // 5 + 4 + 3 = 12 bytes (the 11-byte install.wim does NOT count).
        XCTAssertEqual(last?.totalBytes, 12)
        XCTAssertEqual(last?.bytesCopied, 12)
        XCTAssertEqual(last?.fraction, 1.0)
    }

    func testCustomExclusionSet() throws {
        let src = try makeSourceTree()
        let dst = makeTempDir()

        // Also exclude boot.wim.
        try CopyService().copy(from: src, to: dst,
                               excluding: ["sources/install.wim", "sources/boot.wim"])

        XCTAssertTrue(exists(dst, "setup.exe"))
        XCTAssertFalse(exists(dst, "sources/install.wim"))
        XCTAssertFalse(exists(dst, "sources/boot.wim"))
    }

    func testExclusionIsCaseInsensitive() throws {
        let src = makeTempDir()
        try write(src, "Sources/Install.WIM", "BIG")
        try write(src, "setup.exe", "S")
        let dst = makeTempDir()

        try CopyService().copy(from: src, to: dst, excluding: ["sources/install.wim"])

        XCTAssertFalse(exists(dst, "Sources/Install.WIM"))
        XCTAssertTrue(exists(dst, "setup.exe"))
    }

    func testCancellationThrowsCleanly() throws {
        let src = try makeSourceTree()
        let dst = makeTempDir()

        XCTAssertThrowsError(try CopyService().copy(from: src, to: dst, isCancelled: { true })) { error in
            XCTAssertEqual(error as? CopyServiceError, .cancelled)
        }
    }

    func testRelativePathHelper() {
        let base = URL(fileURLWithPath: "/Volumes/CCCOMA")
        XCTAssertEqual(CopyService.relativePath(of: URL(fileURLWithPath: "/Volumes/CCCOMA/sources/install.wim"), base: base),
                       "sources/install.wim")
        XCTAssertEqual(CopyService.relativePath(of: URL(fileURLWithPath: "/Volumes/CCCOMA/setup.exe"), base: base),
                       "setup.exe")
    }
}
