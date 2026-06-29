#if DEBUG
    import Foundation

    enum DraftObjectTab: String, CaseIterable, Identifiable {
        case data = "Data"
        case structure = "Structure"
        case query = "Query"
        case er = "ER"

        var id: String {
            rawValue
        }

        var symbol: String {
            switch self {
            case .data: "tablecells"
            case .structure: "list.bullet.rectangle"
            case .query: "terminal"
            case .er: "point.3.connected.trianglepath.dotted"
            }
        }
    }

    enum DraftColumnKey {
        case none
        case primary
        case foreign
    }

    struct DraftColumn: Identifiable {
        let id = UUID()
        let name: String
        let type: String
        let nullable: Bool
        let key: DraftColumnKey
        let defaultValue: String?
    }

    enum DraftCell {
        case text(String)
        case number(String)
        case foreign(String)
        case null
    }

    struct DraftRow: Identifiable {
        let id = UUID()
        let cells: [DraftCell]
    }

    struct DraftTable: Identifiable {
        let id = UUID()
        let name: String
        let isView: Bool
        let rowCount: Int
        let columns: [DraftColumn]
        let rows: [DraftRow]
    }

    enum DraftSampleData {
        static let schemaName = "shop_dev"

        static let usersColumns: [DraftColumn] = [
            DraftColumn(name: "id", type: "bigint", nullable: false, key: .primary, defaultValue: nil),
            DraftColumn(name: "name", type: "varchar(120)", nullable: false, key: .none, defaultValue: nil),
            DraftColumn(name: "email", type: "varchar(180)", nullable: false, key: .none, defaultValue: nil),
            DraftColumn(name: "age", type: "int", nullable: true, key: .none, defaultValue: "NULL"),
            DraftColumn(name: "country_id", type: "bigint", nullable: true, key: .foreign, defaultValue: nil),
            DraftColumn(name: "balance", type: "decimal(12,2)", nullable: false, key: .none, defaultValue: "0.00"),
            DraftColumn(name: "created_at", type: "timestamp", nullable: false, key: .none, defaultValue: "now()"),
        ]

        static let usersRows: [DraftRow] = [
            DraftRow(cells: [.number("1"), .text("Linh Tran"), .text("linh@shop.dev"), .number("29"), .foreign("12"), .number("1280.50"), .text("2026-01-12 09:14")]),
            DraftRow(cells: [.number("2"), .text("Minh Pham"), .text("minh@shop.dev"), .null, .foreign("12"), .number("0.00"), .text("2026-02-03 18:40")]),
            DraftRow(cells: [.number("3"), .text("Hana Vo"), .text("hana@shop.dev"), .number("34"), .foreign("7"), .number("942.10"), .text("2026-02-21 11:02")]),
            DraftRow(cells: [.number("4"), .text("Quang Le"), .text("quang@shop.dev"), .number("41"), .null, .number("17.25"), .text("2026-03-08 07:55")]),
            DraftRow(cells: [.number("5"), .text("Thu Nguyen"), .text("thu@shop.dev"), .number("26"), .foreign("3"), .number("5320.00"), .text("2026-03-19 22:31")]),
            DraftRow(cells: [.number("6"), .text("Bao Do"), .null, .number("38"), .foreign("7"), .number("88.40"), .text("2026-04-01 14:10")]),
            DraftRow(cells: [.number("7"), .text("Mai Ho"), .text("mai@shop.dev"), .number("31"), .foreign("12"), .number("210.75"), .text("2026-04-15 16:48")]),
            DraftRow(cells: [.number("8"), .text("Khoa Bui"), .text("khoa@shop.dev"), .null, .foreign("3"), .number("0.00"), .text("2026-05-02 08:22")]),
            DraftRow(cells: [.number("9"), .text("Vy Dang"), .text("vy@shop.dev"), .number("23"), .foreign("7"), .number("1499.99"), .text("2026-05-20 13:37")]),
            DraftRow(cells: [.number("10"), .text("Phuc Ly"), .text("phuc@shop.dev"), .number("45"), .null, .number("64.00"), .text("2026-06-09 19:05")]),
        ]

        static let tables: [DraftTable] = [
            DraftTable(name: "users", isView: false, rowCount: 10482, columns: usersColumns, rows: usersRows),
            DraftTable(name: "orders", isView: false, rowCount: 48201, columns: [], rows: []),
            DraftTable(name: "order_items", isView: false, rowCount: 132_940, columns: [], rows: []),
            DraftTable(name: "products", isView: false, rowCount: 3120, columns: [], rows: []),
            DraftTable(name: "categories", isView: false, rowCount: 64, columns: [], rows: []),
            DraftTable(name: "countries", isView: false, rowCount: 195, columns: [], rows: []),
            DraftTable(name: "active_users", isView: true, rowCount: 0, columns: [], rows: []),
        ]

        static let selectedTable = "users"

        static let indexes: [(name: String, columns: String, unique: Bool)] = [
            ("PRIMARY", "id", true),
            ("uq_users_email", "email", true),
            ("idx_users_country", "country_id", false),
        ]

        static let sampleSQL = """
        SELECT u.id, u.name, u.email, c.name AS country
        FROM users u
        JOIN countries c ON c.id = u.country_id
        WHERE u.balance > 100.00
        ORDER BY u.created_at DESC
        LIMIT 50;
        """

        static let completionItems: [(label: String, hint: String)] = [
            ("users", "table"),
            ("user_id", "column"),
            ("updated_at", "column"),
            ("UPPER(", "function"),
            ("UNION", "keyword"),
        ]
    }

#endif
