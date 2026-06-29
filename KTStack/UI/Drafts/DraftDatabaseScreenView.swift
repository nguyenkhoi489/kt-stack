#if DEBUG
    import KTStackKit
    import SwiftUI

    private enum DraftServerStatus {
        case online(String)
        case connecting(String)
        case offline(String)
    }

    private struct DraftServer: Identifiable {
        let id = UUID()
        let name: String
        let engine: String
        let engineTint: Color
        let engineBackground: Color
        let badge: String?
        let status: DraftServerStatus
    }

    struct DraftDatabaseScreenView: View {
        private let servers: [DraftServer] = [
            DraftServer(
                name: "phongda",
                engine: "MySQL",
                engineTint: Color(hex: 0x1FA463),
                engineBackground: Color(hex: 0xE7F8EE),
                badge: nil,
                status: .online("Online · 127.0.0.1:3306 · 23 databases")
            ),
            DraftServer(
                name: "MySQL (managed)",
                engine: "MySQL",
                engineTint: Color(hex: 0x1FA463),
                engineBackground: Color(hex: 0xE7F8EE),
                badge: "bundled",
                status: .online("Online · 127.0.0.1:3306 · 5 databases")
            ),
            DraftServer(
                name: "PostgreSQL (managed)",
                engine: "Postgres",
                engineTint: Color(hex: 0x2F6BFF),
                engineBackground: Color(hex: 0xEAF1FF),
                badge: "bundled",
                status: .connecting("Connecting… · 127.0.0.1:5432")
            ),
            DraftServer(
                name: "MongoDB (managed)",
                engine: "Mongo",
                engineTint: Color(hex: 0x13AA52),
                engineBackground: Color(hex: 0xE5F7EC),
                badge: "bundled",
                status: .offline("Offline · engine not running")
            ),
        ]

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    segmented
                    searchField
                    VStack(spacing: 10) {
                        ForEach(servers) { serverRow($0) }
                    }
                }
                .padding(24)
                .background(KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(KTEditorTheme.separator, lineWidth: 1))
                .padding(24)
            }
            .background(Color(hex: 0xEDEDF0))
        }

        private var header: some View {
            HStack(spacing: 12) {
                Text("Database").font(.system(size: 20, weight: .bold)).foregroundStyle(KTEditorTheme.label)
                Text("4 connections").font(.system(size: 11)).foregroundStyle(KTEditorTheme.label2)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(KTEditorTheme.pillBg, in: Capsule())
                Spacer()
                DraftButton(title: "Connect", systemImage: "link")
                DraftButton(title: "Import", systemImage: "square.and.arrow.down")
                DraftButton(title: "Backup All", systemImage: "arrow.down.doc")
                DraftButton(title: "New Database", systemImage: "plus", kind: .primary)
            }
            .padding(.bottom, 16)
        }

        private var segmented: some View {
            HStack(spacing: 0) {
                segment("Servers", active: true)
                segment("Backups", active: false)
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(KTEditorTheme.btnBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        }

        private func segment(_ title: String, active: Bool) -> some View {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(active ? .white : KTEditorTheme.label2)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(active ? KTEditorTheme.accent : .clear)
        }

        private var searchField: some View {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(KTEditorTheme.label3)
                Text("Search connections…").font(.system(size: 13)).foregroundStyle(KTEditorTheme.label3)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(KTEditorTheme.fieldBg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(KTEditorTheme.fieldBorder, lineWidth: 1))
            .padding(.bottom, 14)
        }

        private func serverRow(_ server: DraftServer) -> some View {
            let isOffline = if case .offline = server.status { true } else { false }
            return HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(server.engineBackground)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "cylinder.split.1x2").font(.system(size: 16)).foregroundStyle(server.engineTint))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(server.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(KTEditorTheme.label)
                        Text(server.engine).font(.jbMono(10.5, .semibold)).foregroundStyle(server.engineTint)
                            .padding(.horizontal, 7).padding(.vertical, 1)
                            .background(server.engineBackground, in: RoundedRectangle(cornerRadius: 5))
                        if let badge = server.badge {
                            Text(badge).font(.jbMono(11.5)).foregroundStyle(KTEditorTheme.label2)
                        }
                    }
                    statusLabel(server.status)
                }
                Spacer()
                DraftButton(title: "Open", kind: isOffline ? .standard : .primary).opacity(isOffline ? 0.5 : 1)
                DraftIconButton(systemImage: "arrow.down.to.line")
                DraftIconButton(systemImage: "ellipsis")
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(KTEditorTheme.separator, lineWidth: 1))
        }

        @ViewBuilder
        private func statusLabel(_ status: DraftServerStatus) -> some View {
            switch status {
            case let .online(text): statusRow(text, tint: KTEditorTheme.Status.running)
            case let .connecting(text): statusRow(text, tint: KTEditorTheme.accent)
            case let .offline(text): statusRow(text, tint: KTEditorTheme.label3)
            }
        }

        private func statusRow(_ text: String, tint: Color) -> some View {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(text).font(.system(size: 12)).foregroundStyle(tint)
            }
        }
    }

    #if DEBUG
        #Preview {
            DraftDatabaseScreenView().frame(width: 1100, height: 720)
        }
    #endif

#endif
