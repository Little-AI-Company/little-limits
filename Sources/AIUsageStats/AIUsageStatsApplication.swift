import AppKit

@main
enum AIUsageStatsApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let dark = CommandLine.arguments.contains("--dark-appearance")
        if CommandLine.arguments.contains("--increase-contrast") {
            application.appearance = NSAppearance(named: dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
        } else if dark {
            application.appearance = NSAppearance(named: .darkAqua)
        }
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
