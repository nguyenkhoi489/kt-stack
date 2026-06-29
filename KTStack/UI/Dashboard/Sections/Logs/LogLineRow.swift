import KTStackKit
import SwiftUI

struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: KDSpacing.space2) {
            Rectangle().fill(gutterColor).frame(width: 3)
            Text(line.text)
                .font(.jbMono(11))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
        .padding(.trailing, KDSpacing.space2)
    }

    private var gutterColor: Color {
        switch line.severity {
        case .info: .clear
        case .warning: Color.KDStatus.warning
        case .error: Color.KDStatus.error
        }
    }

    private var textColor: Color {
        switch line.severity {
        case .info: .primary
        case .warning: Color.KDStatus.warning
        case .error: Color.KDStatus.error
        }
    }
}
