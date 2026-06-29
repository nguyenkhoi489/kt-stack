import Foundation

public protocol BackupProvider: Sendable {
    var fileExtension: String { get }
    var isAvailable: Bool { get }

    func backup(
        profile: ConnectionProfile,
        password: String?,
        database: String,
        to artifactURL: URL
    ) async throws

    func restore(
        profile: ConnectionProfile,
        password: String?,
        from artifactURL: URL,
        into target: RestoreTarget
    ) async throws
}

public extension BackupProvider {
    func artifactName(for database: String) -> String {
        fileExtension.isEmpty ? database : "\(database).\(fileExtension)"
    }
}
