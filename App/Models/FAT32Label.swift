import Foundation

/// Validation and sanitization of FAT32 labels for the UI.
///
/// A FAT32 label allows at most 11 characters. The root helper has its OWN
/// equivalent validation (it doesn't trust this one); here we only validate for
/// the user before dispatching the operation.
public enum FAT32Label {

    public static let maxLength = 11

    /// Conservative, safe character set for a FAT32 label.
    private static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    /// Checks whether a label is valid as-is (already uppercased and sanitized).
    public static func isValid(_ label: String) -> Bool {
        !label.isEmpty
            && label.count <= maxLength
            && label.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Turns any user text into a valid FAT32 label: uppercased, allowed
    /// characters only, truncated to 11. If it ends up empty, uses the
    /// `fallback`.
    public static func sanitize(_ raw: String, fallback: String = "WIN11") -> String {
        let filtered = String(raw.uppercased().unicodeScalars.filter { allowed.contains($0) })
        let trimmed = String(filtered.prefix(maxLength))
        return trimmed.isEmpty ? fallback : trimmed
    }
}
