import AppKit

/// The app icon the person picks in Settings. Enamel is the bundle icon. Night replaces it only in the running app:
/// the Dock and app switcher while a window is open, and About Limits Left. macOS has no alternate icon API for Mac
/// apps, and a custom Finder icon on the bundle breaks its code signature, so Finder and Launchpad keep Enamel.
enum AppIconChoice: String, CaseIterable {
    case enamel
    case night

    static let defaultsKey = "AppIconChoice"

    init(defaults: UserDefaults) {
        self = defaults.string(forKey: Self.defaultsKey).flatMap(Self.init(rawValue:)) ?? .enamel
    }

    var title: String {
        switch self {
        case .enamel: "Enamel"
        case .night: "Night"
        }
    }

    /// The .icns file in Contents/Resources that holds this icon.
    var resourceName: String {
        switch self {
        case .enamel: "AppIcon"
        case .night: "AppIconNight"
        }
    }

    func image(in bundle: Bundle) -> NSImage? { bundle.image(forResource: resourceName) }

    /// Shows this icon in the running app. Enamel clears the override so AppKit uses the bundle icon.
    @MainActor
    func apply(from bundle: Bundle = .main) {
        NSApp.applicationIconImage = self == .enamel ? nil : image(in: bundle)
    }
}
