import KTStackKit
import SwiftUI

struct KTDot: View {
    var color: Color
    var size: CGFloat = KTMetric.statusDot

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

struct KTStatusLabel: View {
    let running: Bool
    var runningText: String = "Running"
    var stoppedText: String = "Stopped"

    var body: some View {
        HStack(spacing: 7) {
            KTDot(color: running ? KTColor.runDot : KTColor.stopDot)
            Text(running ? runningText : stoppedText)
                .font(.jbMono(13, .medium))
                .foregroundStyle(running ? KTColor.runText : KTColor.stopText)
        }
    }
}

struct KTOnlineLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            KTDot(color: KTColor.runDot, size: 6)
            Text(text)
                .font(KTType.sub)
                .foregroundStyle(KTColor.muted)
        }
    }
}
