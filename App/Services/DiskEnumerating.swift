import Foundation

/// Disk source: abstracts WHERE the raw candidates come from.
///
/// The production implementation (`DiskArbitrationSource`) uses DiskArbitration
/// + IOKit. Tests use a fake source that emits candidates on demand, so that
/// `DiskService` and the filtering are tested without real hardware.
public protocol DiskEnumerating: AnyObject {

    /// Invoked with the FULL list of raw candidates every time the set of disks
    /// changes (on connect/disconnect). Always on the main thread.
    var onChange: (([DiskCandidate]) -> Void)? { get set }

    /// Starts observing and immediately delivers the current state via `onChange`.
    func start()

    /// Stops observing.
    func stop()

    /// Synchronous snapshot of the current state.
    func currentCandidates() -> [DiskCandidate]
}
