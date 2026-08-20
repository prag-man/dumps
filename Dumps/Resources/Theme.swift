import SwiftUI
import AppKit

// MARK: - Dumps Linear Theme
//
// Linear's visual language, translated for Dumps:
// - Near-black, not pure black. Warmth via +0.01 chroma, never neutral gray.
// - Borders are structure, not decoration. 0.5–1pt at white 6–9%.
// - Type is small, tracked, quiet. Uppercase labels carry the hierarchy.
// - Accent is rare: one indigo dot, one focused ring. Everything else is gray.
// - Density is high, spacing is tight, hover is the only shadow.

enum Theme {

    // MARK: - Palette

    // Window / content — #0E0E10 / #111113 range
    static let background = Color(red: 0.055, green: 0.055, blue: 0.060) // #0E0E0F
    static let backgroundElevated = Color(red: 0.078, green: 0.078, blue: 0.084) // #141418
    static let sidebar = Color(red: 0.039, green: 0.039, blue: 0.043) // #0A0A0B — a touch darker than content
    static let panel = Color(red: 0.090, green: 0.090, blue: 0.095) // capture surface — #17171A
    static let card = Color.white.opacity(0.035)
    static let cardHover = Color.white.opacity(0.055)

    // Borders
    static let separator = Color.white.opacity(0.07)
    static let separatorStrong = Color.white.opacity(0.10)
    static let focusRing = Color(red: 0.37, green: 0.42, blue: 0.84) // Linear indigo #5E6AD2

    // Text — white with controlled opacity, never pure #FFF for body
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.45)
    static let textTertiary = Color.white.opacity(0.32)
    static let textQuaternary = Color.white.opacity(0.22)

    // Accent — single indigo for the active-bucket dot and focus states
    static let accent = Color(red: 0.368, green: 0.418, blue: 0.824) // #5E6AD2
    static let accentMuted = Color(red: 0.368, green: 0.418, blue: 0.824).opacity(0.18)

    // MARK: - Light fallback (respects system when appearance == light)
    // Kept intentionally minimal; library respects system via environment.

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? background : Color(nsColor: .windowBackgroundColor)
    }
    static func sidebar(for scheme: ColorScheme) -> Color {
        scheme == .dark ? sidebar : Color(nsColor: .controlBackgroundColor)
    }
}

// MARK: - Typography

enum DumpsType {
    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Metrics

enum DumpsMetrics {
    static let panelWidth: CGFloat = 480
    static let sidebarWidth: CGFloat = 220
    static let rowRadius: CGFloat = 6
    static let panelRadius: CGFloat = 10
    static let hairline: CGFloat = 0.5
}

// MARK: - View helpers

extension View {
    var hairlineBorder: some View {
        overlay(
            RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: DumpsMetrics.hairline)
        )
    }
    var linearCard: some View {
        background(
            RoundedRectangle(cornerRadius: DumpsMetrics.rowRadius, style: .continuous)
                .fill(Theme.card)
        )
        .hairlineBorder
    }
}
