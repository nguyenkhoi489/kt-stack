import Foundation
import KTStackKit

@MainActor
final class PHPExtensionsModel: ObservableObject {
    struct Row: Identifiable {
        let ext: PHPExtension
        let status: PHPExtensionStatus
        var id: String {
            ext.id
        }
    }

    let version: String
    @Published private(set) var rows: [Row] = []
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var errors: [String: String] = [:]

    private let paths: AppSupportPaths
    private let installer: PHPExtensionInstaller
    private let catalog: PHPExtensionCatalog

    init(version: String, paths: AppSupportPaths = AppSupportPaths()) {
        self.version = version
        self.paths = paths
        installer = PHPExtensionInstaller(paths: paths)
        catalog = PHPExtensionCatalog(paths: paths)
    }

    func refresh() async {
        let catalog = catalog
        let version = version

        let (installed, onDisk): (Set<String>, [String: Bool]) = await Task.detached(priority: .utility) {
            let installed = catalog.installedExtensions(version)
            var onDisk: [String: Bool] = [:]
            for ext in PHPExtensionCatalog.descriptors where !ext.isBuiltIn {
                onDisk[ext.id] = catalog.sharedObjectExists(ext.id, phpVersion: version)
            }
            return (installed, onDisk)
        }.value
        rows = PHPExtensionCatalog.descriptors
            .filter { $0.id != "xdebug" }
            .map { Row(ext: $0, status: catalog.status(
                $0,
                phpVersion: version,
                installed: installed,
                soOnDisk: onDisk[$0.id] ?? false
            )) }
            .sorted { a, b in
                if a.ext.isBuiltIn != b.ext.isBuiltIn { return !a.ext.isBuiltIn } // optional first
                return a.ext.displayName.localizedCaseInsensitiveCompare(b.ext.displayName) == .orderedAscending
            }
    }

    func install(_ extID: String, reloadPool: (String) async throws -> Void) async {
        guard !busy.contains(extID) else { return }
        begin(extID)
        do {
            let result = try await installer.install(extID, phpVersion: version) { [weak self] prog in
                Task { @MainActor in self?.progress[extID] = prog.fraction }
            }
            try await reloadPool(version)
            PHPModules.invalidate(version: version)
            await refresh()

            if case let .installedButFailedToLoad(warning) = result {
                errors[extID] = warning ?? "Installed but the extension failed to load."
            }
        } catch {
            errors[extID] = error.localizedDescription
        }
        end(extID)
    }

    func uninstall(_ extID: String, reloadPool: (String) async throws -> Void) async {
        guard !busy.contains(extID) else { return }
        begin(extID)
        do {
            try installer.uninstall(extID, phpVersion: version)
            try await reloadPool(version) // RESTART, not reload — unloads the live .so
            PHPModules.invalidate(version: version)
            await refresh()
        } catch {
            errors[extID] = error.localizedDescription
        }
        end(extID)
    }

    private func begin(_ extID: String) {
        busy.insert(extID); errors[extID] = nil; progress[extID] = nil
    }

    private func end(_ extID: String) {
        busy.remove(extID); progress[extID] = nil
    }
}
