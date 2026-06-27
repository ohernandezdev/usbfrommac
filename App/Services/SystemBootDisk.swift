import Foundation

/// Resuelve el disco físico de arranque del sistema (el que respalda "/").
///
/// Se usa para construir la lista NEGRA del `DiskFilter`: ese disco nunca puede
/// ofrecerse como destino, ni aunque viniera mal etiquetado por DiskArbitration.
public enum SystemBootDisk {

    /// Identificador BSD del disco COMPLETO que respalda "/", p. ej. "disk3".
    /// Devuelve `nil` si no se puede resolver (en cuyo caso el filtro sigue
    /// excluyendo internos por sus otras reglas).
    public static func bsdName() -> String? {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return nil }

        let from = withUnsafeBytes(of: &stat.f_mntfromname) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        // from ≈ "/dev/disk3s1s1" -> queremos "disk3".
        let device = from.hasPrefix("/dev/") ? String(from.dropFirst(5)) : from
        let whole = DiskCandidate.wholeDiskBSDName(from: device)
        return whole.hasPrefix("disk") ? whole : nil
    }
}
