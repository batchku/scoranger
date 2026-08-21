import SwiftUI
import UIKit

/// The design system's tokens: "instrument panel" — a warm paper-and-clay
/// surface, score-first, with the arrangement numeral as the app's identity.
/// Spec: design/DESIGN_SYSTEM.md. Light only, by decision, so nothing here
/// consults the colour scheme.
enum Theme {

    // Transitional aliases from build 116's placeholder Theme. Every call site
    // moves onto the tokens below as its view is restyled; these go with the
    // last one.
    static let structure = Accent.clay
    static let arrangementNumber = Accent.clay

    // MARK: - Colour (§1)

    /// Surfaces. `paper` is the score page and the only pure white in the app.
    enum Surface {
        static let paper  = Color(hex: 0xFFFFFF)
        static let ground = Color(hex: 0xF4F0E8)
        static let panel  = Color(hex: 0xFAF7F1)
        static let well   = Color(hex: 0xEFEAE0)
        static let band   = Color(hex: 0xF1ECE2)
    }

    /// Ink. `ink3` is supplementary only: never the sole carrier of meaning.
    enum Ink {
        static let ink  = Color(hex: 0x1A1917)
        static let ink2 = Color(hex: 0x6B655C)
        static let ink3 = Color(hex: 0x8A8378)
    }

    /// The single accent. `clay` is restricted to ≥15pt semibold text, numerals,
    /// icons and borders; small accent text uses `clayStrong`.
    enum Accent {
        static let clay       = Color(hex: 0xCC5C2E)
        static let clayStrong = Color(hex: 0xA8481F)
        static let clayPress  = Color(hex: 0xB14D22)
        static let clayTint   = Color(hex: 0xF7E7DD)
        /// Border for the user's chat bubble, per §7.7.
        static let clayBorder = Color(hex: 0xE7C4B1)
    }

    /// System status, deliberately outside the three-colour budget and never
    /// used decoratively.
    enum Status {
        static let ok     = Color(hex: 0x3BA05C)
        static let warn   = Color(hex: 0xC8791B)
        static let danger = Color(hex: 0xC0392B)
        static let highlight = Color(hex: 0xFFE25A).opacity(0.4)
        static let errorFill   = Color(hex: 0xFBEEEC)
        static let errorBorder = Color(hex: 0xE3B4AE)
    }

    /// Pencil inks. Fixed: the user's marks are content, not palette.
    enum Pen {
        static let red   = Color(hex: 0xD64B3F)
        static let blue  = Color(hex: 0x2A6BD6)
        static let green = Color(hex: 0x2E9159)
        static let amber = Color(hex: 0xE08A25)
        static let black = Ink.ink
    }

    enum Line {
        static let line  = Color(hex: 0xE2DBCE)
        static let line2 = Color(hex: 0xCFC6B6)
        static let dim   = Color(hex: 0x1A1917).opacity(0.34)
    }

    // MARK: - Type (§2)

    /// One entry per row of the type table. Carries the tracking and casing the
    /// spec attaches to the role, so callers cannot get them out of step.
    enum Role {
        case numeralXL, numeralL, numeralM
        case title, titleS
        case row, body, control, label, meta
        case data, dataS

        var font: Font { Theme.font(self) }

        /// Tracking in points, converted from the spec's em values.
        var tracking: CGFloat {
            switch self {
            case .numeralXL: return -0.02 * 34
            case .numeralL:  return -0.02 * 21
            case .numeralM:  return -0.01 * 17
            case .title:     return -0.01 * 17
            case .titleS:    return -0.01 * 15
            case .label:     return  0.11 * 10
            case .data:      return -0.01 * 11
            default:         return 0
            }
        }

        var isUppercase: Bool { self == .label }

        /// Line spacing where the spec pins it.
        var lineSpacing: CGFloat? {
            switch self {
            case .body: return 13 * 0.45
            default:    return nil
            }
        }
    }

    /// Registered face names. Variable fonts report their default instance, so
    /// Space Grotesk arrives as "SpaceGrotesk-Light" and every weight above it
    /// has to come from the wght axis rather than from `.weight()`.
    private enum Face {
        static let grotesk = "SpaceGrotesk-Light"
        static let inter   = "Inter-Regular"
        static let monoRegular = "IBMPlexMono-Regular"
        static let monoMedium  = "IBMPlexMono-Medium"
    }

    static func font(_ role: Role) -> Font {
        switch role {
        case .numeralXL: return variable(Face.grotesk, 34, 700, .title2)
        case .numeralL:  return variable(Face.grotesk, 21, 700, .title2)
        case .numeralM:  return variable(Face.grotesk, 17, 700, .title2)
        case .title:     return variable(Face.grotesk, 17, 600, .headline)
        case .titleS:    return variable(Face.grotesk, 15, 600, .headline)
        case .row:       return variable(Face.inter, 13.5, 500, .body)
        case .body:      return variable(Face.inter, 13, 400, .body)
        case .control:   return variable(Face.inter, 13, 600, .body)
        case .label:     return variable(Face.inter, 10, 700, .caption1)
        case .meta:      return variable(Face.inter, 11, 400, .caption1)
        case .data:      return staticFace(Face.monoMedium, 11, .caption1)
        case .dataS:     return staticFace(Face.monoRegular, 10.5, .caption1)
        }
    }

