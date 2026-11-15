import AppKit

enum BrandPalette {
    static let label = color(light: 0x0f0f02, dark: (0xfbfaf7, 0.9), lightIncreased: 0x000000, darkIncreased: (0xffffff, 1))
    static let secondaryLabel = color(light: 0x5d5c58, dark: (0xfbfaf7, 0.56), lightIncreased: 0x3a3a3c, darkIncreased: (0xd1d1d6, 1))
    static let tertiaryLabel = color(light: 0xa2a09a, dark: (0xfbfaf7, 0.26), lightIncreased: 0x6e6e73, darkIncreased: (0xaeaeb2, 1))
    static let contentBackground = color(light: 0xfbfaf7, dark: (0x1f1e1c, 1), lightIncreased: 0xffffff, darkIncreased: (0x000000, 1))
    static let windowBackground = color(light: 0xf6f4f0, dark: (0x1f1e1c, 1), lightIncreased: 0xffffff, darkIncreased: (0x000000, 1))
    static let sidebarBackground = color(light: 0xf1efe9, dark: (0x191917, 1), lightIncreased: 0xffffff, darkIncreased: (0x000000, 1))
    static let raisedBackground = color(light: 0xffffff, dark: (0x252422, 1), lightIncreased: 0xffffff, darkIncreased: (0x1c1c1e, 1))
    static let separator = color(light: (0x3c3214, 0.12), dark: (0xfbfaf7, 0.1), lightIncreased: (0x000000, 0.5), darkIncreased: (0xffffff, 0.55))
    static let selectedContentBackground = color(light: 0xe0ded7, dark: (0x3a3936, 1), lightIncreased: 0xd1d1d6, darkIncreased: (0x48484a, 1))
    static let fill = color(light: (0x000000, 0.06), dark: (0xffffff, 0.1), lightIncreased: (0x000000, 0.06), darkIncreased: (0xffffff, 0.1))
    static let accentFill = color(light: 0x0f0f02, dark: (0xecebe5, 1), lightIncreased: 0x000000, darkIncreased: (0xffffff, 1))
    static let labelOnAccent = color(light: 0xfbfaf7, dark: (0x0f0f02, 1), lightIncreased: 0xffffff, darkIncreased: (0x000000, 1))
    static let markBlue = color(light: 0x1b63c5, dark: (0x85b3f7, 1), lightIncreased: 0x0b4596, darkIncreased: (0xc3d9fd, 1))
    static let success = color(light: 0x196130, dark: (0x6bd586, 1), lightIncreased: 0x0e4a22, darkIncreased: (0x8fe6a6, 1))
    static let destructive = color(light: 0xc20019, dark: (0xff8083, 1), lightIncreased: 0xa80016, darkIncreased: (0xff8a8c, 1))
    static let honey = color(light: 0xf7c45c, dark: (0xffbf5a, 1), lightIncreased: 0xf7c45c, darkIncreased: (0xffbf5a, 1))

    private static func color(light: Int, dark: (Int, CGFloat), lightIncreased: Int, darkIncreased: (Int, CGFloat)) -> NSColor {
        color(light: (light, 1), dark: dark, lightIncreased: (lightIncreased, 1), darkIncreased: darkIncreased)
    }

    private static func color(light: (Int, CGFloat), dark: (Int, CGFloat), lightIncreased: (Int, CGFloat),
                              darkIncreased: (Int, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            let value = switch match {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: lightIncreased
            case .accessibilityHighContrastDarkAqua: darkIncreased
            default: light
            }
            return NSColor(srgbRed: CGFloat((value.0 >> 16) & 0xff) / 255, green: CGFloat((value.0 >> 8) & 0xff) / 255,
                           blue: CGFloat(value.0 & 0xff) / 255, alpha: value.1)
        }
    }
}
