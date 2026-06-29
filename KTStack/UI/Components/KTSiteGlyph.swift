import KTStackKit
import SwiftUI

enum KTSiteIconKind: String, CaseIterable {
    case code, cube, db
}

struct KTSiteShape: Shape {
    let kind: KTSiteIconKind

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        switch kind {
        case .code:
            path.move(to: p(9, 8)); path.addLine(to: p(5, 12)); path.addLine(to: p(9, 16))
            path.move(to: p(15, 8)); path.addLine(to: p(19, 12)); path.addLine(to: p(15, 16))
        case .cube:
            path.move(to: p(12, 2)); path.addLine(to: p(3, 7)); path.addLine(to: p(3, 17))
            path.addLine(to: p(12, 22)); path.addLine(to: p(21, 17)); path.addLine(to: p(21, 7))
            path.closeSubpath()
            path.move(to: p(3, 7)); path.addLine(to: p(12, 12)); path.addLine(to: p(21, 7))
            path.move(to: p(12, 12)); path.addLine(to: p(12, 22))
        case .db:
            path.addEllipse(in: CGRect(
                x: rect.minX + 4 * scale,
                y: rect.minY + 2 * scale,
                width: 16 * scale,
                height: 6 * scale
            ))
            path.move(to: p(4, 5)); path.addLine(to: p(4, 17))
            path.move(to: p(20, 5)); path.addLine(to: p(20, 17))
            path.move(to: p(4, 11)); path.addQuadCurve(to: p(20, 11), control: p(12, 14))
            path.move(to: p(4, 17)); path.addQuadCurve(to: p(20, 17), control: p(12, 20))
        }
        return path
    }
}

struct KTSiteGlyph: View {
    let kind: KTSiteIconKind
    var size: CGFloat = 19
    var color: Color = .white

    var body: some View {
        KTSiteShape(kind: kind)
            .stroke(color, style: StrokeStyle(lineWidth: size / 24 * 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
