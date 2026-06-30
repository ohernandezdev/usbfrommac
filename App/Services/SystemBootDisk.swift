import Foundation

/// Resolves the system's physical boot disk (the one backing "/").
///
/// Used to build the `DiskFilter` BLACKLIST: that disk can never be offered as a
/// destination, not even if it came mislabeled by DiskArbitration.
public enum SystemBootDisk {

    /// BSD identifier of the WHOLE disk backing "/", e.g. "disk3".
    /// Returns `nil` if it can't be resolved (in which case the filter keeps
    /// excluding internal disks via its other rules).
    public static func bsdName() -> String? {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return nil }

        let from = withUnsafeBytes(of: &stat.f_mntfromname) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        // from ≈ "/dev/disk3s1s1" -> we want "disk3".
        let device = from.hasPrefix("/dev/") ? String(from.dropFirst(5)) : from
        let whole = DiskCandidate.wholeDiskBSDName(from: device)
        return whole.hasPrefix("disk") ? whole : nil
    }
}
