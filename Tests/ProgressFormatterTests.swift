import XCTest
@testable import Flint

final class ProgressFormatterTests: XCTestCase {

    // MARK: Percentage (clamped and rounded)

    func testPercentRoundsAndClamps() {
        XCTAssertEqual(ProgressFormatter.percent(0), "0 %")
        XCTAssertEqual(ProgressFormatter.percent(0.474), "47 %")
        XCTAssertEqual(ProgressFormatter.percent(0.475), "48 %")
        XCTAssertEqual(ProgressFormatter.percent(1), "100 %")
        XCTAssertEqual(ProgressFormatter.percent(1.5), "100 %")   // clamp high
        XCTAssertEqual(ProgressFormatter.percent(-0.3), "0 %")    // clamp low
    }

    // MARK: Human-readable duration

    func testDurationFormatting() {
        XCTAssertEqual(ProgressFormatter.duration(0), "0 s")
        XCTAssertEqual(ProgressFormatter.duration(45), "45 s")
        XCTAssertEqual(ProgressFormatter.duration(59.4), "59 s")
        XCTAssertEqual(ProgressFormatter.duration(60), "1 min")
        XCTAssertEqual(ProgressFormatter.duration(72), "1 min 12 s")
        XCTAssertEqual(ProgressFormatter.duration(120), "2 min")
        XCTAssertEqual(ProgressFormatter.duration(-5), "0 s")     // no negatives
    }

    // MARK: ETA

    func testETAComputesRemainingTime() {
        // 100 MB remaining at 10 MB/s → 10 s.
        let eta = ProgressFormatter.eta(remainingBytes: 100_000_000, bytesPerSecond: 10_000_000)
        XCTAssertEqual(eta, "10 s")
    }

    func testETANilWhenRateTooLow() {
        XCTAssertNil(ProgressFormatter.eta(remainingBytes: 1_000_000, bytesPerSecond: 0))
        XCTAssertNil(ProgressFormatter.eta(remainingBytes: 1_000_000, bytesPerSecond: 1))
    }

    // MARK: Transfer line (structure, without depending on the byte locale)

    func testTransferLineStructure() {
        // Language-agnostic: we validate structure and data, not the words
        // (which depend on the app's language: "de"/"of", "faltan"/"left").
        let line = ProgressFormatter.transferLine(done: 3_000_000_000,
                                                  total: 6_000_000_000,
                                                  bytesPerSecond: 50_000_000)
        let parts = line.components(separatedBy: " · ")
        XCTAssertEqual(parts.count, 3, "expected progress · speed · ETA: \(line)")
        XCTAssertTrue(parts[0].contains("50 %"), "expected percentage: \(line)")
        XCTAssertTrue(parts[1].contains("/s"), "expected speed: \(line)")
        XCTAssertFalse(parts[2].isEmpty, "expected non-empty ETA: \(line)")
    }

    func testTransferLineOmitsRateWhenNil() {
        let line = ProgressFormatter.transferLine(done: 1_000, total: 2_000, bytesPerSecond: nil)
        XCTAssertTrue(line.contains("50 %"))
        XCTAssertFalse(line.contains("/s"))
        XCTAssertFalse(line.contains("faltan"))
    }

    func testTransferLineZeroTotalIsZeroPercent() {
        let line = ProgressFormatter.transferLine(done: 0, total: 0, bytesPerSecond: nil)
        XCTAssertTrue(line.contains("0 %"))
    }
}
