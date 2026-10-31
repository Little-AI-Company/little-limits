import AppKit
import UsageCore

@MainActor
enum ProviderIcons {
    static let images: [Provider: NSImage] = {
        Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { provider in
            guard let url = Bundle.appResources.url(forResource: provider.rawValue, withExtension: "png", subdirectory: "ProviderIcons"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            return (provider, image)
        })
    }()
}

extension Bundle {
    static let packagedResourceBundleName = "AIUsageStats_AIUsageStats"
    static let appResources: Bundle = Bundle.main.url(forResource: packagedResourceBundleName, withExtension: "bundle")
        .flatMap { Bundle(url: $0) } ?? Bundle.module
}
