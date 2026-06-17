import Foundation
@testable import KDWarmKit

/// Deterministic provider for library-level tests: write the database name as the file body so the
/// round-trip can assert content; restore is a no-op (library tests aren't engine tests).
struct StubBackupProvider: BackupProvider {
    let fileExtension: String
    let isAvailable: Bool = true

    init(fileExtension: String = "stub") { self.fileExtension = fileExtension }

    func backup(profile: ConnectionProfile, password: String?,
                database: String, to artifactURL: URL) async throws {
        if fileExtension.isEmpty {
            try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
            try Data(database.utf8).write(to: artifactURL.appendingPathComponent("payload"))
        } else {
            try Data(database.utf8).write(to: artifactURL)
        }
    }

    func restore(profile: ConnectionProfile, password: String?,
                 from artifactURL: URL, into target: RestoreTarget) async throws {}
}
