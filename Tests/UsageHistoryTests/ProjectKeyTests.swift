import Testing
import UsageHistory

private let salt: [UInt8] = Array(0..<16)

@Test func projectKeySeparatesSameNamedFoldersAndHidesTheName() {
    let client = ProjectKey.make(workingDirectory: "/Users/a/clients/acme/web", salt: salt)
    let personal = ProjectKey.make(workingDirectory: "/Users/a/personal/web", salt: salt)
    #expect(client != personal)
    #expect(client == ProjectKey.make(workingDirectory: "/Users/a/clients/acme/web/", salt: salt))
    #expect(client != ProjectKey.make(workingDirectory: "/Users/a/clients/acme/web", salt: Array(salt.reversed())))
    #expect(client.count == 16)
}
