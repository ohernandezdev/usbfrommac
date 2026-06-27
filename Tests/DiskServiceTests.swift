import XCTest
@testable import UsbFromMac

/// Tests de `DiskService` con una fuente fake: verifican que el servicio solo
/// publica USB elegibles y que reacciona a conexión/desconexión en vivo (RF-1),
/// sin depender de hardware real.
final class DiskServiceTests: XCTestCase {

    /// Fuente de discos falsa controlable desde el test. Emite `onChange` de forma
    /// síncrona en el hilo del test (main), igual que el contrato de la fuente real.
    private final class FakeDiskSource: DiskEnumerating {
        var onChange: (([DiskCandidate]) -> Void)?
        private(set) var startCalled = false
        private(set) var stopCalled = false
        private var candidates: [DiskCandidate]

        init(_ candidates: [DiskCandidate]) { self.candidates = candidates }

        func start() { startCalled = true; onChange?(candidates) }
        func stop() { stopCalled = true }
        func currentCandidates() -> [DiskCandidate] { candidates }

        /// Simula un cambio en caliente (conectar/desconectar) y notifica.
        func emit(_ newCandidates: [DiskCandidate]) {
            candidates = newCandidates
            onChange?(candidates)
        }
    }

    private func usb(_ bsd: String, _ name: String) -> DiskCandidate {
        DiskCandidate(bsdName: bsd, isWholeDisk: true, isInternal: false,
                      isRemovable: false, isEjectable: true, sizeBytes: 32_000_000_000,
                      volumeName: name, deviceModel: "Generic USB", busProtocol: "USB")
    }

    private func internalDisk(_ bsd: String) -> DiskCandidate {
        DiskCandidate(bsdName: bsd, isWholeDisk: true, isInternal: true,
                      isRemovable: false, isEjectable: false, sizeBytes: 1_000_000_000_000,
                      volumeName: nil, deviceModel: "APPLE SSD", busProtocol: "Apple Fabric")
    }

    func testPublishesOnlyEligibleDisksOnStart() {
        let source = FakeDiskSource([internalDisk("disk0"), usb("disk4", "WIN11")])
        let service = DiskService(source: source, bootDiskBSDName: "disk0")

        service.start()

        XCTAssertTrue(source.startCalled)
        XCTAssertEqual(service.disks.map(\.id), ["disk4"])
    }

    func testInternalDiskNeverAppearsEvenIfItIsTheOnlyDisk() {
        let source = FakeDiskSource([internalDisk("disk0")])
        let service = DiskService(source: source, bootDiskBSDName: "disk0")

        service.start()

        XCTAssertTrue(service.disks.isEmpty)
    }

    func testUpdatesLiveWhenUSBConnectsAndDisconnects() {
        let source = FakeDiskSource([internalDisk("disk0")])
        let service = DiskService(source: source, bootDiskBSDName: "disk0")
        service.start()
        XCTAssertTrue(service.disks.isEmpty)

        // Se conecta un USB.
        source.emit([internalDisk("disk0"), usb("disk4", "WIN11")])
        XCTAssertEqual(service.disks.map(\.id), ["disk4"])

        // Se desconecta.
        source.emit([internalDisk("disk0")])
        XCTAssertTrue(service.disks.isEmpty)
    }

    func testRefreshNowAppliesCurrentCandidates() {
        let source = FakeDiskSource([usb("disk4", "A"), usb("disk5", "B"), internalDisk("disk0")])
        let service = DiskService(source: source, bootDiskBSDName: "disk0")

        service.refreshNow()

        XCTAssertEqual(service.disks.map(\.id), ["disk4", "disk5"])
    }

    func testStopForwardsToSource() {
        let source = FakeDiskSource([])
        let service = DiskService(source: source, bootDiskBSDName: "disk0")
        service.start()
        service.stop()
        XCTAssertTrue(source.stopCalled)
    }
}
