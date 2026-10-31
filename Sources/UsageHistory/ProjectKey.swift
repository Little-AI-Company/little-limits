public enum ProjectKey {
    public static func make(workingDirectory: String, salt: [UInt8]) -> String {
        var path = Substring(workingDirectory)
        while path.count > 1, path.hasSuffix("/") { path = path.dropLast() }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in salt + Array(path.utf8) {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
