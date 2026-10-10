import Foundation
import Testing
@testable import UsageCore

@Test func percentageNormalizationAndResetCountdown() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(UsageWindow(id: "a", title: "a", utilizationPercent: 140, resetsAt: nil).utilizationPercent == 100)
    #expect(UsageWindow(id: "a", title: "a", utilizationPercent: -4, resetsAt: nil).utilizationPercent == 0)
    #expect(UsageWindow(id: "a", title: "a", utilizationPercent: .nan, resetsAt: nil).utilizationPercent == nil)
    let decoded = try JSONDecoder().decode(UsageWindow.self, from: Data(#"{"id":"a","title":"A","utilizationPercent":999}"#.utf8))
    #expect(decoded.utilizationPercent == 100)
    #expect(UsageFormatting.countdown(to: now.addingTimeInterval(3_601), now: now) == "1h 1m")
    #expect(UsageFormatting.countdown(to: now.addingTimeInterval(-1), now: now) == "Reset due")
    #expect(UsageFormatting.countdown(to: nil, now: now) == "Reset unavailable")
    #expect(CreditBalance.dollars(fromCents: 1_250) == Decimal(string: "12.50"))
}

@Test func claudeCaptureFiltersInputAndPreservesObservationTime() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let identifier = UUID()
    let input = Data(#"{"model":{"id":"private-example"},"workspace":{"current_dir":"private-path"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":2000}}}"#.utf8)
    let first = try ClaudeQuotaCapture.decodeStatusLine(input, profileID: identifier, observedAt: Date(timeIntervalSince1970: 100))
    #expect(first.windows.count == 1)
    #expect(first.windows[0].utilizationPercent == 42)
    try first.save(directory: directory)
    try ClaudeQuotaCapture.decodeStatusLine(input, profileID: identifier, observedAt: Date(timeIntervalSince1970: 200)).save(directory: directory)
    let saved = try Data(contentsOf: UsagePaths.captureURL(profileID: identifier, directory: directory))
    #expect(!String(decoding: saved, as: UTF8.self).contains("private-example"))
    #expect(!String(decoding: saved, as: UTF8.self).contains("private-path"))
    let decoded = try JSONDecoder().decode(ClaudeQuotaCapture.self, from: saved)
    #expect(decoded.observedAt == first.observedAt)
    #expect(try ClaudeQuotaCapture.decodeStatusLine(Data("{}".utf8), profileID: identifier).windows.isEmpty)
}

@Test func captureInstallationPreservesUserConfigurationAndLaterEdits() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = try fakeExecutable(in: directory, content: "#!/bin/sh\nexit 0\n")
    let source = directory.appendingPathComponent("Claude")
    let settings = source.appendingPathComponent("settings.json")
    try UsagePaths.writePrivate(Data(#"{"statusLine":{"type":"command","command":"printf 'existing output'","padding":2},"otherSetting":true}"#.utf8), to: settings)
    let installation = try ClaudeCaptureInstallation.install(profileID: UUID(), configurationURL: source,
                                                             helperURL: helper, storageDirectory: directory)
    let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    let line = installed["statusLine"] as! [String: Any]
    #expect(line["padding"] as? Int == 2)
    #expect((line["command"] as? String)?.contains("--original-command") == true)
    #expect(installed["otherSetting"] as? Bool == true)
    try ClaudeCaptureInstallation.remove(installation)
    let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    #expect((restored["statusLine"] as? [String: Any])?["command"] as? String == "printf 'existing output'")
    let reinstalled = try ClaudeCaptureInstallation.install(profileID: UUID(), configurationURL: source,
                                                           helperURL: helper, storageDirectory: directory)
    try UsagePaths.writePrivate(Data(#"{"statusLine":{"type":"command","command":"printf changed"}}"#.utf8), to: settings)
    try ClaudeCaptureInstallation.remove(reinstalled)
    #expect(String(decoding: try Data(contentsOf: settings), as: UTF8.self).contains("printf changed"))
    let attributes = try FileManager.default.attributesOfItem(atPath: settings.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func providerResponseKeepsMissingDataAndDifferentCreditUnits() throws {
    let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(#"{"accountId":"account-a","rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000},"secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":"12.50"}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"grant-a","status":"available","expiresAt":3000}]}}"#.utf8))
    let snapshot = response.snapshot(profileID: UUID(), observedAt: Date(timeIntervalSince1970: 1000))
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows.first?.utilizationPercent == 25)
    #expect(snapshot.credits.first { $0.id == "provider_credits" }?.amount == Decimal(string: "12.50"))
    #expect(snapshot.credits.first { $0.id == "provider_credits" }?.unit == .credits)
    #expect(snapshot.credits.first { $0.id == "quota_reset_credits" }?.unit == .resets)
    let missing = try JSONDecoder().decode(CodexUsageResponse.self, from: Data("{}".utf8)).snapshot(profileID: UUID())
    #expect(missing.state == .unavailable)
    #expect(missing.windows.isEmpty)
    #expect(missing.credits.isEmpty)
    let expiry = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(#"{"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"never","expiresAt":null},{"id":"unknown"}]}}"#.utf8)).snapshot(profileID: UUID())
    #expect(expiry.credits.first { $0.id == "quota_reset_never" }?.doesNotExpire == true)
    #expect(expiry.credits.first { $0.id == "quota_reset_unknown" }?.doesNotExpire == false)
}

@Test func captureInstallationPreservesSettingsSymlink() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = try fakeExecutable(in: directory, content: "#!/bin/sh\nexit 0\n")
    let source = directory.appendingPathComponent("Claude")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("dotfiles-settings.json")
    try UsagePaths.writePrivate(Data(#"{"statusLine":{"type":"command","command":"printf original"}}"#.utf8), to: target)
    let link = source.appendingPathComponent("settings.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let installation = try ClaudeCaptureInstallation.install(profileID: UUID(), configurationURL: source,
                                                             helperURL: helper, storageDirectory: directory)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    try ClaudeCaptureInstallation.remove(installation)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(String(decoding: try Data(contentsOf: target), as: UTF8.self).contains("printf original"))
}

@Test func accountConfigurationDeduplicatesDirectoriesAndKeepsManualBalances() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = try fakeExecutable(in: directory, content: "#!/bin/sh\nexit 0\n")
    let service = UsageService(directory: directory.appendingPathComponent("Store"), captureHelperURL: helper)
    let source = directory.appendingPathComponent("Claude")
    let first = try await service.importClaudeCLI(label: "Personal", configurationURL: source)
    let duplicate = try await service.importClaudeCLI(label: "Other name", configurationURL: source)
    #expect(first.id == duplicate.id)
    let second = try await service.importClaudeCLI(label: "Work", configurationURL: directory.appendingPathComponent("Work"))
    #expect(first.id != second.id)
    let confirmation = Date(timeIntervalSince1970: 1_000)
    try await service.setManualCredit(accountID: first.id, credit: CreditBalance(id: "api_balance", title: "API", amount: 12,
                                                                               source: .manual, asOf: confirmation))
    let firstSnapshot = await service.snapshot(for: first.id)
    let secondSnapshot = await service.snapshot(for: second.id)
    #expect(firstSnapshot?.credits.first { $0.id == "api_balance" }?.amount == 12)
    #expect(firstSnapshot?.credits.first { $0.id == "api_balance" }?.asOf == confirmation)
    #expect(secondSnapshot?.credits.first { $0.id == "api_balance" }?.amount == nil)
    let reloaded = UsageService(directory: directory.appendingPathComponent("Store"), captureHelperURL: helper)
    #expect(try await reloaded.load().count == 2)
    #expect(await reloaded.snapshot(for: first.id)?.credits.first { $0.id == "api_balance" }?.amount == 12)
    try await service.removeAccount(id: first.id)
    #expect(try await service.load().count == 1)
}

@Test func consoleBalancesStayBoundToOrganizationAndOverrideManualPurchasedAmount() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let helper = try fakeExecutable(in: directory, content: "#!/bin/sh\nexit 0\n")
    let service = UsageService(directory: directory.appendingPathComponent("Store"), captureHelperURL: helper)
    let profile = try await service.importClaudeCLI(label: "Console", configurationURL: directory.appendingPathComponent("Claude"))
    try await service.setManualCredit(accountID: profile.id, credit: CreditBalance(id: "api_balance", title: "Purchased", amount: 9))
    let organizationID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    try await service.setClaudeConsoleConnection(accountID: profile.id, organizationID: organizationID, expectedIdentity: nil)
    let response = Data(#"{"amount":2500,"currency":"USD","tranches":[{"id":"purchase-a","remaining_amount_minor_units":2500,"currency":"USD","expires_at":"2027-10-09T00:00:00Z"}],"promo_tranches":[]}"#.utf8)
    try await service.updateClaudeConsoleCredits(accountID: profile.id, organizationID: organizationID, responseData: response, expectedIdentity: nil)
    let snapshot = await service.refreshAccount(id: profile.id)
    #expect(snapshot.credits.first { $0.id == "api_balance_USD" }?.amount == 25)
    #expect(snapshot.credits.first { $0.id == "api_balance_USD" }?.source == .provider)
    #expect(!snapshot.credits.contains { $0.id == "api_balance" })
    #expect(snapshot.windows.isEmpty)
    #expect(snapshot.state == .unavailable)
    try await service.setClaudeConsoleConnection(accountID: profile.id, organizationID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", expectedIdentity: nil)
    await #expect(throws: UsageError.self) {
        try await service.updateClaudeConsoleCredits(accountID: profile.id, organizationID: organizationID, responseData: response, expectedIdentity: nil)
    }
    #expect(await service.snapshot(for: profile.id)?.credits.first { $0.id == "api_balance" }?.amount == 9)
}

@Test func codexExecutableUsesNativeBundleOrNPMBinaryWithFinderEnvironment() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let applications = directory.appendingPathComponent("Applications")
    let native = applications.appendingPathComponent("ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
    try FileManager.default.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: native, withDestinationURL: URL(fileURLWithPath: "/bin/echo"))
    let package = directory.appendingPathComponent(".bun/install/global/node_modules/@openai/codex")
    let wrapper = package.appendingPathComponent("bin/codex.js")
    try UsagePaths.writePrivate(Data("#!/usr/bin/env node\nthrow new Error('Node wrapper must not run');\n".utf8), to: wrapper, permissions: 0o700)
    let bin = directory.appendingPathComponent(".bun/bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("codex"), withDestinationURL: wrapper)
    let environment = ["HOME": directory.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    #expect(try CodexExecutable.resolve(environment: environment, home: directory, applicationDirectories: [applications]) == native)
    #if arch(arm64)
    let vendor = package.deletingLastPathComponent().appendingPathComponent("codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex")
    #else
    let vendor = package.deletingLastPathComponent().appendingPathComponent("codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex")
    #endif
    try FileManager.default.createDirectory(at: vendor.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: vendor, withDestinationURL: URL(fileURLWithPath: "/bin/echo"))
    let selected = try CodexExecutable.resolve(environment: environment, home: directory, applicationDirectories: [])
    #expect(selected == vendor.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent("codex"))
    let process = Process()
    process.executableURL = selected
    process.arguments = ["--version"]
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageStatsTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func fakeExecutable(in directory: URL, content: String) throws -> URL {
    let url = directory.appendingPathComponent("test-provider")
    try Data(content.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
}
