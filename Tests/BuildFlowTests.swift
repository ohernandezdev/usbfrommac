import XCTest
@testable import UsbFromMac

final class BuildFlowTests: XCTestCase {

    private func disk(_ id: String, _ size: UInt64) -> Disk {
        Disk(id: id, volumeName: "WIN11", model: "USB", sizeBytes: size, busProtocol: "USB")
    }

    // MARK: Re-validación JIT antes de formatear (S-3)

    func testDiskStillValidWhenPresentWithSameSize() {
        let sel = disk("disk4", 32_000_000_000)
        XCTAssertTrue(DiskRevalidation.isStillValid(selected: sel, in: [sel]))
    }

    func testDiskInvalidWhenMissing() {
        let sel = disk("disk4", 32_000_000_000)
        XCTAssertFalse(DiskRevalidation.isStillValid(selected: sel, in: [disk("disk5", 16_000_000_000)]))
    }

    func testDiskInvalidWhenSameIdButDifferentSize() {
        // CASO CRÍTICO: se reconectó OTRO USB que tomó el mismo "disk4".
        let sel = disk("disk4", 32_000_000_000)
        let now = [disk("disk4", 16_000_000_000)] // mismo id, distinto tamaño
        XCTAssertFalse(DiskRevalidation.isStillValid(selected: sel, in: now))
        XCTAssertNil(DiskRevalidation.revalidated(selected: sel, in: now))
    }

    // MARK: Progreso global ponderado por fase

    func testOverallFractionAcrossPhases() {
        XCTAssertEqual(BuildProgress.overall(phase: .formatting, phaseFraction: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: 0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: 1), 0.65, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .splitting, phaseFraction: 1), 0.95, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .finalizing, phaseFraction: 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .done, phaseFraction: 0), 1.0, accuracy: 0.0001)
    }

    // Flujo raw (Linux): escribir la imagen es casi todo; finalizar cierra el último 5%.
    func testOverallFractionRawFlow() {
        XCTAssertEqual(BuildProgress.overall(phase: .writingImage, phaseFraction: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .writingImage, phaseFraction: 0.5), 0.475, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .writingImage, phaseFraction: 1), 0.95, accuracy: 0.0001)
        // finalizing arranca en 0.95 en AMBOS flujos (Windows y raw).
        XCTAssertEqual(BuildProgress.overall(phase: .finalizing, phaseFraction: 0), 0.95, accuracy: 0.0001)
    }

    func testWindowsPhaseWeightsSumToOne() {
        let total = BuildPhase.ordered.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }

    func testRawPhaseWeightsSumToOne() {
        let total = BuildPhase.rawOrdered.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }

    // La UI muestra las filas de fase según el tipo de ISO.
    func testPhaseSequenceForBootType() {
        XCTAssertEqual(BuildPhase.sequence(for: .windows), BuildPhase.ordered)
        XCTAssertEqual(BuildPhase.sequence(for: .hybridRaw), BuildPhase.rawOrdered)
        XCTAssertTrue(BuildPhase.sequence(for: .elToritoOnly).isEmpty)
        XCTAssertTrue(BuildPhase.sequence(for: .notBootable).isEmpty)
    }

    // MARK: Verificación por efecto del formateo (anti-cuelgue)

    func testFormatOKWhenReplyClean() {
        XCTAssertTrue(EraseDecision.succeeded(replyFailed: false, volumeAppeared: false))
    }

    func testFormatOKWhenVolumeAppearsDespiteLostReply() {
        // El caso real: el reply XPC se perdió pero el USB SÍ se formateó.
        XCTAssertTrue(EraseDecision.succeeded(replyFailed: true, volumeAppeared: true))
    }

    func testFormatFailsOnlyWhenNoReplyAndNoVolume() {
        XCTAssertFalse(EraseDecision.succeeded(replyFailed: true, volumeAppeared: false))
    }

    func testOverallClampsPhaseFraction() {
        // Fracciones fuera de rango no rompen la barra.
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: 5), 0.65, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: -1), 0.05, accuracy: 0.0001)
    }
}
