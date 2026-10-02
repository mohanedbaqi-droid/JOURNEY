import SwiftUI

/// Front-view white Dodge Journey SE Blacktop reflecting live ESP state.
struct CarVisualView: View {
    let state: VehicleState
    @State private var pulse = false

    /// Native dimensions of JourneySEClosed/Open.  Keeping the overlay in this
    /// coordinate system makes the lamps stay on the physical housings as the
    /// card changes width.
    private let carSourceSize = CGSize(width: 1536, height: 1024)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                groundGlow

                Image(vehicleAssetName)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.combined(with: .scale(scale: state.simulatedDoorsOpen ? 0.985 : 1.015)))
                    .frame(width: min(proxy.size.width + 18, 430))
                    .shadow(color: .black.opacity(0.72), radius: 18, y: 12)

                // The U-shaped white trim stays untouched.  Headlight output
                // is drawn only inside the four circular lamp lenses.
                if state.headlightsOn {
                    frontLightGlow(in: proxy.size)
                        .allowsHitTesting(false)
                }

                if state.leftSignalOn || state.rightSignalOn {
                    signalGlow(in: proxy.size)
                        .allowsHitTesting(false)
                }

                if state.hornActive { hornWaves }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .animation(.spring(response: 0.52, dampingFraction: 0.72), value: state.simulatedDoorsOpen)
        .animation(.easeInOut(duration: 0.25), value: state.headlightsOn)
        .animation(.easeInOut(duration: 0.18), value: state.leftSignalOn)
        .animation(.easeInOut(duration: 0.18), value: state.rightSignalOn)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.48).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("دودج جورني بلاك توب بيضاء من الأمام")
        .accessibilityValue(state.simulatedLocked ? "مقفلة" : "مفتوحة")
    }

    private var vehicleAssetName: String {
        if state.simulatedDoorsOpen {
            return "JourneyLEDOpen"
        } else {
            return "JourneyLEDClosed"
        }
    }

    private func frontLightGlow(in canvasSize: CGSize) -> some View {
        let imageRect = fittedCarImageRect(in: canvasSize)
        return ZStack {
            ForEach(Array(lensLayouts.enumerated()), id: \.offset) { _, lens in
                headlightGlow
                    .frame(
                        width: imageRect.width * lens.diameter / carSourceSize.width,
                        height: imageRect.width * lens.diameter / carSourceSize.width
                    )
                    .position(sourcePoint(x: lens.x, y: lens.y, in: imageRect))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func signalGlow(in canvasSize: CGSize) -> some View {
        let imageRect = fittedCarImageRect(in: canvasSize)
        let strips = signalStrips
        return ZStack {
            // The aftermarket Journey lamps use the thin lower amber strip.
            // Each side is a separate overlay, so one indicator never turns
            // the other side on and the white U light remains independent.
            // Button directions follow the screen: left lights the left side
            // of the picture and right lights the right side.
            JourneyTurnSignalStrip()
                .opacity(state.leftSignalOn ? 1 : 0)
                .frame(width: imageRect.width * strips.left.width / carSourceSize.width,
                       height: imageRect.height * strips.left.height / carSourceSize.height)
                .rotationEffect(.degrees(strips.left.rotation))
                .position(sourcePoint(x: strips.left.x, y: strips.left.y, in: imageRect))
                .opacity(pulse ? 1 : 0.12)
                .shadow(color: .orange.opacity(0.88), radius: 2.1)
            JourneyTurnSignalStrip()
                .opacity(state.rightSignalOn ? 1 : 0)
                .frame(width: imageRect.width * strips.right.width / carSourceSize.width,
                       height: imageRect.height * strips.right.height / carSourceSize.height)
                .rotationEffect(.degrees(strips.right.rotation))
                .position(sourcePoint(x: strips.right.x, y: strips.right.y, in: imageRect))
                .opacity(pulse ? 1 : 0.12)
                .shadow(color: .orange.opacity(0.88), radius: 2.1)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    /// Centre, size and angle of the amber strip inside each physical lamp.
    /// Directions follow what the driver sees on screen.
    private var signalStrips: (left: SignalStripLayout, right: SignalStripLayout) {
        if state.simulatedDoorsOpen {
            return (
                // Screen-left lamp follows the same lower-edge direction as
                // the closed-door artwork: inner end slightly lower.
                // Keep the outer end fixed, but stop short of the grille.
                SignalStripLayout(x: 184, y: 565, width: 144, height: 20, rotation: 9.0),
                SignalStripLayout(x: 917, y: 580, width: 262, height: 21, rotation: -3.5)
            )
        }
        return (
            // Screen-left lamp (the side opposite the open passenger door):
            // its amber bar sits *below* the round lenses and slopes only
            // gently with the lamp's lower edge.
            SignalStripLayout(x: 215, y: 576, width: 130, height: 20, rotation: 9.0),
            // Screen-right lamp: the inner end (nearest the grille) sits a
            // little lower while the outer end stays on the lamp edge.
            SignalStripLayout(x: 922, y: 582, width: 248, height: 21, rotation: -3.5)
        )
    }

    /// Reference lamp geometry: only the round white centres inside the U
    /// trim illuminate.  The U itself is purely cosmetic in this UI.
    private var lensLayouts: [LensLayout] {
        if state.simulatedDoorsOpen {
            return [
                LensLayout(x: 198, y: 500, diameter: 48),
                LensLayout(x: 260, y: 507, diameter: 42),
                LensLayout(x: 838, y: 526, diameter: 68),
                LensLayout(x: 946, y: 530, diameter: 62)
            ]
        }
        return [
            LensLayout(x: 213, y: 510, diameter: 50),
            LensLayout(x: 280, y: 518, diameter: 42),
            LensLayout(x: 848, y: 531, diameter: 68),
            LensLayout(x: 958, y: 533, diameter: 62)
        ]
    }

    private var headlightGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .white,
                        Color(red: 0.82, green: 0.94, blue: 1.0).opacity(0.96),
                        Color(red: 0.53, green: 0.81, blue: 1.0).opacity(0.38),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 11
                )
            )
            .overlay(Circle().fill(.white.opacity(0.76)).scaleEffect(0.34))
            .shadow(color: .white.opacity(0.85), radius: 2)
            .shadow(color: .cyan.opacity(0.28), radius: 3.5)
    }

    private func fittedCarImageRect(in canvasSize: CGSize) -> CGRect {
        let width = min(canvasSize.width + 18, 430)
        let height = width * carSourceSize.height / carSourceSize.width
        return CGRect(
            x: (canvasSize.width - width) / 2,
            y: (canvasSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func sourcePoint(x: CGFloat, y: CGFloat, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + (x / carSourceSize.width) * imageRect.width,
            y: imageRect.minY + (y / carSourceSize.height) * imageRect.height
        )
    }


    private var groundGlow: some View {
        Ellipse()
            .fill(.cyan.opacity(state.simulatedEngineRunning ? 0.18 : 0.07))
            .frame(width: 228, height: 318)
            .blur(radius: 30)
    }

    private var journeyBody: some View {
        ZStack {
            JourneyBodyShape()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(white: 0.82), Color(white: 0.98), Color(white: 0.64)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 168, height: 306)
                .overlay(JourneyBodyShape().stroke(.white.opacity(0.82), lineWidth: 1.4))
                .shadow(color: .black.opacity(0.75), radius: 15, y: 12)
                .shadow(color: .cyan.opacity(state.simulatedEngineRunning ? 0.28 : 0.08), radius: 25)

            VStack(spacing: 9) {
                frontDetails
                frontGlass
                roof
                rearGlass
                rearDetails
            }
            .frame(height: 285)

            roofRails

            RoundedRectangle(cornerRadius: 3)
                .fill(state.simulatedEngineRunning ? .green : .black.opacity(0.22))
                .frame(width: 36, height: 4)
                .offset(y: 22)
                .shadow(color: state.simulatedEngineRunning ? .green : .clear, radius: 8)
        }
    }

    private var frontDetails: some View {
        VStack(spacing: 3) {
            Text("DODGE")
                .font(.system(size: 5, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.black.opacity(0.62))
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(.black.opacity(0.60)).frame(width: 18, height: 2)
                }
            }
        }
        .frame(height: 23)
    }

    private var frontGlass: some View {
        RoundedRectangle(cornerRadius: 18)
        .fill(glassGradient)
        .frame(width: 116, height: 55)
        .overlay(
            LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .topLeading, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 15))
        )
    }

    private var roof: some View {
        RoundedRectangle(cornerRadius: 21)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.94), Color(white: 0.76), .white],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 119, height: 94)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.77))
                    .frame(width: 84, height: 62)
                    .overlay(
                        LinearGradient(colors: [.cyan.opacity(0.20), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    )
            )
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(.black.opacity(0.10)))
    }

    private var rearGlass: some View {
        RoundedRectangle(cornerRadius: 15)
        .fill(glassGradient)
        .frame(width: 111, height: 43)
    }

    private var rearDetails: some View {
        VStack(spacing: 2) {
            Text("JOURNEY")
                .font(.system(size: 5, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.black.opacity(0.58))
            RoundedRectangle(cornerRadius: 2)
                .fill(.black.opacity(0.72))
                .frame(width: 42, height: 10)
                .overlay(Text("27A 77884").font(.system(size: 4, weight: .bold)).foregroundStyle(.white.opacity(0.75)))
        }
        .frame(height: 24)
    }

    private var glassGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.27, green: 0.40, blue: 0.46), .black.opacity(0.94)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var roofRails: some View {
        HStack(spacing: 119) {
            Capsule().fill(.black.opacity(0.58)).frame(width: 5, height: 151)
            Capsule().fill(.black.opacity(0.58)).frame(width: 5, height: 151)
        }
        .offset(y: 4)
    }

    private var wheels: some View {
        VStack(spacing: 170) {
            wheelPair
            wheelPair
        }
    }

    private var wheelPair: some View {
        HStack(spacing: 146) {
            wheel
            wheel
        }
    }

    private var wheel: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.black)
            .frame(width: 18, height: 54)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.12)))
    }

    private var doors: some View {
        ZStack {
            journeyDoor(front: true, left: true)
                .rotationEffect(.degrees(state.simulatedDoorsOpen ? -33 : 0), anchor: .trailing)
                .offset(x: state.simulatedDoorsOpen ? -92 : -68, y: -42)
            journeyDoor(front: true, left: false)
                .rotationEffect(.degrees(state.simulatedDoorsOpen ? 33 : 0), anchor: .leading)
                .offset(x: state.simulatedDoorsOpen ? 92 : 68, y: -42)
            journeyDoor(front: false, left: true)
                .rotationEffect(.degrees(state.simulatedDoorsOpen ? -31 : 0), anchor: .trailing)
                .offset(x: state.simulatedDoorsOpen ? -91 : -68, y: 51)
            journeyDoor(front: false, left: false)
                .rotationEffect(.degrees(state.simulatedDoorsOpen ? 31 : 0), anchor: .leading)
                .offset(x: state.simulatedDoorsOpen ? 91 : 68, y: 51)
        }
    }

    private func journeyDoor(front: Bool, left: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(LinearGradient(colors: [.white, Color(white: 0.69)], startPoint: .top, endPoint: .bottom))
            .frame(width: 48, height: front ? 78 : 73)
            .overlay(
                Capsule()
                    .fill(.black.opacity(0.50))
                    .frame(width: 13, height: 2)
                    .offset(x: left ? 10 : -10, y: -24)
            )
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.65)))
            .shadow(color: state.simulatedDoorsOpen ? .cyan.opacity(0.24) : .clear, radius: 12)
    }

    private var lamps: some View {
        VStack(spacing: 254) {
            HStack(spacing: 76) {
                lamp(color: state.leftSignalOn ? .orange : (state.headlightsOn ? .white : .gray), flashing: state.leftSignalOn)
                lamp(color: state.rightSignalOn ? .orange : (state.headlightsOn ? .white : .gray), flashing: state.rightSignalOn)
            }
            HStack(spacing: 79) {
                lamp(color: state.leftSignalOn ? .orange : .red.opacity(0.78), flashing: state.leftSignalOn)
                lamp(color: state.rightSignalOn ? .orange : .red.opacity(0.78), flashing: state.rightSignalOn)
            }
        }
    }

    private func lamp(color: Color, flashing: Bool) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 31, height: 8)
            .opacity(flashing ? (pulse ? 1 : 0.18) : (state.headlightsOn ? 1 : 0.52))
            .shadow(color: color, radius: flashing || state.headlightsOn ? 13 : 0)
    }

    private var headlightBeams: some View {
        HStack(spacing: 46) {
            beam
            beam
        }
            .offset(y: -202)
            .blur(radius: 5)
    }

    private var beam: some View {
        LinearGradient(colors: [.white.opacity(0.02), .yellow.opacity(0.40)], startPoint: .bottom, endPoint: .top)
            .frame(width: 66, height: 105)
            .clipShape(Triangle())
    }

    private var hornWaves: some View {
        HStack(spacing: 205) {
            Image(systemName: "wave.3.left").font(.title).foregroundStyle(.cyan)
            Image(systemName: "wave.3.right").font(.title).foregroundStyle(.cyan)
        }
        .scaleEffect(pulse ? 1.16 : 0.86)
        .opacity(pulse ? 1 : 0.42)
    }
}

