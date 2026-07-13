import Foundation

/// Disk filter: the "code-level whitelist" required by the goal and by S-1. It
/// is a PURE function (no side effects, no hardware access) so it can be tested
/// exhaustively: candidates are injected —including the internal and boot disk—
/// and it is verified that ONLY external USB drives survive.
///
/// It is layer 1 of a 3-layer defense in depth:
///   1. `DiskFilter`        — the app never lists or allows an ineligible disk.
///   2. Root helper         — revalidates whole+external+removable before eraseDisk (S-4).
///   3. JIT re-resolution   — the identifier is re-checked right before
///                            formatting (S-3).
public struct DiskFilter {

    /// BSD of the system boot disk (e.g. "disk3"), if it could be resolved.
    /// It goes into an explicit BLACKLIST: even if a candidate were mistakenly
    /// marked as external, if it is the boot disk it is excluded no matter what.
    public let bootDiskBSDName: String?

    public init(bootDiskBSDName: String?) {
        self.bootDiskBSDName = bootDiskBSDName
    }

    /// Decides whether a candidate can be offered to the user as a USB target.
    ///
    /// Whitelist rule (ALL must hold):
    ///   - it is a WHOLE physical disk (not a partition or synthetic volume),
    ///   - it is NOT internal,
    ///   - it is removable or ejectable (flash drive),
    ///   - it is NOT the system boot disk (blacklist),
    ///   - it has size > 0.
    public func isEligible(_ c: DiskCandidate) -> Bool {
        // Hard exclusion layer: never the boot disk, no matter what.
        if let boot = bootDiskBSDName, c.wholeDiskBSDName == boot {
            return false
        }
        guard c.isWholeDisk else { return false }   // whole disks only
        guard !c.isInternal else { return false }   // never internal
        // Exclude NON-physical devices (mounted disk images, virtual VM
        // interfaces, cryptexes…): they show up as external+removable but are not
        // USB flash drives. macOS reports them with protocol "Disk Image" or
        // "Virtual Interface", and/or model "Disk Image".
        if Self.isVirtualOrImage(c) { return false }
        guard c.isRemovable || c.isEjectable else { return false } // must be removable USB
        guard c.sizeBytes > 0 else { return false }
        return true
    }

    /// `true` if the candidate is a disk image or a virtual device (not a real
    /// physical medium). It relies on several DiskArbitration signals because no
    /// single one is sufficient on its own (seen in hardware: disk images arrive
    /// with protocol "Virtual Interface", not "Disk Image").
    static func isVirtualOrImage(_ c: DiskCandidate) -> Bool {
        if let p = c.busProtocol?.lowercased(),
           p == "disk image" || p.contains("virtual") {
            return true
        }
        if let m = c.deviceModel?.lowercased(), m == "disk image" {
            return true
        }
        return false
    }

    /// Applies the filter to a raw list and returns `Disk` values ready for the
    /// UI, stably sorted by BSD identifier.
    public func eligibleDisks(from candidates: [DiskCandidate]) -> [Disk] {
        candidates
            .filter(isEligible)
            .sorted { $0.bsdName < $1.bsdName }
            .map { c in
                Disk(id: c.wholeDiskBSDName,
                     volumeName: c.volumeName,
                     model: c.deviceModel,
                     sizeBytes: c.sizeBytes,
                     busProtocol: c.busProtocol)
            }
    }
}
