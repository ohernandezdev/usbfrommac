import Foundation

/// Transfer speed meter (bytes/sec) with exponential smoothing.
///
/// It receives the CUMULATIVE total of bytes on each sample (not the delta) along
/// with its timestamp; it returns a smoothed rate (EWMA) so the number doesn't jump
/// with every chunk. It's pure with respect to the clock: the timestamp is injected,
/// so it's testable without depending on the real `Date()`.
public final class RateMeter {
    private let alpha: Double
    private var lastBytes: UInt64?
    private var lastTime: Date?
    private var ewma: Double?

    public init(alpha: Double = 0.3) {
        self.alpha = alpha
    }

    /// Records a sample (cumulative bytes, timestamp) and returns the smoothed
    /// speed in bytes/sec, or `nil` if there isn't enough history yet.
    @discardableResult
    public func sample(bytes: UInt64, at time: Date) -> Double? {
        defer { lastBytes = bytes; lastTime = time }
        guard let lb = lastBytes, let lt = lastTime else { return nil }
        let dt = time.timeIntervalSince(lt)
        // No elapsed time or bytes went backwards: keep the last rate.
        guard dt > 0, bytes >= lb else { return ewma }
        let instant = Double(bytes - lb) / dt
        ewma = ewma.map { $0 * (1 - alpha) + instant * alpha } ?? instant
        return ewma
    }

    public func reset() {
        lastBytes = nil
        lastTime = nil
        ewma = nil
    }
}
