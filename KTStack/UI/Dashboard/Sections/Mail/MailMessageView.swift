import SwiftUI
import AppKit
import KTStackKit

struct MailMessageView: View {
    let detail: MailDetail
    let onDelete: () -> Void
    let rawURL: URL

    private enum Tab: String, CaseIterable { case plain = "Plain", html = "HTML" }
    @State private var tab: Tab = .plain

    private var senderName: String {
        let name = detail.From?.Name ?? ""
        return name.isEmpty ? (detail.From?.Address ?? "—") : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if hasHTML || (detail.Attachments?.isEmpty == false) { toolbar }
            bodyContent
            if let attachments = detail.Attachments, !attachments.isEmpty {
                Rectangle().fill(KTColor.sepFaint).frame(height: 0.5)
                attachmentsList(attachments)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.Subject.isEmpty ? "(no subject)" : detail.Subject)
                .font(.system(size: 18, weight: .bold)).tracking(-0.3).foregroundStyle(KTColor.ink).lineLimit(2)
            HStack(spacing: 8) {
                MailAvatar(name: senderName)
                VStack(alignment: .leading, spacing: 1) {
                    Text(senderName).font(.system(size: 13, weight: .semibold)).foregroundStyle(KTColor.ink)
                    Text(detail.From?.Address ?? "").font(.system(size: 12)).foregroundStyle(KTColor.muted)
                }
                Spacer()
                if let date = detail.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12)).foregroundStyle(KTColor.muted)
                }
                iconButton("doc.plaintext") { NSWorkspace.shared.open(rawURL) }
                iconButton("trash", tint: KTColor.danger, action: onDelete)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
    }

    private func iconButton(_ symbol: String, tint: Color = KTColor.ink3, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint).frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolbar: some View {
        HStack {
            if hasHTML {
                KTSegmentedTabs(items: [.init(value: Tab.plain, label: "Plain"), .init(value: .html, label: "HTML")],
                                selection: $tab)
                .fixedSize()
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if tab == .html && hasHTML {
            MailHTMLView(html: detail.HTML ?? "")
        } else {
            ScrollView {
                Text(detail.Text ?? detail.HTML?.strippingTags ?? "(empty)")
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(KTColor.ink2)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }
        }
    }

    private var hasHTML: Bool { detail.HTML?.isEmpty == false }

    private func attachmentsList(_ attachments: [MailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Attachments (\(attachments.count))").font(.system(size: 12, weight: .semibold)).foregroundStyle(KTColor.ink3)
            ForEach(attachments) { a in
                HStack(spacing: 8) {
                    Image(systemName: "paperclip").font(.system(size: 11)).foregroundStyle(KTColor.muted)
                    Text(a.FileName).font(.system(size: 12.5)).foregroundStyle(KTColor.ink2)
                    Text(ByteCountFormatter().string(fromByteCount: Int64(a.Size)))
                        .font(.system(size: 12)).foregroundStyle(KTColor.muted)
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }
}

private extension String {
    var strippingTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
