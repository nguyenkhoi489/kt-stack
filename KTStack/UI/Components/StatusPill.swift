import KTStackKit
import SwiftUI

struct StatusPill: View {
    private let status: ServiceStatus
    private let text: String?

    init(_ status: ServiceStatus, text: String? = nil) {
        self.status = status
        self.text = text
    }

    var body: some View {
        HStack(spacing: KDSpacing.space1) {
            Image(systemName: status.symbolName)
            Text(text ?? status.label)
        }
        .font(KDFont.footnote)
        .foregroundStyle(status.color)
        .padding(.vertical, KDSpacing.space1)
        .padding(.horizontal, KDSpacing.space2)
        .background(Capsule().fill(status.color.opacity(0.15)))
        .accessibilityLabel("\(status.label)\(text.map { ", \($0)" } ?? "")")
    }
}
