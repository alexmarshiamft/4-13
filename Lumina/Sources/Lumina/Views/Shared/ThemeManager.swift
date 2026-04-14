// ThemeManager.swift – Dynamic theme system for Lumina
// Lumina: AI-powered reminders, task management, and focus app
//
// Themes:
//   - "Deep Space Dark": rich dark OLED-friendly palette
//   - "Minimalist Light": clean, soft-light palette
//   - System: follows macOS/iOS appearance

import SwiftUI

// MARK: - Theme
enum AppTheme: String, CaseIterable, Codable {
    case system       = "system"
    case deepSpaceDark = "deep_space_dark"
    case minimalistLight = "minimalist_light"

    var displayName: String {
        switch self {
        case .system:           return "System"
        case .deepSpaceDark:    return "Deep Space Dark"
        case .minimalistLight:  return "Minimalist Light"
        }
    }

    var systemImage: String {
        switch self {
        case .system:           return "circle.lefthalf.filled"
        case .deepSpaceDark:    return "moon.stars.fill"
        case .minimalistLight:  return "sun.max.fill"
        }
    }
}

// MARK: - Color Palette
struct ThemePalette {
    // Backgrounds
    var backgroundPrimary: Color
    var backgroundSecondary: Color
    var backgroundTertiary: Color

    // Foregrounds
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color

    // Accent
    var accent: Color
    var accentSecondary: Color

    // Semantic
    var destructive: Color
    var success: Color
    var warning: Color

    // Surface (cards, panels)
    var surface: Color
    var surfaceElevated: Color
    var border: Color
}

// MARK: - Deep Space Dark Palette
extension ThemePalette {
    static let deepSpaceDark = ThemePalette(
        backgroundPrimary:   Color(hex: "#0A0A0F"),
        backgroundSecondary: Color(hex: "#12121A"),
        backgroundTertiary:  Color(hex: "#1A1A2E"),
        textPrimary:         Color(hex: "#E8E8F0"),
        textSecondary:       Color(hex: "#A0A0B8"),
        textTertiary:        Color(hex: "#5A5A78"),
        accent:              Color(hex: "#7C5CBF"),  // deep purple
        accentSecondary:     Color(hex: "#4ECDC4"),  // teal
        destructive:         Color(hex: "#FF4757"),
        success:             Color(hex: "#2ED573"),
        warning:             Color(hex: "#FFA502"),
        surface:             Color(hex: "#16162A"),
        surfaceElevated:     Color(hex: "#1E1E3A"),
        border:              Color(hex: "#2A2A48")
    )
}

// MARK: - Minimalist Light Palette
extension ThemePalette {
    static let minimalistLight = ThemePalette(
        backgroundPrimary:   Color(hex: "#FAFAFA"),
        backgroundSecondary: Color(hex: "#F0F0F5"),
        backgroundTertiary:  Color(hex: "#E8E8EF"),
        textPrimary:         Color(hex: "#1A1A2E"),
        textSecondary:       Color(hex: "#4A4A6A"),
        textTertiary:        Color(hex: "#8A8AAA"),
        accent:              Color(hex: "#6B46C1"),  // indigo-purple
        accentSecondary:     Color(hex: "#0EA5E9"),  // sky blue
        destructive:         Color(hex: "#DC2626"),
        success:             Color(hex: "#16A34A"),
        warning:             Color(hex: "#D97706"),
        surface:             Color(hex: "#FFFFFF"),
        surfaceElevated:     Color(hex: "#F8F8FC"),
        border:              Color(hex: "#E0E0EA")
    )
}

// MARK: - ThemeManager
final class ThemeManager: ObservableObject {

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "lumina.theme")
            updatePalette()
        }
    }

    @Published private(set) var palette: ThemePalette

    init() {
        let saved = UserDefaults.standard.string(forKey: "lumina.theme")
        let theme = saved.flatMap { AppTheme(rawValue: $0) } ?? .system
        self.currentTheme = theme
        self.palette = ThemeManager.makePalette(for: theme)
    }

    var colorScheme: ColorScheme? {
        switch currentTheme {
        case .system:           return nil
        case .deepSpaceDark:    return .dark
        case .minimalistLight:  return .light
        }
    }

    private func updatePalette() {
        palette = ThemeManager.makePalette(for: currentTheme)
    }

    private static func makePalette(for theme: AppTheme) -> ThemePalette {
        switch theme {
        case .deepSpaceDark:    return .deepSpaceDark
        case .minimalistLight:  return .minimalistLight
        case .system:
#if canImport(AppKit)
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
            return isDark ? .deepSpaceDark : .minimalistLight
#else
            return .minimalistLight
#endif
        }
    }

    // MARK: - Convenience accent gradient
    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [palette.accent, palette.accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Environment Key for Theme
private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.minimalistLight
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}
