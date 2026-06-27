import Foundation
import SwiftUI

/// Idioma de la interfaz elegido por el usuario (in-app, no el del sistema).
public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case es

    public var id: String { rawValue }

    /// Nombre del idioma en su propio idioma (para el selector).
    public var displayName: String {
        switch self {
        case .system: return loc("lang.system")
        case .en:     return "English"
        case .es:     return "Español"
        }
    }
}

/// Fuente de verdad del idioma de la UI. Permite forzar ES/EN en vivo (sin
/// reiniciar) sobre el idioma del sistema. Singleton para que el helper global
/// `loc(_:)` —usado por modelos y servicios— resuelva en el idioma elegido, y a
/// la vez `ObservableObject` para que SwiftUI re-renderice al cambiarlo.
public final class LocalizationStore: ObservableObject {
    public static let shared = LocalizationStore()

    private static let key = "appLanguage"

    @Published public var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// Locale efectivo (para `.environment(\.locale,)` y para `loc(_:)`).
    public var locale: Locale {
        switch language {
        case .system: return Locale.autoupdatingCurrent
        case .en, .es: return Locale(identifier: language.rawValue)
        }
    }

    /// Bundle de recursos del idioma elegido (el `.lproj` correspondiente), o el
    /// bundle principal cuando se sigue al sistema. NO hay fallback silencioso: si
    /// el `.lproj` no existiera, se usa el bundle principal (que resuelve por el
    /// idioma del sistema), nunca una cadena vacía.
    public var bundle: Bundle {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let b = Bundle(path: path)
        else { return .main }
        return b
    }
}

/// Traducción que respeta el idioma elegido en `LocalizationStore`. Equivalente a
/// `String(localized:)` pero forzando bundle+locale del idioma in-app, de modo que
/// los textos programáticos (errores, progreso) cambien junto con la UI.
public func loc(_ key: String.LocalizationValue) -> String {
    let store = LocalizationStore.shared
    return String(localized: key, bundle: store.bundle, locale: store.locale)
}
