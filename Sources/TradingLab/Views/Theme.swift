import SwiftUI

/// Architectural Fintech Design System for MSNR Desk:
/// Obsidian Dark & Warm Swiss Alabaster Light, anchored by MSNR Signature Brass Gold
/// and crisp institutional Emerald / Crimson semantics with sharp 4–8pt geometry.
struct AppTheme {
    let isDark: Bool

    // MARK: - Surface Hierarchy
    var canvasBg: Color {
        isDark
            ? Color(red: 0.047, green: 0.051, blue: 0.060)   // #0C0D0F Obsidian canvas
            : Color(red: 0.961, green: 0.957, blue: 0.945)   // #F5F4F1 Warm Alabaster
    }

    var chartBg: Color {
        isDark
            ? Color(red: 0.035, green: 0.038, blue: 0.045)   // #090A0C Deep chart ground
            : Color(red: 0.992, green: 0.988, blue: 0.980)   // #FDFCFA Editorial paper
    }

    var chromeBg: Color {
        isDark
            ? Color(red: 0.063, green: 0.068, blue: 0.080)   // #101114 Chrome / Docked panels
            : Color(red: 0.984, green: 0.980, blue: 0.973)   // #FBFAF8 Warm off-white
    }

    var sidebarBg: Color {
        isDark
            ? Color(red: 0.055, green: 0.059, blue: 0.070)   // #0E0F12 Quiet nav rail
            : Color(red: 0.973, green: 0.969, blue: 0.957)   // #F8F7F4 Stone rail
    }

    var cardBg: Color {
        isDark
            ? Color(red: 0.078, green: 0.084, blue: 0.098)   // #141519 Elevated panel
            : Color.white                                     // Pure crisp surface
    }

    var softSurface: Color {
        isDark
            ? Color.white.opacity(0.055)
            : Color(red: 0.933, green: 0.925, blue: 0.906)   // #EEECE7 Warm stone pill
    }

    // MARK: - Hairlines & Grid
    var border: Color {
        isDark
            ? Color.white.opacity(0.088)
            : Color(red: 0.886, green: 0.875, blue: 0.847)   // #E2DFD8 Warm hairline
    }

    var gridLine: Color {
        isDark ? Color.white.opacity(0.042) : Color.black.opacity(0.045)
    }

    // MARK: - Ink Hierarchy
    var primaryText: Color {
        isDark
            ? Color(red: 0.945, green: 0.945, blue: 0.940)   // #F1F1F0 Soft crisp white
            : Color(red: 0.082, green: 0.082, blue: 0.078)   // #151514 Architectural ink
    }

    var secondaryText: Color {
        isDark
            ? Color(red: 0.56, green: 0.58, blue: 0.62)      // #8F949E Muted slate
            : Color(red: 0.43, green: 0.42, blue: 0.39)      // #6E6B64 Warm muted stone
    }

    // MARK: - Brand & Semantic Accents
    /// Signature MSNR Desk Brass Gold (replaces generic blue chrome)
    var accent: Color {
        isDark
            ? Color(red: 0.831, green: 0.643, blue: 0.282)   // #D4A448 Luminous brass
            : Color(red: 0.635, green: 0.443, blue: 0.118)   // #A2711E Deep architectural gold
    }

    /// Secondary cool telemetry tint for chart fast EMA / reference accents
    var telemetryBlue: Color {
        isDark
            ? Color(red: 0.31, green: 0.64, blue: 0.96)
            : Color(red: 0.16, green: 0.42, blue: 0.82)
    }

    var bull: Color {
        isDark
            ? Color(red: 0.10, green: 0.78, blue: 0.52)      // #1AC785 Institutional emerald
            : Color(red: 0.05, green: 0.56, blue: 0.36)      // #0D8F5C Deep emerald
    }

    var bear: Color {
        isDark
            ? Color(red: 0.92, green: 0.31, blue: 0.39)      // #EB4F63 Institutional crimson
            : Color(red: 0.80, green: 0.18, blue: 0.25)      // #CC2E40 Crisp crimson
    }

    var amber: Color {
        isDark
            ? Color(red: 0.94, green: 0.68, blue: 0.22)      // #F0AD38 Warm ochre
            : Color(red: 0.76, green: 0.46, blue: 0.04)      // #C2750A Burnished ochre
    }

    // MARK: - Sharp Fintech Geometry Tokens
    var radiusSharp: CGFloat { 4 }
    var radiusControl: CGFloat { 6 }
    var radiusPanel: CGFloat { 8 }
}
