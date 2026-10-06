import SwiftUI

/// Original angled JOURNEY artwork and light overlays, retained from the final main version.
/// Only the driver-front demo control selects its existing open-door artwork.
struct JourneyAngledCarView: View {
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

                // The chassis never switches artwork. Only the door region
                // uses the open image, registered to the closed A-pillar.
                Image("JourneyLEDClosed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(proxy.size.width + 18, 430))
                    .shadow(color: .black.opacity(0.72), radius: 18, y: 12)

                openDriverDoor(in: proxy.size)
                    .opacity(state.demoDriverFrontOpen ? 1 : 0)
                    .allowsHitTesting(false)

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
        // Artwork coordinates describe the physical car, independent of UI language.
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .animation(.easeInOut(duration: 0.18), value: state.demoDriverFrontOpen)
        .animation(.easeInOut(duration: 0.25), value: state.headlightsOn)
        .animation(.easeInOut(duration: 0.18), value: state.leftSignalOn)
        .animation(.easeInOut(duration: 0.18), value: state.rightSignalOn)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.48).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JL("جورني بزاوية جانبية، باب السايق والأضواء", "Angled Journey, driver door and lights"))
        .accessibilityValue(state.simulatedLocked ? JL("مقفلة", "Locked") : JL("مفتوحة", "Unlocked"))
    }

    private func openDriverDoor(in canvasSize: CGSize) -> some View {
        let rect = fittedCarImageRect(in: canvasSize)
        let scale = rect.width / carSourceSize.width
        return Image("JourneyLEDOpen")
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .clipShape(RegisteredDriverDoorRegion())
            .offset(x: 20 * scale, y: 18 * scale)
            .frame(width: canvasSize.width, height: canvasSize.height)
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
        return (
            // Screen-left lamp (the side opposite the open passenger door):
            // its amber bar sits *below* the round lenses and slopes only
            // gently with the lamp's lower edge.
            SignalStripLayout(x: 215, y: 576, width: 130, height: 20, rotation: 9.0),
            // Screen-right lamp: the inner end (nearest the grille) sits a
            // little lower while the outer end stays on the lamp edge.
            SignalStripLayout(x: 922, y: 594, width: 248, height: 21, rotation: -3.5)
        )
    }

    /// Reference lamp geometry: only the round white centres inside the U
    /// trim illuminate.  The U itself is purely cosmetic in this UI.
    private var lensLayouts: [LensLayout] {
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

/// Native source coordinates covering only the open door and cabin opening.
/// The bumper, grille, lamps, bonnet, roof and wheels remain the closed base.
private struct RegisteredDriverDoorRegion: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 1155, y: 127), CGPoint(x: 1217, y: 128),
            CGPoint(x: 1266, y: 160), CGPoint(x: 1300, y: 117),
            CGPoint(x: 1418, y: 104), CGPoint(x: 1455, y: 205),
            CGPoint(x: 1475, y: 340), CGPoint(x: 1484, y: 650),
            CGPoint(x: 1200, y: 729), CGPoint(x: 1172, y: 393)
        ]
        return Path { path in
            for (index, point) in points.enumerated() {
                let p = CGPoint(x: rect.minX + point.x / 1536 * rect.width,
                                y: rect.minY + point.y / 1024 * rect.height)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}
