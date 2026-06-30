import Foundation

/// Phases of the USB creation process (order and weight for the global bar).
public enum BuildPhase: Equatable {
    case idle
    case formatting     // Format (root, via helper)             — Windows flow
    case copying        // Copy ISO files (except install.wim)   — Windows flow
    case splitting      // Split install.wim into .swm           — Windows flow
    case writingImage   // Write the raw ISO (dd) to the disk    — Linux/raw flow
    case finalizing     // Unmount ISO + eject USB               — both flows
    case done
    case failed(String)
    case cancelled

    /// Windows-flow phases (copy to FAT32), in order.
    public static let ordered: [BuildPhase] = [.formatting, .copying, .splitting, .finalizing]

    /// Raw-flow phases (Linux/isohybrid), in order.
    public static let rawOrdered: [BuildPhase] = [.writingImage, .finalizing]

    /// Phase sequence to show based on the ISO's boot type.
    public static func sequence(for bootType: ISOBootType) -> [BuildPhase] {
        switch bootType {
        case .windows:                  return ordered
        case .hybridRaw:                return rawOrdered
        case .elToritoOnly, .notBootable: return []
        }
    }

    /// Human-readable title for the UI (localized ES/EN via String Catalog).
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

    /// Relative weight in the global progress bar.
    /// `finalizing` is worth 0.05 in both flows and always closes the last segment
    /// (Windows: after splitting; raw: after writingImage) → starts at 0.95.
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
