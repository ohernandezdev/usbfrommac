import XCTest
@testable import Flint

final class BuildFlowTests: XCTestCase {

    private func disk(_ id: String, _ size: UInt64) -> Disk {
        Disk(id: id, volumeName: "WIN11", model: "USB", sizeBytes: size, busProtocol: "USB")
    }

    // MARK: JIT re-validation before formatting (S-3)

    func testDiskStillValidWhenPresentWithSameSize() {
        let sel = disk("disk4", 32_000_000_000)
        XCTAssertTrue(DiskRevalidation.isStillValid(selected: sel, in: [sel]))
    }

    func testDiskInvalidWhenMissing() {
        let sel = disk("disk4", 32_000_000_000)
        XCTAssertFalse(DiskRevalidation.isStillValid(selected: sel, in: [disk("disk5", 16_000_000_000)]))
    }

    func testDiskInvalidWhenSameIdButDifferentSize() {
        // CRITICAL CASE: ANOTHER USB was reconnected and grabbed the same "disk4".
        let sel = disk("disk4", 32_000_000_000)
        let now = [disk("disk4", 16_000_000_000)] // same id, different size
        XCTAssertFalse(DiskRevalidation.isStillValid(selected: sel, in: now))
        XCTAssertNil(DiskRevalidation.revalidated(selected: sel, in: now))
    }

    // MARK: Phase-weighted overall progress

    func testOverallFractionAcrossPhases() {
        XCTAssertEqual(BuildProgress.overall(phase: .formatting, phaseFraction: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: 0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: 1), 0.65, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .splitting, phaseFraction: 1), 0.95, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .finalizing, phaseFraction: 1), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .done, phaseFraction: 0), 1.0, accuracy: 0.0001)
    }

    // Raw flow (Linux): writing the image is almost everything; finalizing closes the last 5%.
    func testOverallFractionRawFlow() {
        XCTAssertEqual(BuildProgress.overall(phase: .writingImage, phaseFraction: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .writingImage, phaseFraction: 0.5), 0.475, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .writingImage, phaseFraction: 1), 0.95, accuracy: 0.0001)
        // finalizing starts at 0.95 in BOTH flows (Windows and raw).
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

    // The UI shows the phase rows according to the ISO type.
    func testPhaseSequenceForBootType() {
        XCTAssertEqual(BuildPhase.sequence(for: .windows), BuildPhase.ordered)
        XCTAssertEqual(BuildPhase.sequence(for: .hybridRaw), BuildPhase.rawOrdered)
        XCTAssertTrue(BuildPhase.sequence(for: .elToritoOnly).isEmpty)
        XCTAssertTrue(BuildPhase.sequence(for: .notBootable).isEmpty)
    }

    // MARK: Effect-based format verification (anti-hang)

    func testFormatOKWhenReplyClean() {
        XCTAssertTrue(EraseDecision.succeeded(replyFailed: false, volumeAppeared: false))
    }

    func testFormatOKWhenVolumeAppearsDespiteLostReply() {
        // The real-world case: the XPC reply was lost but the USB WAS in fact formatted.
        XCTAssertTrue(EraseDecision.succeeded(replyFailed: true, volumeAppeared: true))
    }

    func testFormatFailsOnlyWhenNoReplyAndNoVolume() {
        XCTAssertFalse(EraseDecision.succeeded(replyFailed: true, volumeAppeared: false))
    }

    func testOverallClampsPhaseFraction() {
        // Out-of-range fractions don't break the bar.
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: 5), 0.65, accuracy: 0.0001)
        XCTAssertEqual(BuildProgress.overall(phase: .copying, phaseFraction: -1), 0.05, accuracy: 0.0001)
    }
}