private struct SignalStripLayout {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
}

private struct LensLayout {
    let x: CGFloat
    let y: CGFloat
    let diameter: CGFloat
}

/// Curved row of individual amber LEDs matching the lower edge of the
/// aftermarket Journey headlamp instead of drawing a generic orange blob.
private struct JourneyTurnSignalStrip: View {
    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: 1, y: size.height * 0.24)
            let control = CGPoint(x: size.width * 0.52, y: size.height * 0.82)
            let end = CGPoint(x: size.width - 1, y: size.height * 0.60)

            var rail = Path()
            rail.move(to: start)
            rail.addQuadCurve(to: end, control: control)
            context.stroke(
                rail,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.34, blue: 0.0),
                        Color(red: 1.0, green: 0.73, blue: 0.04),
                        Color(red: 1.0, green: 0.31, blue: 0.0)
                    ]),
                    startPoint: start,
                    endPoint: end
                ),
                style: StrokeStyle(lineWidth: max(2.2, size.height * 0.42), lineCap: .round)
            )

            // Bright LED points sitting on the same quadratic curve.
            for index in 0..<12 {
                let t = CGFloat(index) / 11
                let oneMinusT = 1 - t
                let x = oneMinusT * oneMinusT * start.x
                    + 2 * oneMinusT * t * control.x
                    + t * t * end.x
                let y = oneMinusT * oneMinusT * start.y
                    + 2 * oneMinusT * t * control.y
                    + t * t * end.y
                let diameter = max(1.6, size.height * 0.26)
                let dot = CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                 width: diameter, height: diameter)
                context.fill(Path(ellipseIn: dot), with: .color(.yellow))
            }
        }
    }
}

