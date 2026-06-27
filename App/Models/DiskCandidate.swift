import Foundation

/// Materia prima cruda de un disco, tal y como la reporta DiskArbitration
/// (o un fake en tests). Es deliberadamente "tonta": no decide elegibilidad,
/// solo transporta las propiedades que el `DiskFilter` necesita para decidir.
///
/// Separar este tipo de la fuente real (DiskArbitration/IOKit) es lo que permite
/// probar el filtrado de discos SIN hardware: los tests inyectan candidatos
/// (incluido el disco interno/de arranque) y verifican que jamás pasan el filtro.
public struct DiskCandidate: Equatable, Hashable {

    /// Identificador BSD, p. ej. "disk4" (whole) o "disk4s1" (partición).
    public let bsdName: String

    /// `true` si es un disco físico COMPLETO (kDADiskDescriptionMediaWholeKey),
    /// no una partición ni un volumen sintético.
    public let isWholeDisk: Bool

    /// `true` si el dispositivo es interno (kDADiskDescriptionDeviceInternalKey).
    /// Los internos se excluyen SIEMPRE.
    public let isInternal: Bool

    /// `true` si el medio es removible (kDADiskDescriptionMediaRemovableKey).
    public let isRemovable: Bool

    /// `true` si el medio es expulsable (kDADiskDescriptionMediaEjectableKey).
    /// Los pendrives USB suelen reportar ejectable=true.
    public let isEjectable: Bool

    /// Tamaño del medio en bytes (kDADiskDescriptionMediaSizeKey).
    public let sizeBytes: UInt64

    /// Nombre del volumen, si hay uno montado (kDADiskDescriptionVolumeNameKey).
    public let volumeName: String?

    /// Modelo del dispositivo (kDADiskDescriptionDeviceModelKey), p. ej. "SanDisk Ultra".
    public let deviceModel: String?

    /// Protocolo del bus (kDADiskDescriptionDeviceProtocolKey), p. ej. "USB".
    public let busProtocol: String?

    public init(bsdName: String,
                isWholeDisk: Bool,
                isInternal: Bool,
                isRemovable: Bool,
                isEjectable: Bool,
                sizeBytes: UInt64,
                volumeName: String?,
                deviceModel: String?,
                busProtocol: String?) {
        self.bsdName = bsdName
        self.isWholeDisk = isWholeDisk
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.sizeBytes = sizeBytes
        self.volumeName = volumeName
        self.deviceModel = deviceModel
        self.busProtocol = busProtocol
    }

    /// Identificador del disco COMPLETO al que pertenece este candidato.
    /// "disk4s1" -> "disk4". Para candidatos whole devuelve su propio nombre.
    public var wholeDiskBSDName: String {
        DiskCandidate.wholeDiskBSDName(from: bsdName)
    }

    /// "disk4s1s2" -> "disk4". Devuelve la cadena original si no matchea el patrón.
    public static func wholeDiskBSDName(from bsd: String) -> String {
        guard bsd.hasPrefix("disk") else { return bsd }
        let digits = bsd.dropFirst(4).prefix { $0.isNumber }
        guard !digits.isEmpty else { return bsd }
        return "disk" + digits
    }
}
