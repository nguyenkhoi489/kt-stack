#if DEBUG
    import KTStackKit
    import SwiftUI

    enum DraftScreen: String, CaseIterable, Identifiable {
        case dataTab
        case structureTab
        case queryTab
        case erTab
        case sheetsOverlays
        case databaseScreen

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .dataTab: "Data Tab"
            case .structureTab: "Structure Tab"
            case .queryTab: "Query Tab"
            case .erTab: "ER Tab"
            case .sheetsOverlays: "Sheets & Overlays"
            case .databaseScreen: "Database Screen"
            }
        }

        var subtitle: String {
            switch self {
            case .dataTab: "Grid, breadcrumb, filter, row detail"
            case .structureTab: "Columns, DDL toolbar, indexes"
            case .queryTab: "SQL editor, results, status bar"
            case .erTab: "Diagram nodes, edges, zoom"
            case .sheetsOverlays: "Row editor, DDL, alerts, popover"
            case .databaseScreen: "Server list, status, search"
            }
        }

        var symbol: String {
            switch self {
            case .dataTab: "tablecells"
            case .structureTab: "list.bullet.rectangle"
            case .queryTab: "terminal"
            case .erTab: "point.3.connected.trianglepath.dotted"
            case .sheetsOverlays: "rectangle.on.rectangle"
            case .databaseScreen: "server.rack"
            }
        }
    }

    struct SQLEditorDraftsGallery: View {
        @State private var selection: DraftScreen?

        var body: some View {
            Group {
                if let selection {
                    draftDetail(selection)
                } else {
                    galleryGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KTEditorTheme.window)
        }

        private var galleryGrid: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SQL Editor Drafts")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(KTEditorTheme.label)
                    Text("Static SwiftUI drafts of the light-theme demo. Mock data, no logic.")
                        .font(.system(size: 13))
                        .foregroundStyle(KTEditorTheme.label2)
                        .padding(.bottom, 18)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                        ForEach(DraftScreen.allCases) { screen in
                            Button { selection = screen } label: { card(screen) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(28)
            }
        }

        private func card(_ screen: DraftScreen) -> some View {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(KTEditorTheme.accentSoft)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: screen.symbol).foregroundStyle(KTEditorTheme.accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text(screen.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(KTEditorTheme.label)
                    Text(screen.subtitle).font(.system(size: 11.5)).foregroundStyle(KTEditorTheme.label2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(KTEditorTheme.label3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(KTEditorTheme.separator, lineWidth: 1))
        }

        private func draftDetail(_ screen: DraftScreen) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        selection = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                            Text("Drafts")
                        }
                        .font(.system(size: 12.5))
                        .foregroundStyle(KTEditorTheme.accent)
                    }
                    .buttonStyle(.plain)
                    Text(screen.title).font(.jbMono(12.5, .semibold)).foregroundStyle(KTEditorTheme.label2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(KTEditorTheme.content2)
                .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }

                destination(screen)
            }
        }

        @ViewBuilder
        private func destination(_ screen: DraftScreen) -> some View {
            switch screen {
            case .dataTab: DraftDataTabView()
            case .structureTab: DraftStructureTabView()
            case .queryTab: DraftQueryTabView()
            case .erTab: DraftERTabView()
            case .sheetsOverlays: DraftSheetsOverlaysView()
            case .databaseScreen: DraftDatabaseScreenView()
            }
        }
    }

#endif
