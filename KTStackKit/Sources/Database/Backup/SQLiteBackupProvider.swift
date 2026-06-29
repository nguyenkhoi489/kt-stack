import Foundation
import GRDB

/// File-based backup: `VACUUM INTO` produces a consistent snapshot from a live database without a
/// managed binary. Restore replaces the file through an atomic `replaceItemAt` after a verified
/// safety copy, removing stale WAL/SHM sidecars so SQLite can't replay a journal against the new file.
public struct SQLiteBackupProvider: BackupProvider {
    public init() {}

    public var fileExtension: String {
        "sqlite"
    }

    public var isAvailable: Bool {
        true
    }

    private static let sidecarSuffixes = ["-wal", "-shm", "-journal"]
    private static let freeSpaceMargin: Int64 = 8 * 1024 * 1024

    public func backup(
        profile: ConnectionProfile,
        password _: String?,
        database _: String,
        to artifactURL: URL
    ) async throws {
        guard let path = profile.filePath, !path.isEmpty else {
            throw DatabaseError.connection("No SQLite file selected for this connection.")
        }
        let destination = artifactURL.path
        guard !destination.contains(where: { $0.unicodeScalars.contains { $0.value < 0x20 } }) else {
            throw DatabaseError.connection("Illegal characters in the backup file path.")
        }
        let escaped = destination.replacingOccurrences(of: "'", with: "''")
        var config = Configuration()
        config.readonly = profile.readOnly
        do {
            let queue = try DatabaseQueue(path: path, configuration: config)
            try await queue.writeWithoutTransaction { db in
                try db.execute(sql: "VACUUM INTO '\(escaped)'")
            }
        } catch {
            try? FileManager.default.removeItem(at: artifactURL)
            throw SQLiteDriver.mapError(error)
        }
    }

    public func restore(
        profile: ConnectionProfile,
        password _: String?,
        from artifactURL: URL,
        into target: RestoreTarget
    ) async throws {
        switch target {
        case let .newDatabase(newPath):
            let dest = URL(fileURLWithPath: newPath)
            guard !FileManager.default.fileExists(atPath: dest.path) else {
                throw DatabaseError.connection(
                    "A file already exists at \"\(newPath)\". Choose another path."
                )
            }
            try FileManager.default.copyItem(at: artifactURL, to: dest)
        case .overwrite:
            guard let path = profile.filePath, !path.isEmpty else {
                throw DatabaseError.connection("No SQLite file selected for this connection.")
            }
            try await SQLiteRestoreCoordinator.shared.withExclusiveAccess(to: path) {
                try Self.overwriteFile(at: path, with: artifactURL)
            }
        }
    }

    private static func overwriteFile(at targetPath: String, with snapshot: URL) throws {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: targetPath)
        let directory = target.deletingLastPathComponent()

        let snapshotSize = fileSize(snapshot, fm)
        let currentSize = fileSize(target, fm)
        if let available = volumeAvailableBytes(directory),
           available < snapshotSize + currentSize + freeSpaceMargin
        {
            throw DatabaseError.connection("Not enough free disk space to restore safely.")
        }

        let safetyDir = directory.appendingPathComponent(
            ".ktstack-restore-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: safetyDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: safetyDir) }

        let safetyMain = safetyDir.appendingPathComponent(target.lastPathComponent)
        if fm.fileExists(atPath: target.path) {
            try fm.copyItem(at: target, to: safetyMain)
        }
        for suffix in sidecarSuffixes {
            let sidecar = URL(fileURLWithPath: targetPath + suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try fm.copyItem(at: sidecar, to: safetyDir.appendingPathComponent(sidecar.lastPathComponent))
            }
        }

        let staged = directory.appendingPathComponent(".ktstack-staged-\(UUID().uuidString).sqlite")
        try fm.copyItem(at: snapshot, to: staged)
        guard fileSize(staged, fm) == snapshotSize else {
            try? fm.removeItem(at: staged)
            throw DatabaseError.connection("The staged restore file is incomplete.")
        }

        do {
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: target)
            }
            for suffix in sidecarSuffixes {
                try? fm.removeItem(at: URL(fileURLWithPath: targetPath + suffix))
            }
        } catch {
            try? fm.removeItem(at: staged)
            try? fm.removeItem(at: target)
            if fm.fileExists(atPath: safetyMain.path) {
                try? fm.copyItem(at: safetyMain, to: target)
            }
            for suffix in sidecarSuffixes {
                let saved = safetyDir.appendingPathComponent(target.lastPathComponent + suffix)
                if fm.fileExists(atPath: saved.path) {
                    try? fm.copyItem(at: saved, to: URL(fileURLWithPath: targetPath + suffix))
                }
            }
            throw DatabaseError.connection(
                "Restore failed and the original database was rolled back: \(SQLiteDriver.mapError(error).message)"
            )
        }
    }

    private static func fileSize(_ url: URL, _ fm: FileManager) -> Int64 {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    private static func volumeAvailableBytes(_ directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
