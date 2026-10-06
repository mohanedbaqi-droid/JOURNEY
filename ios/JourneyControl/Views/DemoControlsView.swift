import SwiftUI

struct DemoControlsView: View {
    @EnvironmentObject private var mqtt: MQTTService
    let deviceID: String
    let state: VehicleState
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        if mqtt.demoMode {
            VStack(alignment: .leading, spacing: 12) {
                Label("JOURNEY DEMO", systemImage: "car.side.fill")
                    .font(.headline).foregroundStyle(.cyan)
                Text(JL("محاكاة محلية • البيبان والأضواء مستقلة، والسيارة ثابتة بالسنتر.", "Local simulation • Independent doors and lights, fixed vehicle center."))
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 8) {
                    control(JL("باب السائق", "Driver door"), item: "driverFront", active: state.demoDriverFrontOpen)
                    control(JL("باب الراكب", "Passenger door"), item: "passengerFront", active: state.demoPassengerFrontOpen)
                    control(JL("خلف السائق", "Driver rear"), item: "driverRear", active: state.demoDriverRearOpen)
                    control(JL("خلف الراكب", "Passenger rear"), item: "passengerRear", active: state.demoPassengerRearOpen)
                    control(JL("الصندوق", "Liftgate"), item: "liftgate", active: state.demoLiftgateOpen)
                    control(JL("البنيد", "Hood"), item: "hood", active: state.demoHoodOpen)
                    control(JL("كل البيبان", "All doors"), item: "allDoors", active: state.demoDriverFrontOpen && state.demoPassengerFrontOpen && state.demoDriverRearOpen && state.demoPassengerRearOpen)
                    control(JL("النهاري", "DRL"), item: "drl", active: state.demoDRLOn)
                    control(JL("السكن / البروجكتر", "Parking / projectors"), item: "projectors", active: state.demoProjectorsOn)
                    control(JL("الايت الناصي", "Low beam"), item: "headlights", active: state.headlightsOn)
                    control(JL("إشارة السائق", "Driver turn signal"), item: "leftSignal", active: state.leftSignalOn)
                    control(JL("إشارة الراكب", "Passenger turn signal"), item: "rightSignal", active: state.rightSignalOn)
                    control(JL("فلشر", "Hazard"), item: "hazard", active: state.leftSignalOn && state.rightSignalOn)
                }
                Button(JL("إعادة ضبط الديمو", "Reset demo")) { mqtt.demoToggle("reset", for: deviceID) }
                    .buttonStyle(.bordered)
            }
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func control(_ title: String, item: String, active: Bool) -> some View {
        Button { mqtt.demoToggle(item, for: deviceID) } label: {
            HStack {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(active ? Color.green : Color.cyan)
            .background((active ? Color.green : Color.cyan).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityValue(active ? JL("مفعّل", "On") : JL("مطفي", "Off"))
    }
}

struct DemoOpenStateBadges: View {
    let state: VehicleState
    private var labels: [String] {
        var result: [String] = []
        if state.demoDriverFrontOpen { result.append(JL("سائق", "Driver")) }
        if state.demoPassengerFrontOpen { result.append(JL("راكب", "Passenger")) }
        if state.demoDriverRearOpen { result.append(JL("خلف سائق", "Driver rear")) }
        if state.demoPassengerRearOpen { result.append(JL("خلف راكب", "Passenger rear")) }
        if state.demoLiftgateOpen { result.append(JL("صندوق", "Liftgate")) }
        if state.demoHoodOpen { result.append(JL("بنيد", "Hood")) }
        return result
    }
    var body: some View {
        VStack {
            Spacer()
            if !labels.isEmpty {
                Text(labels.joined(separator: " • "))
                    .font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.bottom, 12)
    }
}
