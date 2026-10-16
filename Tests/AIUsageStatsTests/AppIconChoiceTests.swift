import AppKit
import Foundation
import Testing
@testable import AIUsageStats

@Test
func appIconChoiceDefaultsToEnamelAndReadsTheStoredChoice() throws {
    let suite = "AppIconChoiceTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(AppIconChoice(defaults: defaults) == .enamel)
    defaults.set("night", forKey: AppIconChoice.defaultsKey)
    #expect(AppIconChoice(defaults: defaults) == .night)
    defaults.set("glass", forKey: AppIconChoice.defaultsKey)
    #expect(AppIconChoice(defaults: defaults) == .enamel)
}

@Test
func eachAppIconChoiceLoadsItsOwnPackagedIcon() throws {
    // The packaging script copies these files from Resources/ into Contents/Resources.
    let resources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Resources").standardized
    let bundle = try #require(Bundle(url: resources))
    let enamel = try #require(AppIconChoice.enamel.image(in: bundle))
    let night = try #require(AppIconChoice.night.image(in: bundle))
    #expect(enamel.tiffRepresentation != night.tiffRepresentation)
    #expect(enamel.representations.map(\.pixelsWide).max() == 1024)
}
