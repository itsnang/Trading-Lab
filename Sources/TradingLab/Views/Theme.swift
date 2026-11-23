import SwiftUI

struct AppTheme {
    let isDark: Bool

    var canvasBg: Color {
        isDark ? Color(red: 0.055, green: 0.065, blue: 0.088) : Color(red: 0.965, green: 0.972, blue: 0.982)
    }

    var chartBg: Color {
        isDark ? Color(red: 0.050, green: 0.058, blue: 0.080) : Color.white
    }

    var chromeBg: Color {
        isDark ? Color(red: 0.075, green: 0.085, blue: 0.110) : Color.white
    }

    var sidebarBg: Color {
        isDark ? Color(red: 0.065, green: 0.075, blue: 0.098) : Color(red: 0.975, green: 0.980, blue: 0.988)
    }

    var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.108, blue: 0.140) : Color.white
    }

    var softSurface: Color {
        isDark ? Color.white.opacity(0.06) : Color(red: 0.945, green: 0.955, blue: 0.970)
    }

    var border: Color {
        isDark ? Color.white.opacity(0.10) : Color(red: 0.87, green: 0.89, blue: 0.92)
    }

    var gridLine: Color {
        isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.055)
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.94) : Color(red: 0.09, green: 0.11, blue: 0.15)
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.56) : Color(red: 0.40, green: 0.45, blue: 0.52)
    }

    var accent: Color {
        isDark ? Color(red: 0.25, green: 0.65, blue: 0.98) : Color(red: 0.14, green: 0.39, blue: 0.88)
    }

    var bull: Color {
        isDark ? Color(red: 0.14, green: 0.82, blue: 0.54) : Color(red: 0.06, green: 0.65, blue: 0.42)
    }

    var bear: Color {
        isDark ? Color(red: 0.94, green: 0.33, blue: 0.43) : Color(red: 0.86, green: 0.22, blue: 0.30)
    }

    var amber: Color {
        isDark ? Color(red: 0.96, green: 0.72, blue: 0.20) : Color(red: 0.85, green: 0.54, blue: 0.05)
    }
}
