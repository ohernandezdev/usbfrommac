import XCTest
@testable import Flint

final class RateMeterTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testFirstSampleHasNoRate() {
        let m = RateMeter()
        XCTAssertNil(m.sample(bytes: 0, at: at(0)))
    }

    func testSteadyRateMatchesDelta() {
        let m = RateMeter()
        _ = m.sample(bytes: 0, at: at(0))
        // 10 MB in 1 s → 10 MB/s. First rate = instantaneous (no prior history).
        let r = m.sample(bytes: 10_000_000, at: at(1))
        XCTAssertEqual(r ?? 0, 10_000_000, accuracy: 1)
    }

    func testEWMASmoothsTowardNewRate() {
        let m = RateMeter(alpha: 0.5)
        _ = m.sample(bytes: 0, at: at(0))
        _ = m.sample(bytes: 10_000_000, at: at(1))      // 10 MB/s (seed)
        // Next interval at 20 MB/s → EWMA = 0.5*10 + 0.5*20 = 15 MB/s.
        let r = m.sample(bytes: 30_000_000, at: at(2))
        XCTAssertEqual(r ?? 0, 15_000_000, accuracy: 1)
    }

    func testZeroDeltaTimeKeepsLastRate() {
        let m = RateMeter()
        _ = m.sample(bytes: 0, at: at(0))
        let r1 = m.sample(bytes: 5_000_000, at: at(1))
        let r2 = m.sample(bytes: 6_000_000, at: at(1))   // same instant → dt=0
        XCTAssertEqual(r2, r1)
    }

    func testResetClearsHistory() {
        let m = RateMeter()
        _ = m.sample(bytes: 0, at: at(0))
        _ = m.sample(bytes: 1_000_000, at: at(1))
        m.reset()
        XCTAssertNil(m.sample(bytes: 5_000_000, at: at(2)))
    }
}
