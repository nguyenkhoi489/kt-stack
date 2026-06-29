import KTStackKit
import SwiftUI

struct KTAPIResponseView: View {
    let response: APIResponseResult
    let bodyLimitKB: Int

    enum ResponseTab: Hashable { case body, headers }

    @State private var tab: ResponseTab = .body
    @State private var raw = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            content
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            statusBadge
            metric("time", "\(response.elapsedMs) ms")
            metric("size", byteString)
            Spacer()
            KTSegmentedTabs(
                items: [
                    .init(value: ResponseTab.body, label: "Body"),
                    .init(value: .headers, label: "Headers"),
                ],
                selection: $tab
            )
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private var statusBadge: some View {
        let tint = statusTint
        return Text("\(response.statusCode)")
            .font(.jbMono(13, .bold))
            .foregroundStyle(tint.fg)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.bg))
    }

    private var statusTint: KTTint {
        switch response.statusCode {
        case 200...299: KTTint(fg: Color(hex: 0x1FA463), bg: Color(hex: 0xE7F8EE))
        case 300...399: KTTint(fg: Color(hex: 0x2F6BFF), bg: Color(hex: 0xEAF1FF))
        case 400...499: KTTint(fg: Color(hex: 0xC07A00), bg: Color(hex: 0xFFF3DC))
        default: KTTint(fg: Color(hex: 0xD93A2E), bg: Color(hex: 0xFFF0EE))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.jbMono(11)).foregroundStyle(KTColor.faint)
            Text(value).font(.jbMono(12, .medium)).foregroundStyle(KTColor.ink2)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .body: bodyView
        case .headers: headersView
        }
    }

    private var bodyView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                if truncated {
                    Text("truncated to \(bodyLimitKB) KB")
                        .font(.jbMono(11)).foregroundStyle(Color(hex: 0xC07A00))
                }
                Toggle("Raw", isOn: $raw)
                    .toggleStyle(.switch).controlSize(.mini)
                    .font(.jbMono(11))
                copyButton
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    Text(displayedBody)
                        .font(.jbMono(12))
                        .foregroundStyle(KTColor.ink)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
            .modifier(ResponsePanel())
        }
    }

    private var headersView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(response.headers.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 10) {
                        Text(pair.0).font(.jbMono(12, .medium)).foregroundStyle(KTColor.ink2)
                            .frame(width: 180, alignment: .leading)
                        Text(pair.1).font(.jbMono(12)).foregroundStyle(KTColor.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .modifier(ResponsePanel())
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fullBody, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(KTColor.muted)
        }
        .buttonStyle(.plain)
        .help("Copy body")
    }

    private var byteString: String {
        let bytes = response.body.count
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    private var fullBody: String {
        if !raw, let pretty = Self.prettyJSON(response.body) { return pretty }
        return String(data: response.body, encoding: .utf8) ?? "<\(response.body.count) bytes binary>"
    }

    private var limitChars: Int {
        max(1, bodyLimitKB) * 1024
    }

    private var truncated: Bool {
        fullBody.count > limitChars
    }

    private var displayedBody: String {
        let body = fullBody
        guard body.count > limitChars else { return body }
        return String(body.prefix(limitChars)) + "\n… (truncated)"
    }

    private struct ResponsePanel: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(Color(hex: 0xFBFBFC))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(KTColor.fieldBorder, lineWidth: 0.5)
                )
                .padding([.horizontal, .bottom], 14)
        }
    }

    static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        guard let pretty = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }
}
