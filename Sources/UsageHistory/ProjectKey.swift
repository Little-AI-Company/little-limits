/// An opaque, stable key that groups records by working directory without storing folder names. The full path
/// keeps directories with the same last component apart. It is not meant to resist someone who holds the database
/// and its salt and guesses paths.
public enum ProjectKey {
    /// A 64-bit FNV-1a hash of the salt and the path, as 16 hexadecimal digits. Trailing slashes are ignored.
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
