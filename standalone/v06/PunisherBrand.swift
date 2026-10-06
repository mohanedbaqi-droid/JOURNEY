import SwiftUI

struct PunisherBrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.red.opacity(0.28), Color.black.opacity(0.92)],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.62
                    )
                )
            Circle().stroke(Color.cyan.opacity(0.75), lineWidth: max(1, size * 0.025))
            Circle().trim(from: 0.08, to: 0.42)
                .stroke(Color.red, style: StrokeStyle(lineWidth: max(2, size * 0.055), lineCap: .round))
                .rotationEffect(.degrees(-18))
            Circle().trim(from: 0.58, to: 0.92)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: max(2, size * 0.045), lineCap: .round))
                .rotationEffect(.degrees(10))

            PunisherSkullShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.14, blue: 0.10), Color(red: 0.55, green: 0.01, blue: 0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(PunisherSkullShape().stroke(Color.red.opacity(0.95), lineWidth: max(0.8, size * 0.018)))
                .padding(size * 0.15)

            HStack(spacing: size * 0.085) {
                Capsule().fill(Color.white).frame(width: size * 0.18, height: size * 0.055).rotationEffect(.degrees(14))
                Capsule().fill(Color.white).frame(width: size * 0.18, height: size * 0.055).rotationEffect(.degrees(-14))
            }
            .offset(y: -size * 0.04)
        }
        .frame(width: size, height: size)
        .shadow(color: .red.opacity(0.35), radius: size * 0.14)
        .shadow(color: .cyan.opacity(0.18), radius: size * 0.12)
    }
}

private struct PunisherSkullShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.04))
        p.addCurve(to: CGPoint(x: w * 0.90, y: h * 0.34),
                   control1: CGPoint(x: w * 0.73, y: h * 0.03),
                   control2: CGPoint(x: w * 0.92, y: h * 0.16))
        p.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.61),
                   control1: CGPoint(x: w * 0.93, y: h * 0.47),
                   control2: CGPoint(x: w * 0.88, y: h * 0.57))
        p.addLine(to: CGPoint(x: w * 0.67, y: h * 0.64))
        p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.79))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.98))
        p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.79))
        p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.33, y: h * 0.64))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.61))
        p.addCurve(to: CGPoint(x: w * 0.10, y: h * 0.34),
                   control1: CGPoint(x: w * 0.12, y: h * 0.57),
                   control2: CGPoint(x: w * 0.07, y: h * 0.47))
        p.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.04),
                   control1: CGPoint(x: w * 0.08, y: h * 0.16),
                   control2: CGPoint(x: w * 0.27, y: h * 0.03))
        p.closeSubpath()
        return p
    }
}
