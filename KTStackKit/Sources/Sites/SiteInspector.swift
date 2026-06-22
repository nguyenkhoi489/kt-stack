import Foundation


public struct SiteInspector {
    public struct Result: Equatable, Sendable {
        public let docroot: URL
        public let defaultDomain: String
        public let type: SiteType
    }

    static let docrootCandidates = ["public", "web", "public_html"]

    public init() {}

    public func inspect(folder: URL, tld: String = "test", fileManager: FileManager = .default) -> Result {
        let docroot = resolveDocroot(folder: folder, fileManager: fileManager)
        let type = classify(folder: folder, docroot: docroot, fileManager: fileManager)
        let domain = "\(Self.slug(folder.lastPathComponent)).\(tld)"
        return Result(docroot: docroot, defaultDomain: domain, type: type)
    }

    private func resolveDocroot(folder: URL, fileManager: FileManager) -> URL {
        for candidate in Self.docrootCandidates {
            let dir = folder.appendingPathComponent(candidate, isDirectory: true)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return folder
    }

    private func classify(folder: URL, docroot: URL, fileManager: FileManager) -> SiteType {
        func has(_ name: String, in dir: URL) -> Bool {
            fileManager.fileExists(atPath: dir.appendingPathComponent(name).path)
        }
        if has("artisan", in: folder)
            || containsPHPFile(in: docroot, fileManager: fileManager)
            || containsPHPFile(in: folder, fileManager: fileManager) {
            return .php
        }
        if has("package.json", in: folder) {
            return .node
        }
        return .staticSite
    }

    public func suggestedNodeCommand(at folder: URL, fileManager: FileManager = .default) -> String? {
        let packageJSON = folder.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJSON),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = root["scripts"] as? [String: Any] else { return nil }
        if scripts["start"] != nil { return "npm run start" }
        if scripts["dev"] != nil { return "npm run dev" }
        return nil
    }

    private func containsPHPFile(in dir: URL, fileManager: FileManager) -> Bool {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }
        return entries.contains { $0.pathExtension.lowercased() == "php" }
    }

    public static func slug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var out = ""
        var lastHyphen = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastHyphen = false
            } else if !lastHyphen {
                out.append("-"); lastHyphen = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "site" : trimmed
    }
}
