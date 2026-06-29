import KTStackKit
import SwiftUI

struct ServiceErrorBanner: View {
    let status: ServiceStatus
    let title: String
    let message: String
    var ctaTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: KDSpacing.space2) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.color)
                .font(.system(size: 15, weight: .regular))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KDFont.body).fontWeight(.medium)
                Text(message).font(KDFont.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: KDSpacing.space2)
            if let ctaTitle, let action {
                Button(ctaTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(KDSpacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(status.color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(status.color.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}
