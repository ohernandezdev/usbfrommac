import Foundation

/// Re-validación del disco JUSTO antes de formatear (S-3).
///
/// Entre que el usuario elige el USB y se pulsa "formatear" puede haber pasado
/// una reconexión: el mismo identificador BSD (diskN) podría apuntar ahora a OTRO
/// dispositivo. Por eso no basta con que exista "diskN": debe coincidir también
/// el tamaño. Si el disco elegido ya no está, o cambió, se aborta.
public enum DiskRevalidation {

    /// `true` solo si en la lista actual sigue existiendo EXACTAMENTE el disco
    /// elegido (mismo identificador y mismo tamaño).
    public static func isStillValid(selected: Disk, in current: [Disk]) -> Bool {
        current.contains { $0.id == selected.id && $0.sizeBytes == selected.sizeBytes }
    }

    /// Devuelve el disco revalidado de la lista actual, o `nil` si ya no es válido.
    public static func revalidated(selected: Disk, in current: [Disk]) -> Disk? {
        current.first { $0.id == selected.id && $0.sizeBytes == selected.sizeBytes }
    }
}
