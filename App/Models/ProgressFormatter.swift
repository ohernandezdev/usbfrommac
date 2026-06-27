import Foundation

/// Formato legible de las métricas de progreso (bytes, porcentaje, velocidad, ETA).
/// Funciones puras → testeables sin UI.
public enum ProgressFormatter {

    /// Tamaño legible: "3,2 GB" (estilo de archivo, base 1000 como Finder).
    public static func bytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(n, UInt64(Int64.max))), countStyle: .file)
    }

    /// Porcentaje entero clampeado a 0…100: 0.47 → "47 %".
    public static func percent(_ fraction: Double) -> String {
        let clamped = min(1, max(0, fraction))
        return "\(Int((clamped * 100).rounded())) %"
    }

    /// Velocidad: bytes/seg → "42 MB/s". Devuelve "—" si no hay tasa válida.
    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "—" }
        return bytes(UInt64(bytesPerSecond)) + "/s"
    }

    /// Duración legible: 45 → "45 s", 72 → "1 min 12 s", 120 → "2 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return loc("duration.seconds \(total)") }
        let minutes = total / 60
        let rem = total % 60
        return rem == 0
            ? loc("duration.minutes \(minutes)")
            : loc("duration.minutesSeconds \(minutes) \(rem)")
    }

    /// Tiempo estimado restante, o `nil` si la velocidad es demasiado baja/inestable.
    public static func eta(remainingBytes: UInt64, bytesPerSecond: Double) -> String? {
        guard bytesPerSecond > 1 else { return nil }
        return duration(Double(remainingBytes) / bytesPerSecond)
    }

    /// Línea completa de transferencia:
    /// "3,2 GB de 6,8 GB (47 %) · 42 MB/s · faltan 1 min 12 s".
    /// Las partes de velocidad/ETA se omiten si no hay tasa fiable aún.
    public static func transferLine(done: UInt64, total: UInt64, bytesPerSecond: Double?) -> String {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        // "3,2 GB de 6,8 GB (47 %)" → clave parametrizada %@ %@ %@.
        var parts = [loc("transfer.progress \(bytes(done)) \(bytes(total)) \(percent(fraction))")]
        if let bps = bytesPerSecond, bps > 0 {
            parts.append(rate(bps))
            if total >= done, let remaining = eta(remainingBytes: total - done, bytesPerSecond: bps) {
                parts.append(loc("transfer.eta \(remaining)"))
            }
        }
        return parts.joined(separator: " · ")
    }
}
