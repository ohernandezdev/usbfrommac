import Foundation

/// Filtro de discos: la "lista blanca a nivel de código" exigida por el goal y
/// por S-1. Es una función PURA (sin efectos, sin acceso a hardware) para poder
/// probarla exhaustivamente: se le inyectan candidatos —incluido el disco
/// interno y el de arranque— y se verifica que SOLO los USB externos sobreviven.
///
/// Es la capa 1 de una defensa en profundidad de 3 capas:
///   1. `DiskFilter`        — la app jamás lista ni permite un disco no elegible.
///   2. Helper root         — revalida whole+external+removable antes de eraseDisk (S-4).
///   3. Re-resolución JIT   — se vuelve a comprobar el identificador justo antes
///                            de formatear (S-3).
public struct DiskFilter {

    /// BSD del disco de arranque del sistema (p. ej. "disk3"), si se pudo resolver.
    /// Va a una lista NEGRA explícita: aunque algún candidato viniese mal marcado
    /// como externo, si es el disco de arranque queda excluido sí o sí.
    public let bootDiskBSDName: String?

    public init(bootDiskBSDName: String?) {
        self.bootDiskBSDName = bootDiskBSDName
    }

    /// Decide si un candidato puede ofrecerse al usuario como destino USB.
    ///
    /// Regla de lista blanca (TODAS deben cumplirse):
    ///   - es un disco físico COMPLETO (no partición ni volumen sintético),
    ///   - NO es interno,
    ///   - es removible o expulsable (pendrive),
    ///   - NO es el disco de arranque del sistema (lista negra),
    ///   - tiene tamaño > 0.
    public func isEligible(_ c: DiskCandidate) -> Bool {
        // Capa de exclusión dura: nunca el disco de arranque, pase lo que pase.
        if let boot = bootDiskBSDName, c.wholeDiskBSDName == boot {
            return false
        }
        guard c.isWholeDisk else { return false }   // solo discos completos
        guard !c.isInternal else { return false }   // jamás internos
        // Excluir imágenes de disco montadas (.dmg, simuladores de iOS, cryptexes…):
        // son "externas" y "removibles" pero NO son pendrives USB físicos.
        if let proto = c.busProtocol, proto.caseInsensitiveCompare("Disk Image") == .orderedSame {
            return false
        }
        guard c.isRemovable || c.isEjectable else { return false } // debe ser USB extraíble
        guard c.sizeBytes > 0 else { return false }
        return true
    }

    /// Aplica el filtro a una lista cruda y devuelve `Disk` listos para la UI,
    /// ordenados de forma estable por identificador BSD.
    public func eligibleDisks(from candidates: [DiskCandidate]) -> [Disk] {
        candidates
            .filter(isEligible)
            .sorted { $0.bsdName < $1.bsdName }
            .map { c in
                Disk(id: c.wholeDiskBSDName,
                     volumeName: c.volumeName,
                     model: c.deviceModel,
                     sizeBytes: c.sizeBytes,
                     busProtocol: c.busProtocol)
            }
    }
}
