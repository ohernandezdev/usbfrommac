import SwiftUI
import AppKit

/// Flint design system.
///
/// Visual language: Vercel-inspired (Geist) — near-white/near-black canvas,
/// a single ink primary reserved for CTAs, a deliberate gray scale, flat
/// surfaces (no gradients), stacked soft shadows + hairline rings on cards,
/// and restrained, high-contrast typography with negative tracking on
/// headings. Every token adapts to light/dark.
///
/// (The `Carbon` name is kept for API compatibility across the app.)
enum Carbon {

    // MARK: Colors (light/dark dynamic)

    /// Page background (canvas-soft).
    static let canvas         = Color(light: 0xFAFAFA, dark: 0x000000)
    /// Card / control surface (floats above the canvas).
    static let surface1       = Color(light: 0xFFFFFF, dark: 0x0A0A0A)
    /// Inset surface: hover fills, code blocks, dropdowns.
    static let surface2       = Color(light: 0xF5F5F5, dark: 0x1A1A1A)
    /// Subtle hairline dividers and borders. 0.08 (the literal Vercel token value)
    /// read as nearly invisible on card outlines in practice — bumped for legibility.
    static let hairline       = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.14)
    /// Stronger hairline: input borders, unselected controls.
    static let hairlineStrong = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.18)

    static let ink            = Color(light: 0x171717, dark: 0xEDEDED)
    static let inkMuted        = Color(light: 0x4D4D4D, dark: 0xA1A1A1)
    static let inkSubtle       = Color(light: 0x8F8F8F, dark: 0x8A8A8A)

    /// The single strong accent, reserved for primary CTAs (ink — never a brand blue).
    static let primary        = ink
    /// Text/icon on top of a primary-filled surface (flips polarity with `ink`).
    static let onPrimary      = Color(light: 0xFFFFFF, dark: 0x0A0A0A)

    /// Link / focus-ring / success accent — the only non-ink color in the system.
    static let link           = Color(light: 0x0070F3, dark: 0x3291FF)
    static let success        = link
    static let warning        = Color(light: 0xF5A623, dark: 0xF7B955)
    static let error          = Color(light: 0xEE0000, dark: 0xFF6166)

    // MARK: Spacing (strict 4px grid)

    enum Space {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Corner radii — one family per view (sm for controls, md for cards)

    enum Radius {
        /// Everyday UI: buttons, inputs, nav chips.
        static let control: CGFloat = 6
        /// Small icon swatches / chips.
        static let chip:    CGFloat = 8
        /// Cards and elevated containers.
        static let card:    CGFloat = 10
        /// Marketing-scale pill (unused in this compact desktop UI, kept for API parity).
        static let pill:    CGFloat = 999
    }

    // MARK: Motion (short, physical, respects Reduce Motion)

    enum Motion {
        static let fast     = Animation.easeOut(duration: 0.15)
        static let standard = Animation.timingCurve(0.175, 0.885, 0.32, 1.1, duration: 0.28)
        static func resolve(_ animation: Animation, reduce: Bool) -> Animation? {
            reduce ? nil : animation
        }
    }
}

// MARK: - Shadows (stacked soft elevation, never a single heavy drop shadow)

extension View {
    /// Card elevation: a tight contact shadow + a soft diffuse shadow, stacked.
    /// Pair with a hairline stroke overlay for the signature inset ring.
    func cardShadow(_ scheme: ColorScheme) -> some View {
        self
            .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.05), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.08), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Typography (system SF Pro — Geist-equivalent geometric sans)

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

    /// Max weight is 600 (semibold) — never bold — per the Vercel-inspired type rules.
    var weight: Font.Weight {
        switch self {
        case .displayMd:    return .semibold
        case .headline:     return .semibold
        case .cardTitle:    return .semibold
        case .subhead:      return .semibold
        case .bodyEmphasis: return .semibold
        case .button:       return .semibold
        case .caption:      return .medium
        default:            return .regular
        }
    }

    /// Aggressive negative tracking on display sizes, tapering off toward body text.
    var tracking: CGFloat {
        switch self {
        case .displayMd: return -1.2
        case .headline:  return -0.6
        case .cardTitle: return -0.2
        case .bodySm, .bodyEmphasis: return -0.14
        default: return 0
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

    /// Hand cursor on hover (for clickable desktop controls).
    func pointingCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Color from hex (static and light/dark dynamic)

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Color that follows the system appearance (light/dark).
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

// MARK: - Buttons (flat fills, no gradients — the ink primary is the only strong color)

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

    var body: some View {
        label
            .carbon(.button)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(backgroundView)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous))
            .modifier(ButtonElevation(kind: kind, enabled: isEnabled, scheme: scheme))
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Carbon.Motion.fast, value: hovering)
            .animation(Carbon.Motion.fast, value: pressed)
            .onHover { hovering = $0 && isEnabled }
            .pointingCursor()
    }

    /// Ink's polarity flips between light/dark, so hover/press overlays must too:
    /// lighten a dark (light-mode) fill, darken a light (dark-mode) fill.
    private var hoverOverlay: Color { scheme == .dark ? .black.opacity(0.08) : .white.opacity(0.12) }
    private var pressedOverlay: Color { scheme == .dark ? .black.opacity(0.16) : .white.opacity(0.20) }

    @ViewBuilder private var backgroundView: some View {
        switch kind {
        case .primary:
            ZStack { Carbon.primary; if hovering { hoverOverlay }; if pressed { pressedOverlay } }
        case .danger:
            ZStack { Carbon.error; if hovering { Color.white.opacity(0.10) }; if pressed { Color.black.opacity(0.14) } }
        case .secondary:
            (hovering ? Carbon.surface2 : Carbon.surface1)
        case .tertiary:
            (pressed ? Carbon.surface2 : (hovering ? Carbon.surface2.opacity(0.6) : Color.clear))
        case .ghost:
            (pressed ? Carbon.surface2 : (hovering ? Carbon.surface1 : Color.clear))
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger:        return Carbon.onPrimary
        case .secondary, .tertiary, .ghost: return Carbon.ink
        }
    }

    @ViewBuilder private var borderOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous)
        switch kind {
        case .secondary: shape.strokeBorder(Carbon.hairlineStrong, lineWidth: 1)
        default:         EmptyView()
        }
    }
}

/// Subtle neutral elevation for filled buttons only (never a colored glow).
private struct ButtonElevation: ViewModifier {
    let kind: CarbonButton.Kind
    let enabled: Bool
    let scheme: ColorScheme
    func body(content: Content) -> some View {
        switch (kind, enabled) {
        case (.primary, true), (.danger, true):
            content.shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.12), radius: 6, x: 0, y: 2)
        default:
            content
        }
    }
}

// MARK: - Text field (flat fill, hairline border, link-blue focus ring)

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
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Carbon.surface1)
            .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous)
                    .strokeBorder(focused ? Carbon.link : Carbon.hairlineStrong,
                                  lineWidth: focused ? 2 : 1)
            )
            .focused($focused)
            .animation(Carbon.Motion.fast, value: focused)
    }
}

// MARK: - Card (flat surface, stacked shadow + inset hairline ring)

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
                    .strokeBorder(Carbon.hairline, lineWidth: 1)
            )
            .cardShadow(scheme)
    }
}

extension View {
    /// Card container: flat surface, radius `card`, stacked shadow + hairline ring.
    func carbonCard(surface: Color = Carbon.surface1,
                    padding: CGFloat = Carbon.Space.lg) -> some View {
        modifier(CarbonCard(surface: surface, padding: padding))
    }
}
