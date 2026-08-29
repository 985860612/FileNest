import AppKit
import SwiftUI

enum FileNestTheme {
    static let accent = Color(red: 0.25, green: 0.49, blue: 0.89)
    static let teal = Color(red: 0.12, green: 0.58, blue: 0.57)
    static let green = Color(red: 0.20, green: 0.58, blue: 0.38)
    static let orange = Color(red: 0.88, green: 0.48, blue: 0.18)
    static let red = Color(red: 0.82, green: 0.29, blue: 0.28)
    static let violet = Color(red: 0.43, green: 0.36, blue: 0.76)

    static let workspaceBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.72)
}
