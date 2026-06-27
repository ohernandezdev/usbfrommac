import XCTest
@testable import UsbFromMac

/// Tests del corazón de seguridad de la app (CA-1 / CA-6 / S-1):
/// debe ser IMPOSIBLE que el disco interno o el de arranque pasen el filtro,
/// incluso ante candidatos mal etiquetados (casos adversariales).
final class DiskFilterTests: XCTestCase {

    // MARK: Factoría de candidatos

    /// Crea un candidato con valores por defecto "seguros de USB" y permite
    /// sobreescribir solo lo relevante para cada caso.
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

    // Disco interno de arranque típico de un Mac (APPLE SSD).
    private func internalBootSSD() -> DiskCandidate {
        candidate(bsd: "disk0", whole: true, isInternal: true,
                  removable: false, ejectable: false, size: 1_000_000_000_000,
                  volume: nil, model: "APPLE SSD AP1024", proto: "Apple Fabric")
    }

    // MARK: Exclusiones duras

    func testInternalBootSSDIsNeverEligible() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertFalse(filter.isEligible(internalBootSSD()))
    }

    func testInternalDiskExcludedEvenWithUnknownBootDisk() {
        // Aunque no se haya podido resolver el disco de arranque, la regla
        // "jamás internos" basta para excluirlo.
        let filter = DiskFilter(bootDiskBSDName: nil)
        XCTAssertFalse(filter.isEligible(internalBootSSD()))
    }

    func testBootDiskBlacklistedEvenIfMismarkedAsExternal() {
        // ADVERSARIAL: un candidato que (erróneamente) se presenta como externo,
        // whole y ejectable, pero ES el disco de arranque. La lista negra gana.
        let filter = DiskFilter(bootDiskBSDName: "disk3")
        let trap = candidate(bsd: "disk3", whole: true, isInternal: false,
                             removable: true, ejectable: true)
        XCTAssertFalse(filter.isEligible(trap))
    }

    func testBootDiskPartitionAlsoBlacklisted() {
        // Una partición del disco de arranque (disk3s1) mapea a "disk3" -> excluida.
        let filter = DiskFilter(bootDiskBSDName: "disk3")
        let part = candidate(bsd: "disk3s1", whole: false, isInternal: true)
        XCTAssertFalse(filter.isEligible(part))
    }

    func testSyntheticOrPartitionNotWholeIsExcluded() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertFalse(filter.isEligible(candidate(bsd: "disk1", whole: false)))   // APFS sintético
        XCTAssertFalse(filter.isEligible(candidate(bsd: "disk4s1", whole: false))) // partición de USB
    }

    func testExternalButFixedDiskIsExcluded() {
        // Externo y whole, pero ni removible ni ejectable -> no es un pendrive.
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
        // Imágenes de disco (.dmg, simuladores de iOS) reportan external+removable
        // pero NO son pendrives físicos. No deben aparecer.
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let dmg = candidate(bsd: "disk4", whole: true, isInternal: false,
                            removable: true, ejectable: true, proto: "Disk Image")
        XCTAssertFalse(filter.isEligible(dmg))
    }

    // MARK: Inclusiones legítimas

    func testExternalEjectableUSBIsEligible() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        XCTAssertTrue(filter.isEligible(candidate(bsd: "disk4")))
    }

    func testExternalRemovableUSBIsEligible() {
        let filter = DiskFilter(bootDiskBSDName: "disk0")
        let usb = candidate(bsd: "disk4", removable: true, ejectable: false)
        XCTAssertTrue(filter.isEligible(usb))
    }

    // MARK: Mapeo + orden de la lista resultante

    func testEligibleDisksKeepsOnlyUSBAndSortsStably() {
        let filter = DiskFilter(bootDiskBSDName: "disk3")
        let candidates = [
            internalBootSSD(),                              // disk0 interno
            candidate(bsd: "disk6", volume: "USB-B"),       // USB
            candidate(bsd: "disk3", isInternal: true,       // arranque (mal marcado)
                      removable: true, ejectable: true),
            candidate(bsd: "disk1", whole: false),          // sintético
            candidate(bsd: "disk4", volume: "USB-A"),       // USB
        ]
        let disks = filter.eligibleDisks(from: candidates)
        XCTAssertEqual(disks.map(\.id), ["disk4", "disk6"]) // solo USB, ordenados
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

    // MARK: Normalización de identificadores

    func testWholeDiskBSDNameNormalization() {
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "disk4"), "disk4")
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "disk4s1"), "disk4")
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "disk10s1s2"), "disk10")
        XCTAssertEqual(DiskCandidate.wholeDiskBSDName(from: "notadisk"), "notadisk")
    }
}
