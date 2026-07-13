import Foundation

/// Raw material of a disk, exactly as reported by DiskArbitration
/// (or a fake in tests). It is deliberately "dumb": it makes no eligibility
/// decisions, it only carries the properties the `DiskFilter` needs to decide.
///
/// Separating this type from the real source (DiskArbitration/IOKit) is what
/// lets us test disk filtering WITHOUT hardware: tests inject candidates
/// (including the internal/boot disk) and verify they never pass the filter.
public struct DiskCandidate: Equatable, Hashable {

    /// BSD identifier, e.g. "disk4" (whole) or "disk4s1" (partition).
    public let bsdName: String

    /// `true` if it's a WHOLE physical disk (kDADiskDescriptionMediaWholeKey),
    /// not a partition or a synthetic volume.
    public let isWholeDisk: Bool

    /// `true` if the device is internal (kDADiskDescriptionDeviceInternalKey).
    /// Internal devices are ALWAYS excluded.
    public let isInternal: Bool

    /// `true` if the media is removable (kDADiskDescriptionMediaRemovableKey).
    public let isRemovable: Bool

    /// `true` if the media is ejectable (kDADiskDescriptionMediaEjectableKey).
    /// USB flash drives usually report ejectable=true.
    public let isEjectable: Bool

    /// Media size in bytes (kDADiskDescriptionMediaSizeKey).
    public let sizeBytes: UInt64

    /// Volume name, if one is mounted (kDADiskDescriptionVolumeNameKey).
    public let volumeName: String?

    /// Device model (kDADiskDescriptionDeviceModelKey), e.g. "SanDisk Ultra".
    public let deviceModel: String?

    /// Bus protocol (kDADiskDescriptionDeviceProtocolKey), e.g. "USB".
    public let busProtocol: String?

    public init(bsdName: String,
                isWholeDisk: Bool,
                isInternal: Bool,
                isRemovable: Bool,
                isEjectable: Bool,
                sizeBytes: UInt64,
                volumeName: String?,
                deviceModel: String?,
                busProtocol: String?) {
        self.bsdName = bsdName
        self.isWholeDisk = isWholeDisk
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.sizeBytes = sizeBytes
        self.volumeName = volumeName
        self.deviceModel = deviceModel
        self.busProtocol = busProtocol
    }

    /// Identifier of the WHOLE disk this candidate belongs to.
    /// "disk4s1" -> "disk4". For whole candidates it returns its own name.
    public var wholeDiskBSDName: String {
        DiskCandidate.wholeDiskBSDName(from: bsdName)
    }

    /// "disk4s1s2" -> "disk4". Returns the original string if it doesn't match the pattern.
    public static func wholeDiskBSDName(from bsd: String) -> String {
        guard bsd.hasPrefix("disk") else { return bsd }
        let digits = bsd.dropFirst(4).prefix { $0.isNumber }
        guard !digits.isEmpty else { return bsd }
        return "disk" + digits
    }
}
