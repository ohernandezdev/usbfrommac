import XCTest
@testable import Flint

/// Tests for the app's safety core (CA-1 / CA-6 / S-1):
/// it must be IMPOSSIBLE for the internal or boot disk to pass the filter,
/// even when faced with mislabeled candidates (adversarial cases).
final class DiskFilterTests: XCTestCase {

    // MARK: Candidate factory

    /// Creates a candidate with "USB-safe" defaults and lets each case
    /// override only what's relevant to it.
    private func candidate(
        bsd: String = "disk4",
        whole: Bool = true,
        isInternal: Bool = false,
        removable: Bool = false,
        ejectable: Bool = true,
        size: UInt64 = 32_000_000_000,
        volume: String? = "WIN11",
        model: String? = "SanDisk Ultra",
        proto: String? = "USB"
    ) -> DiskCandidate {
        DiskCandidate(bsdName: bsd, isWholeDisk: whole, isInternal: isInternal,
                      isRemovable: removable, isEjectable: ejectable, sizeBytes: size,
                      volumeName: volume, deviceModel: model, busProtocol: proto)
    }

    // Typical internal boot disk of a Mac (APPLE SSD).
    private func internalBootSSD() -> DiskCandidate {
        candidate(bsd: "disk0", whole: true, isInternal: true,
                  removable: false, ejectable: false, size: 1_000_000_000_000,
                  volume: nil, model: "APPLE SSD AP1024", proto: "Apple Fabric")
    }

    // MARK: Hard exclusions

    func testInternalBootSSDIsNeverEligible() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertFalse(filter.isEligible(internalBootSSD()))
    }

    func testInternalDiskExcludedEvenWithUnknownBootDisk() {
        // Even if the boot disk couldn't be resolved, the "never internal"
        // rule is enough to exclude it.
        let filter = DiskFilter(bootDiskBSDName: nil)
        XCTAssertFalse(filter.isEligible(internalBootSSD()))
    }

    func testBootDiskBlacklistedEvenIfMismarkedAsExternal() {
        // ADVERSARIAL: a candidate that (wrongly) presents itself as external,
        // whole and ejectable, but IS the boot disk. The blacklist wins.
        let filter = DiskFilter(bootDiskBSDName: "disk3")
        let trap = candidate(bsd: "disk3", whole: true, isInternal: false,
                             removable: true, ejectable: true)
        XCTAssertFalse(filter.isEligible(trap))
    }

    func testBootDiskPartitionAlsoBlacklisted() {
        // A partition of the boot disk (disk3s1) maps to "disk3" -> excluded.
        let filter = DiskFilter(bootDiskBSDName: "disk3")
        let part = candidate(bsd: "disk3s1", whole: false, isInternal: true)
        XCTAssertFalse(filter.isEligible(part))
    }

    func testSyntheticOrPartitionNotWholeIsExcluded() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertFalse(filter.isEligible(candidate(bsd: "disk1", whole: false)))   // synthetic APFS
        XCTAssertFalse(filter.isEligible(candidate(bsd: "disk4s1", whole: false))) // USB partition
    }

    func testExternalButFixedDiskIsExcluded() {
        // External and whole, but neither removable nor ejectable -> not a flash drive.
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let fixed = candidate(bsd: "disk5", whole: true, isInternal: false,
                              removable: false, ejectable: false)
        XCTAssertFalse(filter.isEligible(fixed))
    }

    func testZeroSizeIsExcluded() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertFalse(filter.isEligible(candidate(size: 0)))
    }

    func testMountedDiskImageIsExcluded() {
        // Disk images (.dmg, iOS simulators) report external+removable
        // but are NOT physical flash drives. They must not show up.
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let dmg = candidate(bsd: "disk4", whole: true, isInternal: false,
                            removable: true, ejectable: true, proto: "Disk Image")
        XCTAssertFalse(filter.isEligible(dmg))
    }

    func testVirtualInterfaceDiskImageIsExcluded() {
        // REAL CASE (seen on hardware): macOS disk images report
        // DADeviceProtocol="Virtual Interface" (NOT "Disk Image") and DADeviceModel=
        // "Disk Image". The filter MUST catch them via either of the two signals.
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let img = candidate(bsd: "disk4", whole: true, isInternal: false,
                            removable: true, ejectable: true,
                            model: "Disk Image", proto: "Virtual Interface")
        XCTAssertFalse(filter.isEligible(img))
    }

    func testVirtualModelAloneIsExcluded() {
        // Even if the protocol came back empty/unknown, model "Disk Image" is enough.
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let img = candidate(bsd: "disk4", whole: true, isInternal: false,
                            removable: true, ejectable: true,
                            model: "Disk Image", proto: nil)
        XCTAssertFalse(filter.isEligible(img))
    }

    // MARK: Legitimate inclusions

    func testExternalEjectableUSBIsEligible() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertTrue(filter.isEligible(candidate(bsd: "disk4")))
    }

    func testExternalRemovableUSBIsEligible() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let usb = candidate(bsd: "disk4", removable: true, ejectable: false)
        XCTAssertTrue(filter.isEligible(usb))
    }

    // MARK: Mapping + ordering of the resulting list

    func testEligibleDisksKeepsOnlyUSBAndSortsStably() {
        let filter = DiskFilter(bootDiskBSDName: "disk3")
        let candidates = [
            internalBootSSD(),                              // disk0 internal
            candidate(bsd: "disk6", volume: "USB-B"),       // USB
            candidate(bsd: "disk3", isInternal: true,       // boot (mislabeled)
                      removable: true, ejectable: true),
            candidate(bsd: "disk1", whole: false),          // synthetic
            candidate(bsd: "disk4", volume: "USB-A"),       // USB
        ]
        let disks = filter.eligibleDisks(from: candidates)
        XCTAssertEqual(disks.map(\.id), ["disk4", "disk6"]) // USB only, sorted
    }

    func testEligibleDiskMapsWholeBSDAndFields() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let usb = candidate(bsd: "disk4", size: 16_000_000_000, volume: "INSTALL", model: "Kingston")
        let disks = filter.eligibleDisks(from: [usb])
        XCTAssertEqual(disks.count, 1)
        let d = disks[0]
        XCTAssertEqual(d.id, "disk4")
        XCTAssertEqual(d.devicePath, "/dev/disk4")
        XCTAssertEqual(d.displayName, "INSTALL")
        XCTAssertEqual(d.sizeBytes, 16_000_000_000)
    }

    func testEmptyInputYieldsEmptyOutput() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertTrue(filter.eligibleDisks(from: []).isEmpty)
    }

    // MARK: Identifier normalization

    func testWholeDiskBSDNameNormalization() {
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "disk4"), "disk4")
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "disk4s1"), "disk4")
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "disk10s1s2"), "disk10")
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "notadisk"), "notadisk")
    }
}