/// Trapezoid matching the swept-back front lamp housing of the Journey.
private struct JourneyHeadlampShape: Shape {
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = mirrored
            ? [
                CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.20),
                CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.82),
                CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.maxY)
            ]
            : [
                CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.20),
                CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.82),
                CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY)
            ]

        return Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
    }
}

/// Narrow amber segment at the outside edge of each Journey headlamp.
private struct JourneySignalShape: Shape {
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.18
        return Path { path in
            if mirrored {
                path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.13))
                path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12))
            } else {
                path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.13))
                path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.12))
            }
            path.closeSubpath()
        }
    }
}

private struct JourneyBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX - 42, y: rect.minY + 4))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 10, y: rect.minY + 50), control: CGPoint(x: rect.minX + 17, y: rect.minY + 13))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: rect.midY), control: CGPoint(x: rect.minX, y: rect.minY + 92))
            path.addLine(to: CGPoint(x: rect.minX + 5, y: rect.maxY - 48))
            path.addQuadCurve(to: CGPoint(x: rect.midX - 37, y: rect.maxY - 3), control: CGPoint(x: rect.minX + 17, y: rect.maxY - 12))
            path.addQuadCurve(to: CGPoint(x: rect.midX + 37, y: rect.maxY - 3), control: CGPoint(x: rect.midX, y: rect.maxY + 5))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 48), control: CGPoint(x: rect.maxX - 17, y: rect.maxY - 12))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 50), control: CGPoint(x: rect.maxX, y: rect.minY + 92))
            path.addQuadCurve(to: CGPoint(x: rect.midX + 42, y: rect.minY + 4), control: CGPoint(x: rect.maxX - 17, y: rect.minY + 13))
            path.addQuadCurve(to: CGPoint(x: rect.midX - 42, y: rect.minY + 4), control: CGPoint(x: rect.midX, y: rect.minY - 4))
            path.closeSubpath()
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}
