import Foundation

public struct V2QueryTab: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var text: String
    public var result: QueryResult?
    public var error: String?
    public var isRunning: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        text: String = "",
        result: QueryResult? = nil,
        error: String? = nil,
        isRunning: Bool = false
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.result = result
        self.error = error
        self.isRunning = isRunning
    }
}

extension DatabaseV2ViewModel {

    public var activeQueryTab: V2QueryTab? {
        guard let activeQueryTabID else { return queryTabs.first }
        return queryTabs.first { $0.id == activeQueryTabID } ?? queryTabs.first
    }

    public var queryText: String {
        get { activeQueryTab?.text ?? "" }
        set {
            guard let id = activeQueryTab?.id,
                  let idx = queryTabs.firstIndex(where: { $0.id == id }) else { return }
            queryTabs[idx].text = newValue
        }
    }

    public var queryResult: QueryResult? { activeQueryTab?.result }
    public var queryError: String? { activeQueryTab?.error }
    public var isRunning: Bool { activeQueryTab?.isRunning ?? false }

    public func addQueryTab() {
        let tab = V2QueryTab(title: "Query \(queryTabs.count + 1)")
        queryTabs.append(tab)
        activeQueryTabID = tab.id
    }

    public func closeQueryTab(id: UUID) {
        guard queryTabs.count > 1 else { return }
        guard let index = queryTabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeQueryTabID == id
        queryTabs.remove(at: index)
        if wasActive {
            activeQueryTabID = queryTabs[min(index, queryTabs.count - 1)].id
        }
    }

    public func selectQueryTab(id: UUID) {
        guard queryTabs.contains(where: { $0.id == id }) else { return }
        activeQueryTabID = id
    }

    public func runQuery() async {
        guard let driver, let tab = activeQueryTab else { return }
        let tabID = tab.id
        let text = tab.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mutateQueryTab(tabID) { t in
            t.isRunning = true
            t.result = nil
            t.error = nil
        }
        do {
            let result = try await driver.query(text, database: selectedDatabase)
            mutateQueryTab(tabID) { t in
                t.result = result
                t.isRunning = false
            }
        } catch {
            mutateQueryTab(tabID) { t in
                t.error = error.localizedDescription
                t.isRunning = false
            }
        }
    }

    public func cancelQuery() async {
        await driver?.cancelCurrentQuery()
        guard let id = activeQueryTab?.id,
              let idx = queryTabs.firstIndex(where: { $0.id == id }) else { return }
        queryTabs[idx].isRunning = false
    }

    private func mutateQueryTab(_ id: UUID, mutate: (inout V2QueryTab) -> Void) {
        guard let index = queryTabs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&queryTabs[index])
    }
}
