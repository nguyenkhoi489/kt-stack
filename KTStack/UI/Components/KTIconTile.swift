import KTStackKit
import SwiftUI

struct KTIconTile<Content: View>: View {
    let tint: KTTint
    var size: CGFloat = 38
    var radius: CGFloat = KTRadius.iconTileSmall
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(tint.fg)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.bg))
    }
}
