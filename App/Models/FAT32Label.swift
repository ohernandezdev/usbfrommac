import Foundation

/// Validación y saneado de etiquetas FAT32 para la UI.
///
/// La etiqueta FAT32 admite como máximo 11 caracteres. El helper root tiene su
/// PROPIA validación equivalente (no confía en esta); aquí solo se valida de cara
/// al usuario antes de enviar la operación.
public enum FAT32Label {

    public static let maxLength = 11

    /// Charset conservador y seguro para una etiqueta FAT32.
    private static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    /// Comprueba si una etiqueta es válida tal cual (ya en mayúsculas y saneada).
    public static func isValid(_ label: String) -> Bool {
        !label.isEmpty
            && label.count <= maxLength
            && label.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Convierte cualquier texto del usuario en una etiqueta FAT32 válida:
    /// mayúsculas, solo caracteres permitidos, truncada a 11. Si queda vacía,
    /// usa el `fallback`.
    public static func sanitize(_ raw: String, fallback: String = "WIN11") -> String {
        let filtered = String(raw.uppercased().unicodeScalars.filter { allowed.contains($0) })
        let trimmed = String(filtered.prefix(maxLength))
        return trimmed.isEmpty ? fallback : trimmed
    }
}
