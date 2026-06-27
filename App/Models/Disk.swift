import Foundation

/// Disco USB elegible que se muestra al usuario en la lista.
///
/// Un `Disk` solo se construye a partir de candidatos que YA pasaron el
/// `DiskFilter` (whole + external + removable + no es el de arranque). Por diseño,
/// es imposible representar aquí el disco interno o de arranque.
public struct Disk: Identifiable, Equatable, Hashable {

    /// Identificador BSD del disco completo, p. ej. "disk4". Sirve de `id`.
    public let id: String

    /// "/dev/disk4" — ruta del dispositivo para diskutil.
    public var devicePath: String { "/dev/\(id)" }

    /// Nombre del volumen montado, si lo hay.
    public let volumeName: String?

    /// Modelo del dispositivo, p. ej. "SanDisk Ultra".
    public let model: String?

    /// Tamaño en bytes.
    public let sizeBytes: UInt64

    /// Protocolo del bus, p. ej. "USB".
    public let busProtocol: String?

    public init(id: String,
                volumeName: String?,
                model: String?,
                sizeBytes: UInt64,
                busProtocol: String?) {
        self.id = id
        self.volumeName = volumeName
        self.model = model
        self.sizeBytes = sizeBytes
        self.busProtocol = busProtocol
    }

    /// Tamaño legible, p. ej. "32 GB".
    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }

    /// Nombre mostrable: volumen > modelo > identificador BSD.
    public var displayName: String {
        if let v = volumeName, !v.isEmpty { return v }
        if let m = model, !m.isEmpty { return m }
        return id
    }

    // MARK: Umbrales de tamaño (RF-3)

    /// Tamaño mínimo recomendado para Windows 11 (≥ 16 GB).
    public static let recommendedMinimumBytes: UInt64 = 16 * 1_000_000_000

    /// Por debajo de esto, advertir con fuerza (< 8 GB).
    public static let hardWarnBelowBytes: UInt64 = 8 * 1_000_000_000

    public var meetsRecommendedSize: Bool { sizeBytes >= Disk.recommendedMinimumBytes }
    public var isTooSmall: Bool { sizeBytes < Disk.hardWarnBelowBytes }
}
