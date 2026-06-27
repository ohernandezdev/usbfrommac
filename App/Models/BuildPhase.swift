import Foundation

/// Fases del proceso de creación del USB (orden y peso para la barra global).
public enum BuildPhase: Equatable {
    case idle
    case formatting     // Formatear (root, vía helper)        — flujo Windows
    case copying        // Copiar archivos del ISO (menos install.wim) — flujo Windows
    case splitting      // Dividir install.wim en .swm           — flujo Windows
    case writingImage   // Escribir el ISO crudo (dd) al disco    — flujo Linux/raw
    case finalizing     // Desmontar ISO + expulsar USB           — ambos flujos
    case done
    case failed(String)
    case cancelled

    /// Fases del flujo Windows (copia a FAT32), en orden.
    public static let ordered: [BuildPhase] = [.formatting, .copying, .splitting, .finalizing]

    /// Fases del flujo raw (Linux/isohíbrido), en orden.
    public static let rawOrdered: [BuildPhase] = [.writingImage, .finalizing]

    /// Título legible para la UI (localizado ES/EN vía String Catalog).
    public var title: String {
        switch self {
        case .idle:         return loc("phase.idle")
        case .formatting:   return loc("phase.formatting")
        case .copying:      return loc("phase.copying")
        case .splitting:    return loc("phase.splitting")
        case .writingImage: return loc("phase.writingImage")
        case .finalizing:   return loc("phase.finalizing")
        case .done:         return loc("phase.done")
        case .failed:       return loc("phase.failed")
        case .cancelled:    return loc("phase.cancelled")
        }
    }

    /// Peso relativo en la barra de progreso global.
    /// `finalizing` vale 0.05 en ambos flujos y siempre cierra el último tramo
    /// (Windows: tras splitting; raw: tras writingImage) → arranca en 0.95.
    public var weight: Double {
        switch self {
        case .formatting:   return 0.05
        case .copying:      return 0.60
        case .splitting:    return 0.30
        case .writingImage: return 0.95
        case .finalizing:   return 0.05
        default:            return 0
        }
    }
}
