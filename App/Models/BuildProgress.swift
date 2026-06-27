import Foundation

/// Estado de progreso del proceso completo.
public struct BuildProgress: Equatable {
    public var phase: BuildPhase
    public var phaseFraction: Double   // 0…1 dentro de la fase actual
    public var detail: String

    /// Métricas reales de la fase activa (cuando aplican): bytes movidos/total y
    /// velocidad instantánea suavizada. Permiten a la UI mostrar avance concreto
    /// ("X de Y · MB/s · faltan …") en vez de un spinner indeterminado.
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

    /// `true` si hay datos de bytes para dibujar una barra/contador determinado.
    public var hasByteMetrics: Bool {
        if let total = bytesTotal { return total > 0 }
        return false
    }

    /// Progreso global 0…1 ponderando las fases por su peso.
    public var overallFraction: Double {
        BuildProgress.overall(phase: phase, phaseFraction: phaseFraction)
    }

    public static func overall(phase: BuildPhase, phaseFraction: Double) -> Double {
        if phase == .done { return 1 }
        guard let idx = BuildPhase.ordered.firstIndex(of: phase) else { return 0 }
        var sum = 0.0
        for p in BuildPhase.ordered.prefix(idx) { sum += p.weight }
        sum += BuildPhase.ordered[idx].weight * min(1, max(0, phaseFraction))
        return min(1, sum)
    }
}
