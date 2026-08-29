import AppKit
import SwiftUI

enum FileNestTheme {
    static let accent = Color(red: 0.25, green: 0.49, blue: 0.89)
    static let teal = Color(red: 0.12, green: 0.58, blue: 0.57)
    static let green = Color(red: 0.20, green: 0.58, blue: 0.38)
    static let orange = Color(red: 0.88, green: 0.48, blue: 0.18)
    static let red = Color(red: 0.82, green: 0.29, blue: 0.28)
    static let violet = Color(red: 0.43, green: 0.36, blue: 0.76)

    static let workspaceBackground = adaptive(
        light: NSColor(srgbRed: 0.945, green: 0.957, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.115, green: 0.126, blue: 0.150, alpha: 1)
    )
    static let panelBackground = adaptive(
        light: NSColor(srgbRed: 0.969, green: 0.976, blue: 0.988, alpha: 1),
        dark: NSColor(srgbRed: 0.145, green: 0.163, blue: 0.195, alpha: 1)
    )
    static let recessedBackground = adaptive(
        light: NSColor(srgbRed: 0.925, green: 0.945, blue: 0.972, alpha: 1),
        dark: NSColor(srgbRed: 0.126, green: 0.143, blue: 0.174, alpha: 1)
    )
    static let sidebarBackground = adaptive(
        light: NSColor(srgbRed: 0.918, green: 0.937, blue: 0.961, alpha: 1),
        dark: NSColor(srgbRed: 0.095, green: 0.105, blue: 0.126, alpha: 1)
    )
    static let border = adaptive(
        light: NSColor(srgbRed: 0.820, green: 0.851, blue: 0.894, alpha: 1),
        dark: NSColor(srgbRed: 0.245, green: 0.274, blue: 0.326, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
