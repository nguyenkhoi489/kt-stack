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

struct KTDatabaseRow: View {
    let name: String
    let kind: DatabaseKind
    let onOpen: () -> Void
    let onBackup: () -> Void
    let onExport: () -> Void
    let onRestore: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            KTIconTile(tint: KTEngineTint.of(kind.rawValue), size: 40, radius: 11) {
                Image(systemName: "cylinder.split.1x2").font(.system(size: 18, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text(name).font(.system(size: 14.5, weight: .semibold, design: .monospaced)).foregroundStyle(KTColor.ink)
                    KTBadge(text: KTDatabaseVisuals.engineLabel(kind), tint: KTEngineTint.of(kind.rawValue), radius: 6)
                }
                HStack(spacing: 7) {
                    KTDot(color: KTColor.runDot, size: 6)
                    Text("Online").font(KTType.sub).foregroundStyle(KTColor.muted)
                }
            }
            Spacer(minLength: 8)
            KTButton(title: "Open", kind: .secondary, action: onOpen)
            ghostIcon("tray.and.arrow.down", help: "Backup now", action: onBackup)
            Menu {
                Button("Open in Editor", systemImage: "tablecells", action: onOpen)
                Button("Backup Now", systemImage: "tray.and.arrow.down", action: onBackup)
                Button("Restore from Backups…", systemImage: "clock.arrow.circlepath", action: onRestore)
                Button("Export SQL…", systemImage: "square.and.arrow.up", action: onExport)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KTColor.muted).frame(width: 32, height: 30).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 32)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 18)
        .background(hovering ? KTColor.rowHover : Color.clear)
        .onHover { hovering = $0 }
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
