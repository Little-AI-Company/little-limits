import AppKit

enum AppIconChoice: String, CaseIterable {
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

    var resourceName: String {
        switch self {
        case .paper: "AppIcon"
        case .night: "AppIconNight"
        }
    }

    func image(in bundle: Bundle) -> NSImage? { bundle.image(forResource: resourceName) }

    @MainActor
    func apply(from bundle: Bundle = .main) {
        NSApp.applicationIconImage = self == .paper ? nil : image(in: bundle)
    }
}
