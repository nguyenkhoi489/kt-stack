#if DEBUG
    import KTStackKit
    import SwiftUI

    struct DraftQueryTabView: View {
        private let resultColumns = ["id", "name", "country"]
        private let resultRows: [DraftRow] = [
            DraftRow(cells: [.number("7"), .text("Hana Vo"), .text("Vietnam")]),
            DraftRow(cells: [.number("3"), .text("Linh Tran"), .text("Vietnam")]),
            DraftRow(cells: [.number("12"), .text("Mai Ho"), .text("Japan")]),
            DraftRow(cells: [.number("21"), .text("Vy Dang"), .text("Vietnam")]),
            DraftRow(cells: [.number("9"), .text("Thu Nguyen"), .text("Korea")]),
            DraftRow(cells: [.number("2"), .text("Quang Le"), .text("Japan")]),
        ]

        var body: some View {
            DraftChrome(activeTab: .query) {
                VStack(spacing: 0) {
                    queryTabs
                    toolbar
                    editor
                    Divider().overlay(KTEditorTheme.separator)
                    DraftGrid(columnTitles: resultColumns, rows: resultRows)
                    statusBar
                }
            }
        }

        private var queryTabs: some View {
            HStack(spacing: 0) {
                queryTab("Query 1", active: true)
                queryTab("Query 2", active: false)
                HStack { Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(KTEditorTheme.label2) }
                    .padding(.horizontal, 12).frame(maxHeight: .infinity)
                Spacer()
            }
            .frame(height: 34)
            .background(KTEditorTheme.content2)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        private func queryTab(_ title: String, active: Bool) -> some View {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 12)).foregroundStyle(active ? KTEditorTheme.label : KTEditorTheme.label2)
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(KTEditorTheme.label3)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(active ? KTEditorTheme.content : .clear)
            .overlay(alignment: .trailing) { Rectangle().fill(KTEditorTheme.separator).frame(width: 1) }
        }

        private var toolbar: some View {
            HStack(spacing: 10) {
                DraftButton(title: "Run Query", systemImage: "play.fill", shortcut: "⌘↩", kind: .primary)
                DraftButton(title: "Format")
                DraftButton(title: "Export CSV", systemImage: "square.and.arrow.up")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }

        private var editor: some View {
            ScrollView {
                HStack {
                    Text(DraftSQLHighlighter.highlight(DraftSampleData.sampleSQL))
                        .font(.jbMono(12.5))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(height: 132)
            .background(KTEditorTheme.content)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(KTEditorTheme.separator, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }

        private var statusBar: some View {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                    Text("6 rows").font(.jbMono(11))
                }
                .foregroundStyle(KTEditorTheme.Status.running)
                Spacer()
                Text("12 ms").font(.jbMono(11)).foregroundStyle(KTEditorTheme.label2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(KTEditorTheme.content2)
            .overlay(alignment: .top) { Divider().overlay(KTEditorTheme.separator) }
        }
    }

    enum DraftSQLHighlighter {
        private static let keywords: Set<String> = [
            "SELECT", "FROM", "JOIN", "INNER", "LEFT", "RIGHT", "ON", "WHERE",
            "GROUP", "BY", "ORDER", "LIMIT", "AS", "DESC", "ASC", "AND", "OR",
            "INSERT", "UPDATE", "DELETE", "SET", "VALUES", "INTO", "COUNT", "DISTINCT",
        ]

        static func highlight(_ sql: String) -> AttributedString {
            var result = AttributedString()
            var index = sql.startIndex

            while index < sql.endIndex {
                let character = sql[index]

                if character == "'" {
                    let start = index
                    index = sql.index(after: index)
                    while index < sql.endIndex, sql[index] != "'" {
                        index = sql.index(after: index)
                    }
                    if index < sql.endIndex { index = sql.index(after: index) }
                    result.append(styled(String(sql[start..<index]), KTEditorTheme.Syntax.string))
                    continue
                }

                if character.isLetter || character == "_" {
                    let start = index
                    while index < sql.endIndex && (sql[index].isLetter || sql[index].isNumber || sql[index] == "_") {
                        index = sql.index(after: index)
                    }
                    let word = String(sql[start..<index])
                    let color = keywords.contains(word.uppercased()) ? KTEditorTheme.Syntax.keyword : KTEditorTheme.label
                    result.append(styled(word, color))
                    continue
                }

                if character.isNumber {
                    let start = index
                    while index < sql.endIndex, sql[index].isNumber || sql[index] == "." {
                        index = sql.index(after: index)
                    }
                    result.append(styled(String(sql[start..<index]), KTEditorTheme.Syntax.number))
                    continue
                }

                result.append(styled(String(character), KTEditorTheme.label))
                index = sql.index(after: index)
            }

            return result
        }

        private static func styled(_ text: String, _ color: Color) -> AttributedString {
            var piece = AttributedString(text)
            piece.foregroundColor = color
            return piece
        }
    }

    #if DEBUG
        #Preview {
            DraftQueryTabView().frame(width: 1200, height: 720)
        }
    #endif

#endif
