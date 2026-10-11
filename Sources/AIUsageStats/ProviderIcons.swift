import AppKit
import UsageCore

@MainActor
enum ProviderIcons {
    static let images: [Provider: NSImage] = {
        // Packaged apps locate the resource bundle in Bundle.main before any SwiftPM fallback.
        let resources = Bundle.main.url(forResource: "AIUsageStats_AIUsageStats", withExtension: "bundle")
            .flatMap { Bundle(url: $0) } ?? Bundle.module
        return Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { provider in
            guard let url = resources.url(forResource: provider.rawValue, withExtension: "png", subdirectory: "ProviderIcons"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            return (provider, image)
        })
    }()
}
