import CryptoKit
import Foundation

public enum ChecksumVerifier {
    public struct Mismatch: LocalizedError {
        public let expected: String
        public let actual: String
        public var errorDescription: String? {
            "Checksum mismatch — refusing to use the download. Expected \(expected.prefix(12))…, got \(actual.prefix(12))…"
        }
    }

    public static func isResolved(_ checksum: String?) -> Bool {
        guard let checksum else { return false }
        return checksum.count == 64 && checksum.allSatisfy(\.isHexDigit)
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(_ file: URL, expected: String) throws {
        let actual = try sha256(of: file)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw Mismatch(expected: expected, actual: actual)
        }
    }
}
