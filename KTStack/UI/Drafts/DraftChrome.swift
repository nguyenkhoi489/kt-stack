#if DEBUG
    import KTStackKit
    import SwiftUI

    enum DraftConnectionState {
        case connected
        case connecting
        case disconnected

        var led: Color {
            switch self {
            case .connected: KTEditorTheme.Status.running
            case .connecting: KTEditorTheme.accent
            case .disconnected: KTEditorTheme.Status.error
            }
        }

        var label: String {
            switch self {
            case .connected: "Connected"
            case .connecting: "Connecting…"
            case .disconnected: "Disconnected"
            }
        }
    }

    struct DraftTrafficLights: View {
        var body: some View {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
                Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 12, height: 12)
                Circle().fill(Color(hex: 0x28C840)).frame(width: 12, height: 12)
            }
        }
    }

    struct DraftConnectionPill: View {
        let state: DraftConnectionState

        var body: some View {
            HStack(spacing: 5) {
                Circle().fill(state.led).frame(width: 7, height: 7)
                Text(state.label)
                    .font(.system(size: 11))
                    .foregroundStyle(KTEditorTheme.label2)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(KTEditorTheme.pillBg, in: Capsule())
        }
    }

    struct DraftChrome<Content: View>: View {
        var schema: String = DraftSampleData.schemaName
        var activeTab: DraftObjectTab
        var connection: DraftConnectionState = .connected
        var selectedTable: String = DraftSampleData.selectedTable
        @ViewBuilder var content: () -> Content

        var body: some View {
            VStack(spacing: 0) {
                titlebar
                objectTabs
                HStack(spacing: 0) {
                    DraftTableSidebar(selectedTable: selectedTable)
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(KTEditorTheme.content)
                }
            }
            .background(KTEditorTheme.window)
        }

        private var titlebar: some View {
            HStack(spacing: 11) {
                DraftTrafficLights()
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: 0xFFF1E0))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 12))
                            .foregroundStyle(KTEditorTheme.switcherIcon)
                    )
                HStack(spacing: 6) {
                    Text("SQL Editor")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KTEditorTheme.label)
                    Text(schema)
                        .font(.jbMono(12))
                        .foregroundStyle(KTEditorTheme.label2)
                }
                Spacer()
                DraftConnectionPill(state: connection)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                LinearGradient(
                    colors: [KTEditorTheme.titlebarTop, KTEditorTheme.titlebarBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        private var objectTabs: some View {
            HStack(spacing: 2) {
                ForEach(DraftObjectTab.allCases) { tab in
                    let isActive = tab == activeTab
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 11)).opacity(0.8)
                        Text(tab.rawValue).font(.system(size: 12))
                    }
                    .foregroundStyle(isActive ? KTEditorTheme.label : KTEditorTheme.label2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        isActive ? KTEditorTheme.content : .clear,
                        in: UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                    )
                    .overlay(alignment: .bottom) {
                        if isActive { Rectangle().fill(KTEditorTheme.accent).frame(height: 1.5) }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .background(KTEditorTheme.window)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }
    }

    struct DraftTableSidebar: View {
        let selectedTable: String

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "cylinder.split.1x2").foregroundStyle(KTEditorTheme.switcherIcon)
                    Text(DraftSampleData.schemaName)
                        .font(.jbMono(12.5, .semibold))
                        .foregroundStyle(KTEditorTheme.label)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(KTEditorTheme.label3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }

                HStack(spacing: 8) {
                    Text("TABLES")
                        .font(.jbMono(11, .bold))
                        .tracking(0.5)
                        .foregroundStyle(KTEditorTheme.label2)
                    Spacer()
                    Image(systemName: "arrow.clockwise").font(.system(size: 11)).foregroundStyle(KTEditorTheme.label2)
                    Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(KTEditorTheme.label2)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                DraftSearchField(placeholder: "Filter tables")
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(DraftSampleData.tables) { table in
                            sidebarRow(table)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
            .frame(width: 248)
            .background(KTEditorTheme.sidebar)
            .overlay(alignment: .trailing) { Divider().overlay(KTEditorTheme.separator) }
        }

        private func sidebarRow(_ table: DraftTable) -> some View {
            let isSelected = table.name == selectedTable
            return HStack(spacing: 8) {
                Image(systemName: table.isView ? "eye" : "tablecells")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : KTEditorTheme.label3)
                    .frame(width: 14)
                Text(table.name)
                    .font(.jbMono(12.5))
                    .foregroundStyle(isSelected ? .white : KTEditorTheme.label)
                Spacer()
                if !table.isView {
                    Text(table.rowCount.formatted(.number.notation(.compactName)))
                        .font(.jbMono(11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : KTEditorTheme.label3)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                isSelected ? KTEditorTheme.accent : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
    }

    struct DraftSearchField: View {
        let placeholder: String

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(KTEditorTheme.label3)
                Text(placeholder).font(.system(size: 12.5)).foregroundStyle(KTEditorTheme.label3)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(KTEditorTheme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(KTEditorTheme.fieldBorder, lineWidth: 1))
        }
    }

#endif
