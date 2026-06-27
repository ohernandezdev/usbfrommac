import Foundation

/// Fases del proceso de creación del USB (orden y peso para la barra global).
public enum BuildPhase: Equatable {
    case idle
    case formatting     // Formatear (root, vía helper)
    case copying        // Copiar archivos del ISO (menos install.wim)
    case splitting      // Dividir install.wim en .swm (o copiarlo si cabe)
    case finalizing     // Desmontar ISO + expulsar USB
    case done
    case failed(String)
    case cancelled

    /// Las fases activas, en orden.
    public static let ordered: [BuildPhase] = [.formatting, .copying, .splitting, .finalizing]

    /// Título legible para la UI (localizado ES/EN vía String Catalog).
    public var title: String {
        switch self {
        case .idle:       return loc("phase.idle")
        case .formatting: return loc("phase.formatting")
        case .copying:    return loc("phase.copying")
        case .splitting:  return loc("phase.splitting")
        case .finalizing: return loc("phase.finalizing")
        case .done:       return loc("phase.done")
        case .failed:     return loc("phase.failed")
        case .cancelled:  return loc("phase.cancelled")
        }
    }

    /// Peso relativo en la barra de progreso global (la copia es lo más lento).
    public var weight: Double {
        switch self {
        case .formatting: return 0.05
        case .copying:    return 0.60
        case .splitting:  return 0.30
        case .finalizing: return 0.05
        default:          return 0
        }
    }
}
