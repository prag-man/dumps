import SwiftUI
import AppKit

// MARK: - Dumps Silent Lift Theme
//
// Adaptive semantic design system. Every token has two faces:
//  - `static let foo`  — backwards-compat dark default (existing callers keep compiling)
//  - `static func foo(for scheme:)` — adaptive primary API
//
// Light values use black @ 85/55/35/22% for text, white capsule for capture.
// Dark values use white @ 92/45/32/22% for text, #1A1A1E for capture.
// Accent is a single consistent violet/indigo #5E6AD2 for dot, focus, glow.

enum Theme {

    // MARK: - Internal helper

    static func resolved(_ scheme: ColorScheme, light: Color, dark: Color) -> Color {
        scheme == .dark ? dark : light
    }

    // MARK: - Accent

    /// Primary accent — Silent Lift violet. Single consistent value (#5E6AD2) used for dot + focus.
    static let violet = Color(red: 0.368, green: 0.418, blue: 0.824) // #5E6AD2
    static let violetSoft = Color(red: 0.368, green: 0.418, blue: 0.824).opacity(0.18)
    static let violetGlow = Color(red: 0.368, green: 0.418, blue: 0.824).opacity(0.32)

    // Backwards-compat aliases
    static let accent = violet
    static let accentMuted = violetSoft
    static let focusRing = violet

    static func violet(for scheme: ColorScheme) -> Color { violet }
    static func violetSoft(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: violet.opacity(0.12), dark: violetSoft)
    }
    static func violetGlow(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: violet.opacity(0.22), dark: violetGlow)
    }
    static func accent(for scheme: ColorScheme) -> Color { violet(for: scheme) }
    static func focusRing(for scheme: ColorScheme) -> Color { violet }

    // MARK: - Surfaces

    // Base window / content
    static let background = Color(red: 0.055, green: 0.055, blue: 0.060) // #0E0E0F
    static let backgroundElevated = Color(red: 0.078, green: 0.078, blue: 0.084) // #141418
    static let sidebar = Color(red: 0.039, green: 0.039, blue: 0.043) // #0A0A0B
    static let panel = Color(red: 0.090, green: 0.090, blue: 0.095) // capture surface #17171A (legacy)
    static let card = Color.white.opacity(0.035)
    static let cardHover = Color.white.opacity(0.055)

    // Semantic surface aliases
    static let window = background
    static let raised = backgroundElevated
    static let hover = Color.white.opacity(0.055)
    static let selected = Color.white.opacity(0.09)
    /// Capture capsule fill — light: #FFFFFF, dark: #1A1A1E
    static let capture = Color.white
    static let captureDark = Color(red: 0.102, green: 0.102, blue: 0.118) // #1A1A1E

    // Adaptive surface funcs
    static func windowBackground(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color(nsColor: .windowBackgroundColor), dark: window)
    }
    static func window(for scheme: ColorScheme) -> Color { windowBackground(for: scheme) }

    static func sidebarBackground(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color(nsColor: .controlBackgroundColor).opacity(0.65), dark: sidebar)
    }
    static func sidebar(for scheme: ColorScheme) -> Color { sidebarBackground(for: scheme) }

    static func raisedBackground(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color(nsColor: .controlBackgroundColor), dark: raised)
    }
    static func raised(for scheme: ColorScheme) -> Color { raisedBackground(for: scheme) }

    static func hoverBackground(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.04), dark: hover)
    }
    static func hover(for scheme: ColorScheme) -> Color { hoverBackground(for: scheme) }

    static func selectedBackground(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.06), dark: selected)
    }
    static func selected(for scheme: ColorScheme) -> Color { selectedBackground(for: scheme) }

    static func captureBackground(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.white, dark: captureDark)
    }
    static func capture(for scheme: ColorScheme) -> Color { captureBackground(for: scheme) }

    static func card(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.04), dark: card)
    }
    static func cardHover(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.07), dark: cardHover)
    }

    // Legacy adaptive (kept for existing callers)
    static func background(for scheme: ColorScheme) -> Color { windowBackground(for: scheme) }
    static func backgroundElevated(for scheme: ColorScheme) -> Color { raisedBackground(for: scheme) }

    // MARK: - Text

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.45)
    static let textTertiary = Color.white.opacity(0.32)
    static let textQuaternary = Color.white.opacity(0.22)
    static let textDisabled = Color.white.opacity(0.22)

    static func textPrimary(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.85), dark: Color.white.opacity(0.92))
    }
    static func textSecondary(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.55), dark: Color.white.opacity(0.45))
    }
    static func textTertiary(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.35), dark: Color.white.opacity(0.32))
    }
    static func textQuaternary(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.22), dark: Color.white.opacity(0.22))
    }
    static func textDisabled(for scheme: ColorScheme) -> Color {
        textQuaternary(for: scheme)
    }

    // MARK: - Borders

    static let separator = Color.white.opacity(0.07)
    static let separatorStrong = Color.white.opacity(0.10)

    static let hairlineBorder = separator
    static let strongBorder = separatorStrong
    static let focusBorder = violet

    static func hairlineBorder(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color(nsColor: .separatorColor).opacity(0.65), dark: separator)
    }
    // Convenience aliases matching required token names
    static func borderHairline(for scheme: ColorScheme) -> Color { hairlineBorder(for: scheme) }
    static func hairline(for scheme: ColorScheme) -> Color { hairlineBorder(for: scheme) }

    static func strongBorder(for scheme: ColorScheme) -> Color {
        resolved(scheme, light: Color.black.opacity(0.12), dark: separatorStrong)
    }
    static func borderStrong(for scheme: ColorScheme) -> Color { strongBorder(for: scheme) }

    static func focusBorder(for scheme: ColorScheme) -> Color { violet }
    static func borderFocus(for scheme: ColorScheme) -> Color { focusBorder(for: scheme) }

    // Legacy border funcs
    static func separator(for scheme: ColorScheme) -> Color { hairlineBorder(for: scheme) }
    static func separatorStrong(for scheme: ColorScheme) -> Color { strongBorder(for: scheme) }
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
    // Capture (Silent Lift capsule)
    static let captureWidth: CGFloat = 480
    static let captureRadius: CGFloat = 10
    // Legacy alias
    static let panelWidth: CGFloat = captureWidth
    static let panelRadius: CGFloat = captureRadius

    // Library
    static let sidebarWidth: CGFloat = 220
    static let rowRadius: CGFloat = 6

    // Borders
    static let hairline: CGFloat = 0.5

    // Spacing — tight, Linear-like
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 20
    static let spacingXL: CGFloat = 28
}

// MARK: - Motion

enum DumpsMotion {
    /// Capture appear — spring, slightly bouncy but calm
    static let captureShow = Animation.spring(response: 0.30, dampingFraction: 0.82)
    static let captureHide = Animation.easeOut(duration: 0.16)
    static let bucketSwitch = Animation.easeOut(duration: 0.12)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Backwards-compat alias — existing capture code references `Motion.reduceMotion`.
typealias Motion = DumpsMotion

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
