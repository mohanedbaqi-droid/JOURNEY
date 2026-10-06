import SwiftUI

private enum JourneyCarAppearance: String, CaseIterable, Identifiable {
    case front, angled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .front: return JL("أمامي — بيبان وأضواء متحركة", "Front — animated doors and lights")
        case .angled: return JL("زاوية جانبية — صورة ثابتة", "Angled — still photo")
        }
    }
    var asset: String { self == .front ? "JourneyLayerBody" : "JourneyAngledPhoto" }
}

struct JourneySelectedCarView: View {
    let state: VehicleState
    @AppStorage("journey.settings.carAppearance") private var selection = "front"

    var body: some View {
        if JourneyCarAppearance(rawValue: selection) == .angled {
            Image("JourneyAngledPhoto")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { DemoOpenStateBadges(state: state).allowsHitTesting(false) }
                .accessibilityLabel(JL("جورني بزاوية جانبية، صورة ثابتة", "Journey angled view, still photo"))
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
            Text(JL("الاختيار ينحفظ تلقائياً. الصورة الجانبية ثابتة؛ اختر الأمامي لمشاهدة حركة البيبان والأضواء.", "Your choice is saved automatically. The angled photo is static; choose Front to view animated doors and lights."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label(JL("شكل السيارة", "Car appearance"), systemImage: "car.fill")
        }
    }
}
