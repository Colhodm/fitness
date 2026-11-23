import SwiftUI

enum Palette {
    static let orange = Color(hex: 0xFF9F0A)
    static let orangeLight = Color(hex: 0xFFB340)
    static let cyan = Color(hex: 0x64D2FF)
    static let yellow = Color(hex: 0xFFD60A)
    static let card = Color(hex: 0x1C1C1E)
    static let field = Color(hex: 0x2C2C2E)
    static let fieldHigh = Color(hex: 0x3A3A3C)
    static let separator = Color(hex: 0x38383A)
    static let secondary = Color(hex: 0x98989F)
    static let tertiary = Color(hex: 0x636366)
    static let tabBar = Color(hex: 0x161618)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
