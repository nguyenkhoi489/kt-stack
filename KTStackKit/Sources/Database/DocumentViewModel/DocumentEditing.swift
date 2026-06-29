import Foundation

public extension DocumentViewModel {
    static func validateJSON(_ json: String) -> String? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "The document is empty." }
        let data = Data(trimmed.utf8)
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard object is [String: Any] else { return "A document must be a JSON object." }
            return nil
        } catch {
            return "Invalid JSON: \(error.localizedDescription)"
        }
    }

    func insert(json: String) async -> Bool {
        guard let driver, let database = selectedDatabase, let collection = selectedCollection else {
            return false
        }
        if let reason = Self.validateJSON(json) { editError = reason; return false }
        return await mutate { try await driver.insert(database: database, collection: collection, json: json) }
    }

    func update(record: DocumentRecord, json: String) async -> Bool {
        guard let driver, let database = selectedDatabase, let collection = selectedCollection else {
            return false
        }
        if let reason = Self.validateJSON(json) { editError = reason; return false }
        return await mutate {
            try await driver.update(database: database, collection: collection, record: record, json: json)
        }
    }

    func delete(record: DocumentRecord) async -> Bool {
        guard let driver, let database = selectedDatabase, let collection = selectedCollection else {
            return false
        }
        return await mutate { try await driver.delete(database: database, collection: collection, record: record) }
    }

    func createCollection(name: String) async -> Bool {
        guard let driver, let database = selectedDatabase else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { editError = "A collection name is required."; return false }
        let succeeded = await runCollectionOp {
            try await driver.createCollection(database: database, name: trimmed)
        }
        if succeeded { await select(database: database) }
        return succeeded
    }

    func dropCollection(_ collection: String) async -> Bool {
        guard let driver, let database = selectedDatabase else { return false }
        let succeeded = await runCollectionOp {
            try await driver.dropCollection(database: database, collection: collection)
        }
        if succeeded {
            if selectedCollection == collection { documents = [] }
            await select(database: database)
        }
        return succeeded
    }

    func clearEditError() {
        editError = nil
    }

    private func runCollectionOp(_ operation: @Sendable () async throws -> Void) async -> Bool {
        editError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch {
            editError = Self.asDatabaseError(error).message
            return false
        }
    }

    private func mutate(_ operation: @Sendable () async throws -> Void) async -> Bool {
        editError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            await loadPage()
            return true
        } catch {
            editError = Self.asDatabaseError(error).message
            return false
        }
    }
}
