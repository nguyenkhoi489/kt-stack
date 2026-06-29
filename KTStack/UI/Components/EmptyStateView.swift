import KTStackKit
import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: KDSpacing.space4) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(spacing: KDSpacing.space2) {
                Text(title).font(KDFont.title)
                Text(message)
                    .font(KDFont.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(KDSpacing.space6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
