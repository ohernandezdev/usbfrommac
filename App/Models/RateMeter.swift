import Foundation

/// Medidor de velocidad de transferencia (bytes/seg) con suavizado exponencial.
///
/// Recibe el total ACUMULADO de bytes en cada muestra (no el delta) junto con su
/// instante; devuelve una tasa suavizada (EWMA) para que el número no salte con
/// cada chunk. Es puro respecto al reloj: el instante se inyecta, así es testeable
/// sin depender de `Date()` real.
public final class RateMeter {
    private let alpha: Double
    private var lastBytes: UInt64?
    private var lastTime: Date?
    private var ewma: Double?

    public init(alpha: Double = 0.3) {
        self.alpha = alpha
    }

    /// Registra una muestra (bytes acumulados, instante) y devuelve la velocidad
    /// suavizada en bytes/seg, o `nil` si aún no hay suficiente historia.
    @discardableResult
    public func sample(bytes: UInt64, at time: Date) -> Double? {
        defer { lastBytes = bytes; lastTime = time }
        guard let lb = lastBytes, let lt = lastTime else { return nil }
        let dt = time.timeIntervalSince(lt)
        // Sin tiempo transcurrido o retroceso de bytes: conserva la última tasa.
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
