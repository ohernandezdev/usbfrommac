import Foundation

/// POC for the "raw" write (raw / `dd`) of an isohybrid ISO to the disk.
///
/// Mechanics: reads the ISO in blocks and writes them sequentially to the destination,
/// reporting bytes for real progress and allowing a clean cancel (S-5).
/// It's the SAME pattern as `CopyService` but to a single contiguous destination.
///
/// ⚠️ DELIBERATELY ISOLATED (POC): it is NOT yet invoked from the wizard. In production
/// `destination` would be `/dev/rdiskN` opened by the **root helper** (the user app
/// can't write to a block device), after `diskutil unmountDisk`. Here the
/// destination is any URL (in tests, a temporary file) to validate the mechanics and
/// progress without risk. There's NO fallback: if something fails, it throws.
public final class RawImageWriter {

    public struct Progress: Equatable {
        public let bytesWritten: UInt64
        public let totalBytes: UInt64
        public var fraction: Double {
            totalBytes == 0 ? 0 : min(1, Double(bytesWritten) / Double(totalBytes))
        }
    }

    public enum RawWriteError: LocalizedError, Equatable {
        case openSourceFailed(String)
        case openDestinationFailed(String)
        case readFailed(String)
        case writeFailed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .openSourceFailed(let m):      return "Couldn't open the image: \(m)"
            case .openDestinationFailed(let m):  return "Couldn't open the destination: \(m)"
            case .readFailed(let m):             return "Read error: \(m)"
            case .writeFailed(let m):            return "Write error: \(m)"
            case .cancelled:                     return "Write cancelled."
            }
        }
    }

    /// 4 MiB block: balances throughput against progress/cancellation granularity.
    private let blockSize: Int

    public init(blockSize: Int = 4 * 1024 * 1024) {
        self.blockSize = blockSize
    }

    /// Writes `imageURL` byte by byte into `destinationURL`. In production the
    /// destination is a raw device; here the container is required to already exist
    /// (the helper creates the device fd; in tests the file is created).
    public func write(imageURL: URL,
                      to destinationURL: URL,
                      progress: (Progress) -> Void = { _ in },
                      isCancelled: () -> Bool = { false }) throws {

        guard let input = try? FileHandle(forReadingFrom: imageURL) else {
            throw RawWriteError.openSourceFailed(imageURL.lastPathComponent)
        }
        defer { try? input.close() }

        // The destination must exist to open a write handle (in production the
        // device already exists; in tests we create the empty file).
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        }
        guard let output = try? FileHandle(forWritingTo: destinationURL) else {
            throw RawWriteError.openDestinationFailed(destinationURL.lastPathComponent)
        }
        defer { try? output.close() }

        let total = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? NSNumber)??.uint64Value ?? 0
        var written: UInt64 = 0

        while true {
            if isCancelled() { throw RawWriteError.cancelled }
            let chunk: Data
            do {
                chunk = try input.read(upToCount: blockSize) ?? Data()
            } catch {
                throw RawWriteError.readFailed(error.localizedDescription)
            }
            if chunk.isEmpty { break }
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw RawWriteError.writeFailed(error.localizedDescription)
            }
            written += UInt64(chunk.count)
            progress(Progress(bytesWritten: written, totalBytes: total))
        }

        // Guarantees everything reached the medium (critical for a device before ejecting).
        do { try output.synchronize() }
        catch { throw RawWriteError.writeFailed(error.localizedDescription) }
    }
}
