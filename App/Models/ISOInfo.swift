import Foundation

/// Resultado de inspeccionar un ISO montado.
public struct ISOInfo: Equatable {

    public let url: URL
    public let sizeBytes: UInt64
    public let volumeName: String?

    /// `true` si parece un instalador de Windows (setup + carpeta sources + imagen).
    public let isWindowsInstaller: Bool

    /// Tamaño de `sources/install.wim` si existe.
    public let installWIMSizeBytes: UInt64?

    /// `true` si la imagen es `install.esd` (suele caber en FAT32 sin dividir).
    public let usesESD: Bool

    /// Fecha de modificación más reciente entre los archivos de arranque EFI.
    /// Se usa como proxy para la advertencia de Secure Boot 2023 (S-7).
    public let newestBootFileDate: Date?

    /// Cómo debe escribirse este ISO para que el USB arranque (determina la
    /// estrategia: copia FAT32 para Windows vs. escritura cruda para isohíbridos).
    public let bootType: ISOBootType

    public init(url: URL, sizeBytes: UInt64, volumeName: String?,
                isWindowsInstaller: Bool, installWIMSizeBytes: UInt64?,
                usesESD: Bool, newestBootFileDate: Date?,
                bootType: ISOBootType) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.volumeName = volumeName
        self.isWindowsInstaller = isWindowsInstaller
        self.installWIMSizeBytes = installWIMSizeBytes
        self.usesESD = usesESD
        self.newestBootFileDate = newestBootFileDate
        self.bootType = bootType
    }

    /// `true` si la app puede crear un USB booteable de este ISO (Windows o isohíbrido).
    public var bootIsSupported: Bool { bootType.isSupportable }

    /// Límite duro de FAT32 por archivo: 4 GiB.
    public static let fat32FileLimit: UInt64 = 4 * 1024 * 1024 * 1024

    /// `true` si `install.wim` supera FAT32 y hay que dividirlo con wimlib (RF-8).
    public var requiresWIMSplit: Bool {
        (installWIMSizeBytes ?? 0) > ISOInfo.fat32FileLimit
    }

    /// Clasificación de riesgo Secure Boot según la fecha de los archivos de arranque.
    public var secureBootConcern: SecureBootConcern {
        SecureBootConcern.classify(newestBootFileDate: newestBootFileDate)
    }
}

/// Advertencia de compatibilidad con Secure Boot (S-7).
///
/// El certificado "PCA 2011" se revoca en 2026; solo los ISOs firmados con
/// "Windows UEFI CA 2023" arrancan con Secure Boot garantizado. Detectar el
/// certificado del bootloader exige parsear firmas PE, así que se usa una
/// HEURÍSTICA informativa: la fecha de los archivos de arranque. Solo informa,
/// nunca bloquea.
public enum SecureBootConcern: Equatable {
    /// Los archivos de arranque son recientes → probablemente cert 2023.
    case likelyModern
    /// Archivos de arranque antiguos → puede no arrancar con Secure Boot ON.
    case possiblyOutdated
    /// No se pudo determinar la fecha.
    case unknown

    /// Fecha de corte: a partir de aquí asumimos cert 2023 ya integrado.
    /// (Conservadora: el despliegue amplio del CA 2023 se afianzó en 2024.)
    public static var cutoff2023: Date {
        var c = DateComponents()
        c.year = 2024; c.month = 6; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 1_717_200_000)
    }

    public static func classify(newestBootFileDate: Date?,
                                cutoff: Date = SecureBootConcern.cutoff2023) -> SecureBootConcern {
        guard let date = newestBootFileDate else { return .unknown }
        return date >= cutoff ? .likelyModern : .possiblyOutdated
    }
}
