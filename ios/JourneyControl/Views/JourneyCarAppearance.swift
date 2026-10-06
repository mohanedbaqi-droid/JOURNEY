import SwiftUI

private enum JourneyCarAppearance: String, CaseIterable, Identifiable {
    case front, angled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .front: return JL("أمامي — بيبان وأضواء متحركة", "Front — animated doors and lights")
        case .angled: return JL("زاوية جانبية — باب السايق والأضواء", "Angled — driver door and lights")
        }
    }
    var asset: String { self == .front ? "JourneyLayerBody" : "JourneyLEDClosed" }
}

struct JourneySelectedCarView: View {
    let state: VehicleState
    @AppStorage("journey.settings.carAppearance") private var selection = "front"

    var body: some View {
        if JourneyCarAppearance(rawValue: selection) == .angled {
            JourneyAngledCarView(state: state)
        } else {
            CarVisualView(state: state)
        }
    }
}

struct JourneyCarAppearanceSettingsSection: View {
    @AppStorage("journey.settings.carAppearance") private var selection = "front"
    private var appearance: JourneyCarAppearance {
        JourneyCarAppearance(rawValue: selection) ?? .front
    }

    var body: some View {
        Section {
            Picker(JL("نموذج السيارة", "Car appearance"), selection: $selection) {
                ForEach(JourneyCarAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            Image(appearance.asset)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(appearance.title)
            Text(JL("الاختيار ينحفظ تلقائياً. النموذج الجانبي يعرض باب السايق والأضواء؛ النموذج الأمامي يعرض كل البيبان والصندوق.", "Your choice is saved automatically. The angled model shows the driver door and lights; the front model shows all doors and the liftgate."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label(JL("شكل السيارة", "Car appearance"), systemImage: "car.fill")
        }
    }
}
