import AppKit

/// The app icon the person picks in Settings. Paper is the bundle icon. Night replaces it only in the running app:
/// the Dock and app switcher while a window is open, and About Little Limits. macOS has no alternate icon API for Mac
/// apps, and a custom Finder icon on the bundle breaks its code signature, so Finder and Launchpad keep Paper.
enum AppIconChoice: String, CaseIterable {
    /// Stored as "enamel", the name of the bundle icon before the Little Limits artwork, so a saved choice still reads.
    case paper = "enamel"
    case night

    static let defaultsKey = "AppIconChoice"

    init(defaults: UserDefaults) {
        self = defaults.string(forKey: Self.defaultsKey).flatMap(Self.init(rawValue:)) ?? .paper
    }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .night: "Night"
        }
    }

    /// The .icns file in Contents/Resources that holds this icon.
    var resourceName: String {
        switch self {
        case .paper: "AppIcon"
        case .night: "AppIconNight"
        }
    }

    func image(in bundle: Bundle) -> NSImage? { bundle.image(forResource: resourceName) }

    /// Shows this icon in the running app. Paper clears the override so AppKit uses the bundle icon.
    @MainActor
    func apply(from bundle: Bundle = .main) {
        NSApp.applicationIconImage = self == .paper ? nil : image(in: bundle)
    }
}
