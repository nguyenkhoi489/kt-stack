import Foundation
import CryptoKit

/// Verifies a downloaded archive against its expected SHA-256 BEFORE extraction/execution — the
/// gate that keeps an unverified (tampered / wrong-arch / corrupt) runtime from ever being run.
public enum ChecksumVerifier {
    public struct Mismatch: LocalizedError {
        public let expected: String
        public let actual: String
        public var errorDescription: String? {
            "Checksum mismatch — refusing to use the download. Expected \(expected.prefix(12))…, got \(actual.prefix(12))…"
        }
    }

    /// SHA-256 of a file, streamed in chunks so a multi-hundred-MB archive isn't held in memory.
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Throw `Mismatch` unless the file's digest equals `expected` (case-insensitive hex).
    public static func verify(_ file: URL, expected: String) throws {
        let actual = try sha256(of: file)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw Mismatch(expected: expected, actual: actual)
        }
    }
}
