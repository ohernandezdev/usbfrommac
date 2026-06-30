import Foundation

/// Result of inspecting a mounted ISO.
public struct ISOInfo: Equatable {

    public let url: URL
    public let sizeBytes: UInt64
    public let volumeName: String?

    /// `true` if it looks like a Windows installer (setup + sources folder + image).
    public let isWindowsInstaller: Bool

    /// Size of `sources/install.wim` if it exists.
    public let installWIMSizeBytes: UInt64?

    /// `true` if the image is `install.esd` (usually fits on FAT32 without splitting).
    public let usesESD: Bool

    /// Most recent modification date among the EFI boot files.
    /// Used as a proxy for the Secure Boot 2023 warning (S-7).
    public let newestBootFileDate: Date?

    /// How this ISO must be written for the USB to boot (determines the
    /// strategy: FAT32 copy for Windows vs. raw write for isohybrids).
    public let bootType: ISOBootType

    public init(url: URL, sizeBytes: UInt64, volumeName: String?,
                isWindowsInstaller: Bool, installWIMSizeBytes: UInt64?,
                usesESD: Bool, newestBootFileDate: Date?,
                bootType: ISOBootType) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.volumeName = volumeName
        self.isWindowsInstaller = isWindowsInstaller
        self.installWIMSizeBytes = installWIMSizeBytes
        self.usesESD = usesESD
        self.newestBootFileDate = newestBootFileDate
        self.bootType = bootType
    }

    /// `true` if the app can create a bootable USB from this ISO (Windows or isohybrid).
    public var bootIsSupported: Bool { bootType.isSupportable }

    /// Hard FAT32 per-file limit: 4 GiB.
    public static let fat32FileLimit: UInt64 = 4 * 1024 * 1024 * 1024

    /// `true` if `install.wim` exceeds FAT32 and must be split with wimlib (RF-8).
    public var requiresWIMSplit: Bool {
        (installWIMSizeBytes ?? 0) > ISOInfo.fat32FileLimit
    }

    /// Secure Boot risk classification based on the date of the boot files.
    public var secureBootConcern: SecureBootConcern {
        SecureBootConcern.classify(newestBootFileDate: newestBootFileDate)
    }
}

/// Secure Boot compatibility warning (S-7).
///
/// The "PCA 2011" certificate is revoked in 2026; only ISOs signed with
/// "Windows UEFI CA 2023" are guaranteed to boot with Secure Boot. Detecting the
/// bootloader's certificate requires parsing PE signatures, so we use an
/// informational HEURISTIC: the date of the boot files. It only informs,
/// never blocks.
public enum SecureBootConcern: Equatable {
    /// Boot files are recent → probably the 2023 cert.
    case likelyModern
    /// Old boot files → may not boot with Secure Boot ON.
    case possiblyOutdated
    /// Couldn't determine the date.
    case unknown

    /// Cutoff date: from here on we assume the 2023 cert is already baked in.
    /// (Conservative: the broad rollout of the CA 2023 took hold in 2024.)
    public static var cutoff2023: Date {
        var c = DateComponents()
        c.year = 2024; c.month = 6; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 1_717_200_000)
    }

    public static func classify(newestBootFileDate: Date?,
                                cutoff: Date = SecureBootConcern.cutoff2023) -> SecureBootConcern {
        guard let date = newestBootFileDate else { return .unknown }
        return date >= cutoff ? .likelyModern : .possiblyOutdated
    }
}
