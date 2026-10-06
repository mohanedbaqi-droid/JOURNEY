import SwiftUI

struct VehicleOpenStateBadges: View {
    let state: VehicleState
    private var labels: [String] {
        var result: [String] = []
        for (bit, label) in [(0x02, JL("السائق", "Driver")), (0x04, JL("الراكب", "Passenger")), (0x10, JL("خلف الراكب", "Passenger rear")), (0x40, JL("الصندوق", "Liftgate"))] {
            result.append(label + ": " + (state.doorIsKnown(bit) ? (state.doorIsOpen(bit) ? JL("مفتوح", "Open") : JL("مغلق", "Closed")) : JL("غير متاح", "Unavailable")))
        }
        result.append(JL("خلف السائق: غير متاح", "Driver rear: unavailable"))
        return result
    }
    var body: some View {
        VStack {
            Spacer()
            Text(labels.joined(separator: " • "))
                .font(.caption2.weight(.semibold)).foregroundStyle(JourneyTheme.accent)
                .multilineTextAlignment(.center).padding(8)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        }.padding(.bottom, 12)
    }
}
