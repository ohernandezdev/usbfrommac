import SwiftUI
import AppKit

/// Sistema de diseño de WinUSB Mac.
///
/// Lenguaje visual: macOS nativo moderno (estilo Sonoma / Raycast / Linear) —
/// superficies redondeadas con profundidad por sombra suave (no hairlines duros),
/// tipografía del sistema (SF Pro) con peso real, un acento azul vibrante, y aire
/// generoso. Todos los tokens se adaptan a claro/oscuro.
///
/// (El nombre `Carbon` se conserva por compatibilidad de API; el lenguaje ya no
/// es el IBM Carbon plano original.)
enum Carbon {

    // MARK: Colores (dinámicos claro/oscuro)

    /// Fondo de la ventana (ligeramente teñido para que las tarjetas blancas floten).
    static let canvas         = Color(light: 0xF2F3F5, dark: 0x1A1A1C)
    /// Superficie de tarjeta / control (flota sobre el canvas).
    static let surface1       = Color(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let surface2       = Color(light: 0xEDEEF1, dark: 0x37373B)
    /// Separadores muy sutiles (casi imperceptibles, no líneas duras).
    static let hairline       = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.07)
    static let hairlineStrong = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.14)

    static let ink            = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let inkMuted       = Color(light: 0x6E6E73, dark: 0xAEAEB2)
    static let inkSubtle      = Color(light: 0x8A8A8F, dark: 0x8A8A8F)

    /// Acento principal (azul vivo del sistema).
    static let primary        = Color(light: 0x0A84FF, dark: 0x0A84FF)
    static let primaryDeep    = Color(light: 0x0060DF, dark: 0x0060DF)
    static let success        = Color(light: 0x1FA34B, dark: 0x30D158)
    static let warning        = Color(light: 0xE08600, dark: 0xFFD60A)
    static let error          = Color(light: 0xE5342B, dark: 0xFF453A)
    static let onPrimary      = Color(hex: 0xFFFFFF)
    static let inverseCanvas  = Color(light: 0x1D1D1F, dark: 0xF5F5F7)

    /// Degradado del botón/acento primario (sutil, da volumen sin estridencia).
    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x2D95FF), Color(hex: 0x0A6CFF)],
                       startPoint: .top, endPoint: .bottom)
    }
    static var dangerGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xFF5247), Color(hex: 0xE5342B)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Espaciado (rejilla de 4 px)

    enum Space {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Radios de esquina

    enum Radius {
        static let chip:   CGFloat = 8
        static let control: CGFloat = 10
        static let card:   CGFloat = 16
        static let pill:   CGFloat = 999
    }

    // MARK: Movimiento (respeta Reducir movimiento)

    enum Motion {
        static let fast     = Animation.easeOut(duration: 0.16)
        static let standard = Animation.spring(response: 0.36, dampingFraction: 0.84)
        static func resolve(_ animation: Animation, reduce: Bool) -> Animation? {
            reduce ? nil : animation
        }
    }
}

// MARK: - Sombras (elevación suave)

