import Foundation

/// Disk re-validation RIGHT before formatting (S-3).
///
/// Between the user choosing the USB drive and pressing "format" a reconnection
/// may have happened: the same BSD identifier (diskN) could now point to ANOTHER
/// device. That is why the existence of "diskN" is not enough: the size must also
/// match. If the chosen disk is gone, or has changed, the operation is aborted.
public enum DiskRevalidation {

    /// `true` only if the chosen disk still exists EXACTLY in the current list
    /// (same identifier and same size).
    public static func isStillValid(selected: Disk, in current: [Disk]) -> Bool {
        current.contains { $0.id == selected.id && $0.sizeBytes == selected.sizeBytes }
    }

    /// Returns the revalidated disk from the current list, or `nil` if it is no longer valid.
    public static func revalidated(selected: Disk, in current: [Disk]) -> Disk? {
        current.first { $0.id == selected.id && $0.sizeBytes == selected.sizeBytes }
    }
}
