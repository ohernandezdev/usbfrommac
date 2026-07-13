import Foundation
import Combine

/// Observable service consumed by the UI: it publishes the list of eligible USB
/// drives and keeps it up to date live (RF-1). It composes a source
/// (`DiskEnumerating`) with the `DiskFilter`. All exclusion logic lives in the
/// filter, already covered by tests; this service only orchestrates.
///
/// Threading contract: the source guarantees delivering `onChange` on the main
/// thread, so `disks` is always mutated on main (safe for SwiftUI). That is why
/// the type is NOT `@MainActor`: it avoids isolation friction with the synchronous callback.
public final class DiskService: ObservableObject {

    /// Eligible USB drives, ready to display. Never contains the internal/boot disk.
    @Published public private(set) var disks: [Disk] = []

    private let source: DiskEnumerating
    private let filter: DiskFilter

    /// - Parameters:
    ///   - source: defaults to DiskArbitration; tests inject a fake.
    ///   - bootDiskBSDName: boot disk to exclude; defaults to the system's real one.
    public init(source: DiskEnumerating = DiskArbitrationSource(),
                bootDiskBSDName: String? = SystemBootDisk.bsdName()) {
        self.source = source
        self.filter = DiskFilter(bootDiskBSDName: bootDiskBSDName)
    }

    /// Starts observing disks. The source delivers the current state immediately.
    public func start() {
        source.onChange = { [weak self] candidates in
            // `onChange` already arrives on the main thread (guaranteed by the source).
            self?.apply(candidates)
        }
        source.start()
    }

    public func stop() {
        source.stop()
        source.onChange = nil
    }

    /// Filtered synchronous snapshot (useful for revalidating before actions).
    public func refreshNow() {
        apply(source.currentCandidates())
    }

    /// Filtered snapshot WITHOUT publishing (safe from a background thread). Used
    /// for the JIT re-validation of the disk right before formatting (S-3).
    public func snapshot() -> [Disk] {
        filter.eligibleDisks(from: source.currentCandidates())
    }

    private func apply(_ candidates: [DiskCandidate]) {
        disks = filter.eligibleDisks(from: candidates)
    }
}
