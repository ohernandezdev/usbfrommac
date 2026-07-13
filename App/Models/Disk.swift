import Foundation

/// Eligible USB disk shown to the user in the list.
///
/// A `Disk` is only built from candidates that have ALREADY passed the
/// `DiskFilter` (whole + external + removable + not the boot disk). By design,
/// it is impossible to represent the internal or boot disk here.
public struct Disk: Identifiable, Equatable, Hashable {

    /// BSD identifier of the whole disk, e.g. "disk4". Used as the `id`.
    public let id: String

    /// "/dev/disk4" — device path for diskutil.
    public var devicePath: String { "/dev/\(id)" }

    /// Mounted volume name, if any.
    public let volumeName: String?

    /// Device model, e.g. "SanDisk Ultra".
    public let model: String?

    /// Size in bytes.
    public let sizeBytes: UInt64

    /// Bus protocol, e.g. "USB".
    public let busProtocol: String?

    public init(id: String,
                volumeName: String?,
                model: String?,
                sizeBytes: UInt64,
                busProtocol: String?) {
        self.id = id
        self.volumeName = volumeName
        self.model = model
        self.sizeBytes = sizeBytes
        self.busProtocol = busProtocol
    }

    /// Human-readable size, e.g. "32 GB".
    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }

    /// Display name: volume > model > BSD identifier.
    public var displayName: String {
        if let v = volumeName, !v.isEmpty { return v }
        if let m = model, !m.isEmpty { return m }
        return id
    }

    // MARK: Size thresholds (RF-3)

    /// Recommended minimum size for Windows 11 (≥ 16 GB).
    public static let recommendedMinimumBytes: UInt64 = 16 * 1_000_000_000

    /// Below this, warn strongly (< 8 GB).
    public static let hardWarnBelowBytes: UInt64 = 8 * 1_000_000_000

    public var meetsRecommendedSize: Bool { sizeBytes >= Disk.recommendedMinimumBytes }
    public var isTooSmall: Bool { sizeBytes < Disk.hardWarnBelowBytes }

    /// `true` if the USB is large enough for a raw (`dd`) write of an `imageBytes`
    /// image. The raw flow (Linux/isohybrid) writes the whole ISO byte for byte: if the
    /// USB is smaller, `dd` fails halfway and leaves the USB broken (A2). This is the
    /// raw flow's only size criterion (unlike Windows, which uses fixed thresholds).
    public func fitsRawImage(ofBytes imageBytes: UInt64) -> Bool {
        sizeBytes >= imageBytes
    }

    /// Size verdict for the build flow, driving the warning shown in the disk list (B4).
    public enum SizeVerdict: Equatable {
        case ok          // large enough
        case recommend   // works, but below the recommended size (Windows only)
        case tooSmall    // unusable / blocking
    }

    /// Flow-dependent size verdict:
    /// - Windows (FAT32 copy): fixed thresholds — 8 GB (hard) / 16 GB (recommended);
    ///   the ISO size is irrelevant because files are copied, not imaged.
    /// - Linux/raw (`dd`): the only criterion is USB >= ISO size; there is no
    ///   "recommended" middle ground — it either fits the image or it doesn't (A2).
    public func sizeVerdict(imageBytes: UInt64, isRawFlow: Bool) -> SizeVerdict {
        if isRawFlow {
            return fitsRawImage(ofBytes: imageBytes) ? .ok : .tooSmall
        }
        if isTooSmall { return .tooSmall }
        if !meetsRecommendedSize { return .recommend }
        return .ok
    }
}
