import Foundation
import CryptoKit

/// An ISO already mounted by hdiutil.
public struct MountedISO: Equatable {
    public let mountPoint: URL    // /Volumes/CCCOMA_…
    public let deviceNode: String // /dev/diskN (whole) for detach
}

public enum ISOServiceError: LocalizedError, Equatable {
    case attachFailed(String)
    case notMountable
    case detachFailed(String)
    case readFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .attachFailed(let m): return loc("error.iso.attachFailed \(m)")
        case .notMountable: return loc("error.iso.notMountable")
        case .detachFailed(let m): return loc("error.iso.detachFailed \(m)")
        case .readFailed(let m): return loc("error.iso.readFailed \(m)")
        case .cancelled: return loc("error.iso.cancelled")
        }
    }
}

/// Mounts/unmounts the ISO, inspects it, and computes its SHA-256.
/// Everything runs as the user (no root required).
public final class ISOService {

    private let hdiutil = "/usr/bin/hdiutil"

    public init() {}

    // MARK: - Mounting

    /// Mounts the ISO read-only and without opening Finder (RF-6).
    public func attach(_ iso: URL) throws -> MountedISO {
        let r = Subprocess.run(hdiutil, ["attach", "-nobrowse", "-readonly", "-plist", iso.path])
        guard r.succeeded else { throw ISOServiceError.attachFailed(r.errorMessage) }

        guard let plist = try? PropertyListSerialization.propertyList(from: r.stdout, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw ISOServiceError.notMountable
        }
        // Find the entity with a mount point.
        guard let mounted = entities.first(where: { ($0["mount-point"] as? String)?.isEmpty == false }),
              let mountPath = mounted["mount-point"] as? String else {
            throw ISOServiceError.notMountable
        }
        let devEntry = (mounted["dev-entry"] as? String) ?? ""
        let whole = ISOService.wholeDevNode(from: devEntry)
        return MountedISO(mountPoint: URL(fileURLWithPath: mountPath), deviceNode: whole)
    }

    /// Unmounts the ISO. Guarantees cleanup even if the normal path fails (S-5).
    public func detach(_ mounted: MountedISO) throws {
        let r = Subprocess.run(hdiutil, ["detach", mounted.mountPoint.path])
        if r.succeeded { return }
        // Forced retry before giving up.
        let forced = Subprocess.run(hdiutil, ["detach", "-force", mounted.mountPoint.path])
        if !forced.succeeded {
            throw ISOServiceError.detachFailed(forced.errorMessage)
        }
    }

    // MARK: - Inspection

    public func inspect(_ mounted: MountedISO, isoURL: URL) -> ISOInfo {
        let fm = FileManager.default
        let mp = mounted.mountPoint

        func exists(_ rel: String) -> Bool { fm.fileExists(atPath: mp.appendingPathComponent(rel).path) }
        func size(_ rel: String) -> UInt64? {
            let p = mp.appendingPathComponent(rel).path
            guard let attrs = try? fm.attributesOfItem(atPath: p) else { return nil }
            return (attrs[.size] as? NSNumber)?.uint64Value
        }
        func modDate(_ rel: String) -> Date? {
            let p = mp.appendingPathComponent(rel).path
            guard let attrs = try? fm.attributesOfItem(atPath: p) else { return nil }
            return attrs[.modificationDate] as? Date
        }

        let hasSetup = exists("setup.exe")
        let hasSources = exists("sources")
        let wimSize = size("sources/install.wim")
        let hasWIM = wimSize != nil
        let hasESD = exists("sources/install.esd")
        let isWindows = hasSetup && hasSources && (hasWIM || hasESD)

        // Candidate boot files (an age proxy for Secure Boot).
        let bootCandidates = ["efi/boot/bootx64.efi", "boot/bootx64.efi", "bootmgr.efi", "bootmgr"]
        let newestBoot = bootCandidates.compactMap(modDate).max()

        let isoSize = (try? fm.attributesOfItem(atPath: isoURL.path)[.size] as? NSNumber)??.uint64Value ?? 0

        // Classify the boot strategy by reading the ISO header (MBR/El Torito).
        let bootType = ISOBootDetector.detect(isoAt: isoURL, isWindows: isWindows)

        return ISOInfo(
            url: isoURL,
            sizeBytes: isoSize,
            volumeName: mp.lastPathComponent,
            isWindowsInstaller: isWindows,
            installWIMSizeBytes: wimSize,
            usesESD: hasESD && !hasWIM,
            newestBootFileDate: newestBoot,
            bootType: bootType
        )
    }

    // MARK: - SHA-256 (streaming, cancelable)

    /// Computes the file's SHA-256 in streaming mode (doesn't load the ISO into RAM).
    /// `progress` receives 0…1; `isCancelled` allows aborting (S-4 of the flow).
    public func sha256(of url: URL,
                       progress: ((Double) -> Void)? = nil,
                       isCancelled: () -> Bool = { false }) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ISOServiceError.readFailed("Couldn't open \(url.lastPathComponent).")
        }
        defer { try? handle.close() }

        let total = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.uint64Value ?? 0
        var hasher = SHA256()
        var readBytes: UInt64 = 0
        let chunkSize = 4 * 1024 * 1024

        while true {
            if isCancelled() { throw ISOServiceError.cancelled }
            let data: Data
            do {
                data = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                throw ISOServiceError.readFailed(error.localizedDescription)
            }
            if data.isEmpty { break }
            hasher.update(data: data)
            readBytes += UInt64(data.count)
            if total > 0 { progress?(Double(readBytes) / Double(total)) }
        }

        return Self.hexString(hasher.finalize())
    }

    /// Normalizes a hash for comparison (lowercase, no spaces) — CA-3.
    public static func normalizedHash(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func hashesMatch(_ a: String, _ b: String) -> Bool {
        normalizedHash(a) == normalizedHash(b)
    }

    // MARK: - Private

    private static func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// "/dev/disk7s1" -> "/dev/disk7".
    static func wholeDevNode(from devEntry: String) -> String {
        guard let range = devEntry.range(of: "disk[0-9]+", options: .regularExpression) else { return devEntry }
        return "/dev/" + String(devEntry[range])
    }
}