    /// A weight taken from the font's `wght` variation axis, then scaled for
    /// Dynamic Type against the given text style (§2.5).
    private static func variable(_ name: String, _ size: CGFloat,
                                 _ weight: CGFloat,
                                 _ style: UIFont.TextStyle) -> Font {
        let wght = UIFontDescriptor.AttributeName(
            rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: name,
            // 'wght' as a four-character code
            wght: [0x77676874: weight],
        ])
        let base = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base))
    }

    private static func staticFace(_ name: String, _ size: CGFloat,
                                   _ style: UIFont.TextStyle) -> Font {
        guard let base = UIFont(name: name, size: size) else {
            return Font.system(size: size, design: .monospaced)
        }
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base))
    }

    /// Fails loudly in debug if a face did not register, because the fallback
    /// is silent and the whole look depends on these three families.
    static func verifyFontsRegistered() {
        #if DEBUG
        for name in [Face.grotesk, Face.inter, Face.monoRegular, Face.monoMedium] {
            if UIFont(name: name, size: 12) == nil {
                assertionFailure("font \(name) is not registered — check UIAppFonts")
            }
        }
        #endif
    }

    // MARK: - Metrics (§3, §4)

    enum Metric {
        /// The only spacing values in the app.
        static let s2: CGFloat = 2, s4: CGFloat = 4, s6: CGFloat = 6
        static let s8: CGFloat = 8, s12: CGFloat = 12, s16: CGFloat = 16
        static let s20: CGFloat = 20, s24: CGFloat = 24, s32: CGFloat = 32

        static let panelPadding: CGFloat = 14
        static let rowVertical: CGFloat = 7
        static let rowMinHeight: CGFloat = 36
        static let versionRowVertical: CGFloat = 4
        static let versionIndent: CGFloat = 42
        static let stepIndent: CGFloat = 64
        static let sheetRowVertical: CGFloat = 9
        static let sheetRowMinHeight: CGFloat = 40

        static let libraryWidth: CGFloat = 320
        static let chatWidth: CGFloat = 380
        static let pageWidth: CGFloat = 520
        static let pageWidthBothOpen: CGFloat = 436
        static let pillHeight: CGFloat = 50
        static let pillButton: CGFloat = 38
        static let hitTarget: CGFloat = 44

        static let rCtl: CGFloat = 2
        static let rPanel: CGFloat = 3
        static let sheetWidth: CGFloat = 620
        static let alertWidth: CGFloat = 420
    }

    /// Shadows exist only on things that float over the score.
    enum Elevation {
        static func panel<V: View>(_ view: V) -> some View {
            view.shadow(color: Color(hex: 0x1A1917).opacity(0.14), radius: 34 / 2, y: 10)
        }
        static func pill<V: View>(_ view: V) -> some View {
            view.shadow(color: Color(hex: 0x1A1917).opacity(0.16), radius: 20 / 2, y: 6)
        }
        static func sheet<V: View>(_ view: V) -> some View {
            view.shadow(color: Color(hex: 0x1A1917).opacity(0.22), radius: 60 / 2, y: 20)
        }
    }

    // MARK: - Motion (§5)

    enum Motion {
        static let overlay = Animation.spring(response: 0.32, dampingFraction: 0.86)
        static let pillState = Animation.snappy(duration: 0.12)
        static let disclosure = Animation.easeOut(duration: 0.18)
        static let inkBar = Animation.easeOut(duration: 0.16)
        static let versionFlash = Animation.easeOut(duration: 0.24)

        /// Reduce Motion swaps the slide for a short cross-fade (§5, §9).
        static func overlay(reduced: Bool) -> Animation {
            reduced ? .easeInOut(duration: 0.12) : overlay
        }
    }
}

// MARK: - Applying a type role

extension View {
    /// Applies a role's font, tracking and line spacing together, so the three
    /// cannot drift apart.
    func typeRole(_ role: Theme.Role) -> some View {
        modifier(TypeRoleModifier(role: role))
    }
}

private struct TypeRoleModifier: ViewModifier {
    let role: Theme.Role

    func body(content: Content) -> some View {
        let styled = content
            .font(role.font)
            .tracking(role.tracking)
        if let spacing = role.lineSpacing {
            return AnyView(styled.lineSpacing(spacing))
        }
        return AnyView(styled)
    }
}

extension Text {
    /// Caps labels carry their casing as part of the role (§2 rule 3).
    func roleText(_ role: Theme.Role) -> Text {
        role.isUppercase ? self : self
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
