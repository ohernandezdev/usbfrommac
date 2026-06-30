import Foundation

public enum WimConstants {
    /// Target size of each part, in MiB. It's a TARGET, not a hard cap:
    /// a resource isn't split across parts, hence 3800 (not 4096) to leave
    /// headroom under FAT32's 4 GiB ceiling (verified: wimlib LIMITATIONS).
    public static let partSizeMiB = 3800

    /// The first part MUST be named install.swm; wimlib generates install2.swm,
    /// install3.swm… automatically. Windows Setup reassembles them on its own in sources/.
    public static let firstSWMName = "install.swm"

    /// Name of the bundled binary.
    public static let binaryName = "wimlib-imagex"
}

/// Abstraction over the WIM splitter: lets you swap the implementation (binary
/// as a subprocess ↔ linked libwim) without touching the rest of the app.
public protocol WimSplitting {
    func split(wim: URL,
               intoSourcesDir: URL,
               partSizeMiB: Int,
               progress: (Double) -> Void,
               isCancelled: () -> Bool) throws
}

/// Splits `sources/install.wim` into `.swm` parts with `wimlib-imagex` (RF-8).
///
/// The binary runs as a subprocess (the app is open source / GPLv3, so there's
/// no license conflict). There's NO fallback to a system wimlib: if the binary
/// isn't bundled, it fails with a clear error (Phase 8 manual config).
public final class WimService: WimSplitting {

    public enum WimError: LocalizedError, Equatable {
        case binaryNotBundled
        case splitFailed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .binaryNotBundled:
                return loc("error.wim.binaryNotBundled")
            case .splitFailed(let m):
                return loc("error.wim.splitFailed \(m)")
            case .cancelled:
                return loc("error.wim.cancelled")
            }
        }
    }

    private let binaryURL: URL?

    /// Defaults to the bundled binary. In development/tests an explicit path can be
    /// injected (e.g. the Homebrew one). This is explicit configuration,
    /// not a silent fallback.
    public init(binaryURL: URL? = WimService.bundledBinaryURL()) {
        self.binaryURL = binaryURL
    }

    public static func bundledBinaryURL() -> URL? {
        Bundle.main.url(forResource: WimConstants.binaryName, withExtension: nil)
    }

    public func split(wim: URL,
                      intoSourcesDir: URL,
                      partSizeMiB: Int = WimConstants.partSizeMiB,
                      progress: (Double) -> Void = { _ in },
                      isCancelled: () -> Bool = { false }) throws {

        guard let binary = binaryURL else { throw WimError.binaryNotBundled }

        let firstSWM = intoSourcesDir.appendingPathComponent(WimConstants.firstSWMName)
        let (launch, args) = Self.splitCommand(binary: binary, wim: wim,
                                               firstSWM: firstSWM, partSizeMiB: partSizeMiB)

        let wimSize = (try? FileManager.default.attributesOfItem(atPath: wim.path)[.size] as? NSNumber)??.uint64Value ?? 0

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw WimError.splitFailed(error.localizedDescription)
        }

        // Robust progress: measure what's written to the .swm files vs the wim size.
        // Doesn't depend on wimlib's output format (which may change).
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                try? Self.cleanupSWM(in: intoSourcesDir)
                throw WimError.cancelled
            }
            if wimSize > 0 {
                let written = Self.writtenSWMBytes(in: intoSourcesDir)
                progress(min(0.99, Double(written) / Double(wimSize)))
            }
            usleep(200_000) // 200 ms
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try? Self.cleanupSWM(in: intoSourcesDir)
            throw WimError.splitFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        progress(1.0)
    }

    // MARK: - Pure logic (testable without the binary)

    /// Builds the command: `wimlib-imagex split <wim> <install.swm> <partSize>`.
    public static func splitCommand(binary: URL, wim: URL, firstSWM: URL, partSizeMiB: Int) -> (launch: String, args: [String]) {
        (binary.path, ["split", wim.path, firstSWM.path, String(partSizeMiB)])
    }

    /// Name of part number `index` (1 → install.swm, 2 → install2.swm…).
    public static func expectedSWMName(index: Int) -> String {
        index <= 1 ? "install.swm" : "install\(index).swm"
    }

    /// Estimate (lower bound) of the number of parts: ceil(size / part).
    /// The actual count may be equal or one more (a resource isn't split across parts).
    public static func minimumPartCount(wimSizeBytes: UInt64, partSizeMiB: Int) -> Int {
        guard wimSizeBytes > 0, partSizeMiB > 0 else { return 0 }
        let partBytes = UInt64(partSizeMiB) * 1024 * 1024
        return Int((wimSizeBytes + partBytes - 1) / partBytes)
    }

    // MARK: - Private

    private static func writtenSWMBytes(in dir: URL) -> UInt64 {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items
            .filter { isSWM($0) }
            .reduce(0) { acc, url in
                acc + UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
    }

    private static func cleanupSWM(in dir: URL) throws {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items where isSWM(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func isSWM(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().hasPrefix("install")
            && url.pathExtension.lowercased() == "swm"
    }
}
