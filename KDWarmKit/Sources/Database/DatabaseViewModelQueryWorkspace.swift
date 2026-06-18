import Foundation

public extension DatabaseViewModel {
    var activeQueryTab: QueryTab? {
        guard let activeQueryTabID else { return queryTabs.first }
        return queryTabs.first { $0.id == activeQueryTabID } ?? queryTabs.first
    }

    func addQueryTab() {
        let tab = QueryTab(title: nextQueryTitle())
        queryTabs.append(tab)
        activeQueryTabID = tab.id
    }

    func selectQueryTab(_ id: UUID) {
        guard queryTabs.contains(where: { $0.id == id }) else { return }
        activeQueryTabID = id
    }

    func closeQueryTab(_ id: UUID) {
        guard queryTabs.count > 1, let index = queryTabs.firstIndex(where: { $0.id == id }) else {
            resetQueryWorkspace()
            return
        }
        let wasActive = activeQueryTabID == id
        queryTabs.remove(at: index)
        queryGenerations[id] = nil
        if wasActive {
            activeQueryTabID = queryTabs[min(index, queryTabs.count - 1)].id
        }
    }

    func updateQueryTabSQL(_ id: UUID, sql: String) {
        guard let index = queryTabs.firstIndex(where: { $0.id == id }) else { return }
        queryTabs[index].sql = sql
    }

    func updateActiveQuerySQL(_ sql: String) {
        guard let id = activeQueryTab?.id else { return }
        updateQueryTabSQL(id, sql: sql)
    }

    func runActiveQueryTab(confirmed: Bool = false) async {
        guard let id = activeQueryTab?.id else { return }
        await runSQL(tabID: id, confirmed: confirmed)
    }

    func runSQL(tabID: UUID, confirmed: Bool = false) async {
        guard let tab = queryTabs.first(where: { $0.id == tabID }) else { return }
        await executeSQL(tab.sql, tabID: tabID, confirmed: confirmed)
    }

    func runSQL(_ sql: String, confirmed: Bool = false) async {
        await executeSQL(sql, tabID: nil, confirmed: confirmed)
    }

    func cancelDangerousSQL() {
        pendingDangerousSQL = nil
    }

    func clearQueryHistory() {
        try? historyStore.clear()
        queryHistoryEntries = historyStore.entries()
    }
}

extension DatabaseViewModel {
    func clearQueryTabResults() {
        for index in queryTabs.indices {
            queryTabs[index].result = nil
            queryTabs[index].resultError = nil
            queryTabs[index].isBusy = false
        }
        queryGenerations = [:]
    }

    func resetQueryWorkspace() {
        let tab = QueryTab(title: "Query 1")
        queryTabs = [tab]
        activeQueryTabID = tab.id
        queryGenerations = [:]
    }

    private func executeSQL(_ sql: String, tabID: UUID?, confirmed: Bool) async {
        guard let driver else { return }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !confirmed, DestructiveGuard.evaluate(trimmed).isDestructive {
            pendingDangerousSQL = trimmed
            return
        }
        pendingDangerousSQL = nil
        let token = beginQueryOperation(tabID)
        do {
            let r = try await driver.query(trimmed, database: selectedDatabase)
            guard isCurrentQueryOperation(tabID, token: token) else { return }
            recordQueryHistory(trimmed)
            if tabID == nil {
                result = r
                resultError = nil
                resultSource = .query
            } else {
                updateQueryTab(tabID) { tab in
                    tab.result = r
                    tab.resultError = nil
                    tab.isBusy = false
                }
            }
            hasMorePages = false
        } catch {
            guard isCurrentQueryOperation(tabID, token: token) else { return }
            recordQueryHistory(trimmed)
            let message = Self.asDatabaseError(error).message
            if tabID == nil {
                result = nil
                resultError = message
                resultSource = .none
            } else {
                updateQueryTab(tabID) { tab in
                    tab.result = nil
                    tab.resultError = message
                    tab.isBusy = false
                }
            }
        }
    }

    private func beginQueryOperation(_ tabID: UUID?) -> Int {
        guard let tabID else { return 0 }
        let next = (queryGenerations[tabID] ?? 0) + 1
        queryGenerations[tabID] = next
        updateQueryTab(tabID) { tab in
            tab.isBusy = true
            tab.resultError = nil
        }
        return next
    }

    private func isCurrentQueryOperation(_ tabID: UUID?, token: Int) -> Bool {
        guard let tabID else { return true }
        return queryGenerations[tabID] == token && queryTabs.contains { $0.id == tabID }
    }

    private func updateQueryTab(_ id: UUID?, mutate: (inout QueryTab) -> Void) {
        guard let id, let index = queryTabs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&queryTabs[index])
    }

    private func nextQueryTitle() -> String {
        "Query \(queryTabs.count + 1)"
    }

    private func recordQueryHistory(_ sql: String) {
        try? historyStore.record(sql: sql,
                                 connectionLabel: selectedProfile?.name ?? "Unknown connection",
                                 database: selectedDatabase)
        queryHistoryEntries = historyStore.entries()
    }
}
