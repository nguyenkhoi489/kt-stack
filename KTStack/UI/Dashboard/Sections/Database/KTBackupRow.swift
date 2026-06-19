import SwiftUI
import KTStackKit

struct KTBackupRow: View {
    let backup: BackupSet
    let onRestore: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var isFull: Bool { backup.databases.count != 1 }

    var body: some View {
        HStack(spacing: 14) {
            KTIconTile(tint: KTIconTint.neutral, size: 38, radius: 10) {
                Image(systemName: "archivebox").font(.system(size: 17, weight: .regular))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text(title).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(KTColor.ink)
                    KTBadge(text: isFull ? "Full" : "Single",
                            tint: isFull ? KTTint(fg: KTColor.accent, bg: Color(hex: 0xEAF1FF)) : KTTint(fg: KTColor.ink3, bg: KTColor.pillBg),
                            radius: 6)
                }
                Text("\(created) · \(size)").font(KTType.sub).foregroundStyle(KTColor.muted)
            }
            Spacer(minLength: 8)
            Button(action: onRestore) {
                Text("Restore").font(.system(size: 13, weight: .medium)).foregroundStyle(KTColor.accent)
                    .padding(.vertical, 7).padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(hex: 0xBFD4FF), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            ghostIcon("arrow.down.to.line", color: KTColor.ink3, help: "Download", action: onDownload)
            ghostIcon("trash", color: KTColor.danger, help: "Delete", action: onDelete)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(hovering ? KTColor.rowHover : Color.clear)
        .onHover { hovering = $0 }
    }

    private var title: String {
        if backup.databases.count == 1 { return backup.databases[0] }
        return "All databases"
    }

    private var size: String {
        ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file)
    }

    private var created: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: backup.createdAt)
    }

    private func ghostIcon(_ symbol: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(KTColor.btnBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
