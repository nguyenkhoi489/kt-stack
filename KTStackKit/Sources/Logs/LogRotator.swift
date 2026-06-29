import Foundation

public struct LogRotator: Sendable {
    public let maxBytes: Int
    public let keep: Int

    public init(maxBytes: Int = 5 * 1024 * 1024, keep: Int = 3) {
        self.maxBytes = maxBytes
        self.keep = keep
    }

    public func rotateOversized(in paths: AppSupportPaths) {
        for dir in [paths.logs, paths.logsSites] {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            for file in files where file.pathExtension == "log" {
                rotateIfNeeded(file)
            }
        }
    }

    public func rotateIfNeeded(_ url: URL) {
        let fm = FileManager.default
        let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
        guard size > maxBytes else { return }

        try? fm.removeItem(at: url.appendingPathExtension("\(keep)"))
        for n in stride(from: keep - 1, through: 1, by: -1) {
            let from = url.appendingPathExtension("\(n)")
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.moveItem(at: from, to: url.appendingPathExtension("\(n + 1)"))
        }
        try? fm.copyItem(at: url, to: url.appendingPathExtension("1"))

        try? Data().write(to: url)
    }
}
