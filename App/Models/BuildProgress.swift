import Foundation

/// Progress state of the whole process.
public struct BuildProgress: Equatable {
    public var phase: BuildPhase
    public var phaseFraction: Double   // 0…1 within the current phase
    public var detail: String

    /// Real metrics for the active phase (when applicable): bytes moved/total and
    /// smoothed instantaneous speed. They let the UI show concrete progress
    /// ("X of Y · MB/s · … left") instead of an indeterminate spinner.
    public var bytesDone: UInt64?
    public var bytesTotal: UInt64?
    public var bytesPerSecond: Double?

    public init(phase: BuildPhase,
                phaseFraction: Double,
                detail: String,
                bytesDone: UInt64? = nil,
                bytesTotal: UInt64? = nil,
                bytesPerSecond: Double? = nil) {
        self.phase = phase
        self.phaseFraction = phaseFraction
        self.detail = detail
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.bytesPerSecond = bytesPerSecond
    }

    /// `true` if there is byte data to draw a determinate bar/counter.
    public var hasByteMetrics: Bool {
        if let total = bytesTotal { return total > 0 }
        return false
    }

    /// Global progress 0…1, weighting the phases by their weight.
    public var overallFraction: Double {
        BuildProgress.overall(phase: phase, phaseFraction: phaseFraction)
    }

    public static func overall(phase: BuildPhase, phaseFraction: Double) -> Double {
        if phase == .done { return 1 }
        let f = min(1, max(0, phaseFraction))
        // Explicit segments: the Windows and raw phases never coexist in a build,
        // and `finalizing` closes 0.95→1.0 in BOTH flows.
        switch phase {
        case .formatting:   return 0.05 * f
        case .copying:      return 0.05 + 0.60 * f
        case .splitting:    return 0.65 + 0.30 * f
        case .writingImage: return 0.95 * f
        case .finalizing:   return 0.95 + 0.05 * f
        default:            return 0
        }
    }
}
