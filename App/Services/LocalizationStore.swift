import Foundation
import SwiftUI

/// Interface language chosen by the user (in-app, not the system one).
public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case es

    public var id: String { rawValue }

    /// Name of the language in its own language (for the selector).
    public var displayName: String {
        switch self {
        case .system: return loc("lang.system")
        case .en:     return "English"
        case .es:     return "Español"
        }
    }
}

/// Source of truth for the UI language. Lets you force ES/EN live (without
/// restarting) over the system language. A singleton so the global helper
/// `loc(_:)` —used by models and services— resolves in the chosen language, and
/// at the same time an `ObservableObject` so SwiftUI re-renders when it changes.
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

    /// Effective locale (for `.environment(\.locale,)` and for `loc(_:)`).
    public var locale: Locale {
        switch language {
        case .system: return Locale.autoupdatingCurrent
        case .en, .es: return Locale(identifier: language.rawValue)
        }
    }

    /// Resource bundle for the chosen language (the matching `.lproj`), or the
    /// main bundle when following the system. There's NO silent fallback: if the
    /// `.lproj` didn't exist, the main bundle is used (which resolves by the system
    /// language), never an empty string.
    public var bundle: Bundle {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let b = Bundle(path: path)
        else { return .main }
        return b
    }
}

/// Translation that respects the language chosen in `LocalizationStore`. Equivalent
/// to `String(localized:)` but forcing the in-app language's bundle+locale, so that
/// programmatic text (errors, progress) changes along with the UI.
public func loc(_ key: String.LocalizationValue) -> String {
    let store = LocalizationStore.shared
    return String(localized: key, bundle: store.bundle, locale: store.locale)
}
