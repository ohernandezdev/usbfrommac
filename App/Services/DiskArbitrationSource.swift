import Foundation
import DiskArbitration
import IOKit

/// Production disk source: enumerates WHOLE physical disks with IOKit and
/// describes them with DiskArbitration, and observes connection/disconnection
/// live (RF-1: live refresh).
///
/// It does not decide eligibility: it enumerates EVERYTHING (internal disks
/// included) and lets `DiskFilter` apply the whitelist. This way the filter is
/// the single decision point and is fully covered by tests.
public final class DiskArbitrationSource: DiskEnumerating {

    public var onChange: (([DiskCandidate]) -> Void)?

    private var session: DASession?
    private let queue = DispatchQueue(label: "com.omarhernandez.flint.diskarbitration")

    public init() {}

    deinit { stop() }

    public func start() {
        queue.sync {
            guard session == nil else { return }
            guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
            self.session = session
            DASessionSetDispatchQueue(session, queue)

            let context = Unmanaged.passUnretained(self).toOpaque()
            let matchWhole = [kDADiskDescriptionMediaWholeKey as String: kCFBooleanTrue as Any] as CFDictionary

            DARegisterDiskAppearedCallback(session, matchWhole, { _, ctx in
                guard let ctx else { return }
                Unmanaged<DiskArbitrationSource>.fromOpaque(ctx).takeUnretainedValue().handleChange()
            }, context)

            DARegisterDiskDisappearedCallback(session, matchWhole, { _, ctx in
                guard let ctx else { return }
                Unmanaged<DiskArbitrationSource>.fromOpaque(ctx).takeUnretainedValue().handleChange()
            }, context)
        }
        // Immediate delivery of the current state.
        handleChange()
    }

    public func stop() {
        queue.sync {
            if let session {
                DASessionSetDispatchQueue(session, nil)
            }
            session = nil
        }
    }

    public func currentCandidates() -> [DiskCandidate] {
        // Works even if start() was never called: uses a temporary session.
        let sess = session ?? DASessionCreate(kCFAllocatorDefault)
        guard let sess else { return [] }
        return Self.enumerateWholeDisks(session: sess)
    }

    // MARK: - Private

    private func handleChange() {
        let candidates = currentCandidates()
        let callback = onChange
        DispatchQueue.main.async { callback?(candidates) }
    }

    /// Enumerates all whole physical disks (IOMedia with Whole=true) and converts
    /// them to `DiskCandidate` using the DiskArbitration description.
    private static func enumerateWholeDisks(session: DASession) -> [DiskCandidate] {
        // Constants from IOMedia.h (C macros that Swift does not expose as symbols).
        guard let matchingCF = IOServiceMatching("IOMedia") else { return [] }
        let matching = matchingCF as NSMutableDictionary
        matching["Whole"] = kCFBooleanTrue

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingCF, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [DiskCandidate] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let bsd = IORegistryEntryCreateCFProperty(service, "BSD Name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else { continue }
            guard let disk = bsd.withCString({ DADiskCreateFromBSDName(kCFAllocatorDefault, session, $0) }) else { continue }
            if let candidate = makeCandidate(from: disk) {
                result.append(candidate)
            }
        }
        return result
    }

    private static func makeCandidate(from disk: DADisk) -> DiskCandidate? {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any] else { return nil }

        func bool(_ key: CFString) -> Bool {
            (desc[key as String] as? NSNumber)?.boolValue ?? false
        }
        func string(_ key: CFString) -> String? {
            (desc[key as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let bsd = string(kDADiskDescriptionMediaBSDNameKey) else { return nil }
        let size = (desc[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.uint64Value ?? 0

        return DiskCandidate(
            bsdName: bsd,
            isWholeDisk: bool(kDADiskDescriptionMediaWholeKey),
            isInternal: bool(kDADiskDescriptionDeviceInternalKey),
            isRemovable: bool(kDADiskDescriptionMediaRemovableKey),
            isEjectable: bool(kDADiskDescriptionMediaEjectableKey),
            sizeBytes: size,
            volumeName: string(kDADiskDescriptionVolumeNameKey),
            deviceModel: string(kDADiskDescriptionDeviceModelKey),
            busProtocol: string(kDADiskDescriptionDeviceProtocolKey)
        )
    }
}
