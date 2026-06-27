import SwiftUI
import KTStackKit

enum KTDatabaseVisuals {
    static func engineLabel(_ kind: DatabaseKind) -> String {
        switch kind {
        case .mysql: return "MySQL"
        case .postgres: return "PostgreSQL"
        case .sqlite: return "SQLite"
        case .mongodb: return "MongoDB"
        }
    }
}

struct KTServerRow: View {
    let profile: ConnectionProfile
    let status: ServerStatus
    let databaseCount: Int?
    let onOpen: () -> Void
    let onOpenV2: () -> Void
    let onBackup: () -> Void
    let onRestore: () -> Void

    @State private var hovering = false

    private var isOnline: Bool { status == .online }
    private var engineTint: KTTint { KTEngineTint.of(profile.kind.rawValue) }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 11)
                .fill(engineTint.bg)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 16))
                        .foregroundStyle(engineTint.fg)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(profile.name).font(KTType.rowName).foregroundStyle(KTColor.ink)
                    KTBadge(text: KTDatabaseVisuals.engineLabel(profile.kind),
                            tint: engineTint, radius: 5)
                    if profile.isManaged {
                        Text("bundled").font(KTType.sub).foregroundStyle(KTColor.muted)
                    }
                }
                statusLine
            }
            Spacer(minLength: 8)
            KTButton(title: "Open", kind: .primary, action: onOpen).disabled(!isOnline)
            KTButton(title: "v2", kind: .secondary, action: onOpenV2).disabled(!isOnline)
            ghostIcon("tray.and.arrow.down", help: "Backup now", action: onBackup)
                .disabled(!isOnline)
                .opacity(isOnline ? 1 : 0.4)
            Menu {
                Button("Open in Editor", systemImage: "tablecells", action: onOpen).disabled(!isOnline)
                Button("Backup Now", systemImage: "tray.and.arrow.down", action: onBackup).disabled(!isOnline)
                Button("Restore from Backups…", systemImage: "clock.arrow.circlepath", action: onRestore)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular))
                    .foregroundStyle(KTColor.muted).frame(width: 28, height: 30).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? KTColor.rowHover : .white))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(KTColor.sep, lineWidth: 1))
        .onHover { hovering = $0 }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
                .shadow(color: isOnline ? statusColor.opacity(0.55) : .clear, radius: isOnline ? 2.5 : 0)
            Text(statusText).font(KTType.sub).foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch status {
        case .online:     return KTColor.online
        case .connecting: return KTColor.accent
        case .offline:    return KTColor.muted
        }
    }

    private var statusText: String {
        switch status {
        case .online:     return "Online · \(endpoint)\(databaseSuffix)"
        case .connecting: return "Connecting… · \(endpoint)"
        case .offline:    return profile.isManaged ? "Offline · engine not running" : "Offline"
        }
    }

    private var databaseSuffix: String {
        guard let count = databaseCount else { return "" }
        return " · \(count) \(count == 1 ? "database" : "databases")"
    }

    private var endpoint: String {
        if profile.kind == .sqlite {
            return (profile.filePath as NSString?)?.lastPathComponent ?? "file"
        }
        return "\(profile.host):\(profile.port)"
    }

    private func ghostIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(KTColor.ink3)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(KTColor.btnBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
