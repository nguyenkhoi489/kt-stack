import Foundation

public struct IDEDebugConfigWriter: Sendable {
    public init() {}

    public static func launchJSON(docroot: String, port: Int = XdebugController.clientPort) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: launchDocument(docroot: docroot, port: port),
            options: [.prettyPrinted, .sortedKeys]
        ),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\n  \"configurations\" : [\n\n  ],\n  \"version\" : \"0.2.0\"\n}\n"
        }
        return json + "\n"
    }

    @discardableResult
    public func writeVSCode(projectRoot: URL, docroot: URL) throws -> URL {
        let vscode = projectRoot.appendingPathComponent(".vscode", isDirectory: true)
        try FileManager.default.createDirectory(at: vscode, withIntermediateDirectories: true)
        let file = vscode.appendingPathComponent("launch.json")
        let document = try Self.mergedLaunchDocument(file: file, projectRoot: projectRoot, docroot: docroot)
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n").data(using: .utf8)!.write(to: file, options: .atomic)
        return file
    }

    private static func mergedLaunchDocument(file: URL, projectRoot: URL, docroot: URL) throws -> [String: Any] {
        var document = try existingLaunchDocument(file: file)
        var configurations = document["configurations"] as? [[String: Any]] ?? []
        configurations.removeAll { $0["name"] as? String == configurationName }
        configurations.append(launchConfiguration(
            docroot: docroot.path,
            localRoot: workspacePath(projectRoot: projectRoot, docroot: docroot)
        ))
        document["version"] = document["version"] as? String ?? "0.2.0"
        document["configurations"] = configurations
        return document
    }

    private static func existingLaunchDocument(file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return ["version": "0.2.0", "configurations": []]
        }
        let data = try Data(contentsOf: file)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["version": "0.2.0", "configurations": []]
        }
        return object
    }

    private static func launchDocument(docroot: String, port: Int) -> [String: Any] {
        ["version": "0.2.0", "configurations": [launchConfiguration(docroot: docroot, port: port)]]
    }

    private static func launchConfiguration(
        docroot: String,
        localRoot: String = "${workspaceFolder}",
        port: Int = XdebugController.clientPort
    ) -> [String: Any] {
        [
            "name": configurationName,
            "type": "php",
            "request": "launch",
            "port": port,
            "pathMappings": [docroot: localRoot],
        ]
    }

    private static func workspacePath(projectRoot: URL, docroot: URL) -> String {
        let rootPath = projectRoot.standardizedFileURL.path
        let docrootPath = docroot.standardizedFileURL.path
        guard docrootPath != rootPath else { return "${workspaceFolder}" }
        guard docrootPath.hasPrefix(rootPath + "/") else { return docrootPath }
        return "${workspaceFolder}/" + String(docrootPath.dropFirst(rootPath.count + 1))
    }

    private static let configurationName = "Listen for Xdebug (KTStack)"
}