extension View {
    /// Sombra de tarjeta flotante (suave, difusa, nunca dura).
    func cardShadow(_ scheme: ColorScheme) -> some View {
        shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.10),
               radius: 14, x: 0, y: 6)
    }
    /// Sombra coloreada para el CTA primario (le da presencia).
    func glowShadow(_ color: Color, _ scheme: ColorScheme) -> some View {
        shadow(color: color.opacity(scheme == .dark ? 0.35 : 0.28), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Tipografía (SF Pro del sistema)

enum CarbonText {
    case displayMd, headline, cardTitle, subhead, bodyLg, body, bodySm, bodyEmphasis, caption, button

    var size: CGFloat {
        switch self {
        case .displayMd:    return 30
        case .headline:     return 22
        case .cardTitle:    return 17
        case .subhead:      return 15
        case .bodyLg:       return 16
        case .body:         return 14
        case .bodySm:       return 13
        case .bodyEmphasis: return 13
        case .caption:      return 12
        case .button:       return 14
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayMd:    return .bold
        case .headline:     return .bold
        case .cardTitle:    return .semibold
        case .subhead:      return .semibold
        case .bodyEmphasis: return .semibold
        case .button:       return .semibold
        case .caption:      return .medium
        default:            return .regular
        }
    }

    /// Tracking ligeramente negativo en títulos = look moderno y compacto.
    var tracking: CGFloat {
        switch self {
        case .displayMd: return -0.4
        case .headline:  return -0.3
        case .caption:   return 0.1
        default:         return 0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .bodyLg, .body, .bodySm: return 3.5
        default: return 1
        }
    }

    var font: Font { .system(size: size, weight: weight) }
}

extension View {
    func carbon(_ style: CarbonText) -> some View {
        self.font(style.font).tracking(style.tracking).lineSpacing(style.lineSpacing)
    }

    /// Cursor de mano al pasar por encima (controles clicables en desktop).
    func pointingCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Color desde hex (estático y dinámico claro/oscuro)

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Color que cambia con la apariencia del sistema (claro/oscuro).
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Botones (redondeados, con relieve y estados suaves)

struct CarbonButton: ButtonStyle {
    enum Kind { case primary, secondary, tertiary, ghost, danger }
    var kind: Kind = .primary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        CarbonButtonBody(kind: kind, fullWidth: fullWidth,
                         pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct CarbonButtonBody<Label: View>: View {
    let kind: CarbonButton.Kind
    let fullWidth: Bool
    let pressed: Bool
    let label: Label
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var filled: Bool { kind == .primary || kind == .danger }

    var body: some View {
        label
            .carbon(.button)
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(backgroundView)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous))
            .modifier(ButtonElevation(kind: kind, enabled: isEnabled, scheme: scheme))
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Carbon.Motion.fast, value: hovering)
            .animation(Carbon.Motion.fast, value: pressed)
            .onHover { hovering = $0 && isEnabled }
            .pointingCursor()
    }

    @ViewBuilder private var backgroundView: some View {
        switch kind {
        case .primary:
            ZStack { Carbon.primaryGradient; if hovering { Color.white.opacity(0.10) }; if pressed { Color.black.opacity(0.14) } }
        case .danger:
            ZStack { Carbon.dangerGradient; if hovering { Color.white.opacity(0.10) }; if pressed { Color.black.opacity(0.14) } }
        case .secondary:
            (hovering ? Carbon.surface2 : Carbon.surface1)
        case .tertiary:
            (pressed ? Carbon.primary.opacity(0.18) : (hovering ? Carbon.primary.opacity(0.10) : Carbon.primary.opacity(0.05)))
        case .ghost:
            (pressed ? Carbon.surface2 : (hovering ? Carbon.surface1 : Color.clear))
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return Carbon.onPrimary
        case .secondary:        return Carbon.ink
        case .tertiary, .ghost: return Carbon.primary
        }
    }

    @ViewBuilder private var borderOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous)
        switch kind {
        case .secondary: shape.stroke(Carbon.hairlineStrong, lineWidth: 1)
        case .tertiary:  shape.stroke(Carbon.primary.opacity(0.4), lineWidth: 1)
        default:         EmptyView()
        }
    }
}

/// Sombra/elevación del botón según su tipo (solo los rellenos "flotan").
private struct ButtonElevation: ViewModifier {
    let kind: CarbonButton.Kind
    let enabled: Bool
    let scheme: ColorScheme
    func body(content: Content) -> some View {
        switch (kind, enabled) {
        case (.primary, true): content.glowShadow(Carbon.primary, scheme)
        case (.danger, true):  content.glowShadow(Carbon.error, scheme)
        default:               content
        }
    }
}

// MARK: - Campo de texto (redondeado, relleno suave, foco con anillo azul)

struct CarbonTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var monospaced = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 13, design: .monospaced) : .system(size: 14))
            .foregroundStyle(Carbon.ink)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Carbon.surface1)
            .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous)
                    .stroke(focused ? Carbon.primary : Carbon.hairlineStrong,
                            lineWidth: focused ? 2 : 1)
            )
            .focused($focused)
            .animation(Carbon.Motion.fast, value: focused)
    }
}

// MARK: - Tarjeta (superficie redondeada con sombra suave, sin hairline duro)

private struct CarbonCard: ViewModifier {
    let surface: Color
    let padding: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Carbon.Radius.card, style: .continuous)
                    .stroke(Carbon.hairline, lineWidth: 1)
            )
            .cardShadow(scheme)
    }
}

extension View {
    /// Contenedor de tarjeta: superficie redondeada con sombra suave.
    func carbonCard(surface: Color = Carbon.surface1,
                    padding: CGFloat = Carbon.Space.lg) -> some View {
        modifier(CarbonCard(surface: surface, padding: padding))
    }
}
