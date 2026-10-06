import SwiftUI

/// Every layer shares the approved 1920 × 1200 canvas, including closed states.
/// Fit the full envelope once; a door or light can never recenter the vehicle.
struct CarVisualView: View {
    let state: VehicleState
    private let sourceSize = CGSize(width: 1920, height: 1200)

    var body: some View {
        GeometryReader { proxy in
            // Reserve the same complete door/hatch envelope in every state.
            let scale = (proxy.size.width - 8) / 1794
            let carWidth = sourceSize.width * scale
            let carHeight = sourceSize.height * scale
            ZStack {
                layer("Liftgate", visible: state.demoLiftgateOpen)
                layer("DriverRearDoor", visible: state.demoDriverRearOpen)
                layer("PassengerRearDoor", visible: state.demoPassengerRearOpen)
                layer("Body")
                layer("DriverMirror", visible: !state.demoDriverFrontOpen)
                layer("PassengerMirror", visible: !state.demoPassengerFrontOpen)
                layer("DriverDoor", visible: state.demoDriverFrontOpen)
                layer("PassengerDoor", visible: state.demoPassengerFrontOpen)
                layer("RedDRL", visible: state.demoDRLOn && !state.headlightsOn)
                layer("LowBeam", visible: state.headlightsOn)
                layer("Projectors", visible: state.demoProjectorsOn)
                layer("PassengerDRL", visible: state.demoDRLOn && !state.rightSignalOn)
                layer("DriverDRL", visible: state.demoDRLOn && !state.leftSignalOn)
                if state.leftSignalOn || state.rightSignalOn {
                    TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                        ledLights(date: timeline.date)
                    }
                }
            }
            .frame(width: carWidth, height: carHeight)
            .position(x: proxy.size.width / 2, y: carHeight / 2 - 46 * scale)
            DemoOpenStateBadges(state: state).allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1794.0 / 1165.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JL("جورني، طبقات الأبواب والأضواء", "Journey, door and light layers"))
    }

    private func layer(_ suffix: String, visible: Bool = true) -> some View {
        Image("JourneyLayer" + suffix)
            .resizable()
            .aspectRatio(sourceSize, contentMode: .fit)
            .opacity(visible ? 1 : 0)
    }

    private func ledLights(date: Date) -> some View {
        Canvas { context, size in
            let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.15)
            let count = phase < 0.72 ? min(18, Int(phase / 0.72 * 18) + 1) : (phase < 0.9 ? 18 : 0)
            // Vehicle left/driver = picture RIGHT. Both signals share one clock.
            for side in 0..<2 {
                let signal = side == 0 ? state.rightSignalOn : state.leftSignalOn
                let points = side == 0 ? passengerLEDs : driverLEDs
                for (index, point) in points.enumerated() {
                    guard signal && index < count else { continue }
                    let x = (point.x * 1335 / 800 * 0.932 + 347) * size.width / sourceSize.width
                    let y = (point.y * 1178 / 706 * 0.894 + 114) * size.height / sourceSize.height
                    let radius = 8.7 * size.width / sourceSize.width
                    let rect = CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)
                    let colors: [Color] = signal
                        ? [Color(red: 1, green: 0.68, blue: 0.07), Color(red: 1, green: 0.6, blue: 0.02)]
                        : [.white, Color(red: 0.86, green: 0.91, blue: 1)]
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: colors), center: CGPoint(x: x,y: y), startRadius: 0, endRadius: radius))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // Fixed LED centres: grille-side end outward, then up the outer edge.
    private let passengerLEDs: [CGPoint] = [
        CGPoint(x:178,y:470),CGPoint(x:166,y:467),CGPoint(x:154,y:465),CGPoint(x:142,y:462),CGPoint(x:130,y:459),CGPoint(x:118,y:457),CGPoint(x:105,y:449),CGPoint(x:94,y:446),CGPoint(x:82,y:443),CGPoint(x:70,y:440),CGPoint(x:59,y:437),CGPoint(x:48,y:430),CGPoint(x:46,y:422),CGPoint(x:46,y:413),CGPoint(x:46,y:404),CGPoint(x:47,y:395),CGPoint(x:48,y:386),CGPoint(x:49,y:376)
    ]
    private let driverLEDs: [CGPoint] = [
        CGPoint(x:613,y:470),CGPoint(x:625,y:468),CGPoint(x:638,y:465),CGPoint(x:650,y:462),CGPoint(x:662,y:460),CGPoint(x:674,y:457),CGPoint(x:686,y:450),CGPoint(x:698,y:447),CGPoint(x:710,y:444),CGPoint(x:722,y:441),CGPoint(x:733,y:437),CGPoint(x:742,y:430),CGPoint(x:743,y:422),CGPoint(x:743,y:413),CGPoint(x:743,y:404),CGPoint(x:742,y:395),CGPoint(x:741,y:386),CGPoint(x:740,y:376)
    ]
}
