import SwiftUI
import KTStackKit

struct MailSectionView: View {
    @ObservedObject var nav: DashboardNavigation
    @EnvironmentObject private var mail: MailStore
    @EnvironmentObject private var services: ServiceManager

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 18)
            content.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 16).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KTColor.contentBg)
        .onAppear { if nav.activeItem == .mail { mail.startPolling() } }
        .onChange(of: nav.activeItem) { item in
            if item == .mail { mail.startPolling() } else { mail.stopPolling() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Mail").font(KTType.screenTitle).tracking(KTType.screenTitleTracking).foregroundStyle(KTColor.ink)
            Text("Mailpit · :8025")
                .font(.jbMono(12.5, .regular)).foregroundStyle(Color(hex: 0x8E8E93))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(KTColor.pillBg))
            Spacer()
            Button(action: { mail.deleteAll() }) {
                Text("Clear inbox").font(.jbMono(13, .medium)).foregroundStyle(KTColor.danger)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KTColor.dangerBorder, lineWidth: 0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(mail.messages.isEmpty)
            .opacity(mail.messages.isEmpty ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !mail.isReachable && mail.messages.isEmpty {
            offlineState
        } else {
            HStack(spacing: 14) {
                messageList
                detailPane
            }
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(mail.messages) { msg in
                    MailListRow(summary: msg, active: mail.selectedID == msg.ID) { mail.select(msg.ID) }
                }
            }
            .padding(6)
        }
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KTColor.sep, lineWidth: 0.5))
        .overlay { if mail.messages.isEmpty { listEmptyHint } }
    }

    private var listEmptyHint: some View {
        Text("No messages yet.\nSend mail from a site to :1025.")
            .font(.jbMono(12.5)).foregroundStyle(KTColor.muted).multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var detailPane: some View {
        Group {
            if let detail = mail.detail {
                MailMessageView(detail: detail,
                                onDelete: { mail.delete(detail.ID) },
                                rawURL: mail.rawURL(detail.ID))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "envelope.open").font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
                    Text("No message selected").font(.jbMono(16, .regular)).foregroundStyle(KTColor.ink3)
                    Text("Pick a message from the list to read it.").font(.jbMono(13)).foregroundStyle(KTColor.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KTColor.sep, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var offlineState: some View {
        EmptyStateView(symbol: "envelope", title: "Mailpit is off",
                       message: "Start Mailpit to catch outgoing mail from your sites and read it here.",
                       actionTitle: "Start Mailpit") { services.toggle(.mailpit) }
    }
}

struct MailListRow: View {
    let summary: MailSummary
    let active: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                MailAvatar(name: senderName)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(senderName).font(.jbMono(13.5, .regular))
                            .foregroundStyle(KTColor.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        if let date = summary.date {
                            Text(date.formatted(date: .omitted, time: .shortened))
                                .font(.jbMono(11.5)).foregroundStyle(KTColor.muted)
                        }
                    }
                    Text(summary.Subject.isEmpty ? "(no subject)" : summary.Subject)
                        .font(.jbMono(13)).foregroundStyle(KTColor.ink2).lineLimit(1)
                    Text(summary.Snippet).font(.jbMono(12)).foregroundStyle(KTColor.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(active ? KTColor.accentSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var senderName: String {
        let name = summary.From?.Name ?? ""
        return name.isEmpty ? (summary.From?.Address ?? "—") : name
    }
}

struct MailAvatar: View {
    let name: String

    private var tint: KTTint {
        let palette = [KTIconTint.code, KTIconTint.cube, KTIconTint.db, KTIconTint.globe, KTIconTint.mail]
        let index = Int(name.hashValue.magnitude % UInt(palette.count))
        return palette[index]
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased()
    }

    var body: some View {
        Text(initial)
            .font(.jbMono(13, .bold))
            .foregroundStyle(tint.fg)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint.bg))
    }
}
