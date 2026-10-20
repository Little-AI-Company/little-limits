import AppKit
import Foundation
import Testing
@testable import AIUsageStats

@Test
func appIconChoiceDefaultsToPaperAndReadsTheStoredChoice() throws {
    let suite = "AppIconChoiceTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(AppIconChoice(defaults: defaults) == .paper)
    defaults.set("enamel", forKey: AppIconChoice.defaultsKey)
    #expect(AppIconChoice(defaults: defaults) == .paper)
    defaults.set("night", forKey: AppIconChoice.defaultsKey)
    #expect(AppIconChoice(defaults: defaults) == .night)
    defaults.set("glass", forKey: AppIconChoice.defaultsKey)
    #expect(AppIconChoice(defaults: defaults) == .paper)
}

@Test
func eachAppIconChoiceLoadsItsOwnPackagedIcon() throws {
    // The packaging script copies these files from Resources/ into Contents/Resources.
    let resources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Resources").standardized
    let bundle = try #require(Bundle(url: resources))
    let paper = try #require(AppIconChoice.paper.image(in: bundle))
    let night = try #require(AppIconChoice.night.image(in: bundle))
    #expect(paper.tiffRepresentation != night.tiffRepresentation)
    #expect(paper.representations.map(\.pixelsWide).max() == 1024)
}
