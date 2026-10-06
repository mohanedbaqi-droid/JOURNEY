import SwiftUI

struct PunisherVehicleChoice: Identifiable, Hashable {
    let id: String
    let make: String
    let model: String
    let year: Int

    var title: String { "\(make) \(model) \(year)" }
}

private enum PunisherVehicleCatalog {
    static let vehicles: [PunisherVehicleChoice] = [
        .init(id: "dodge_journey_2017", make: "Dodge", model: "Journey", year: 2017),
        .init(id: "toyota_camry_2024", make: "Toyota", model: "Camry", year: 2024),
        .init(id: "toyota_land_cruiser_2024", make: "Toyota", model: "Land Cruiser", year: 2024)
    ]

    static var makes: [String] { Array(Set(vehicles.map(\.make))).sorted() }
    static func models(for make: String) -> [String] {
        Array(Set(vehicles.filter { $0.make == make }.map(\.model))).sorted()
    }
    static func years(for make: String, model: String) -> [Int] {
        vehicles.filter { $0.make == make && $0.model == model }.map(\.year).sorted(by: >)
    }
    static func resolve(make: String, model: String, year: Int) -> PunisherVehicleChoice? {
        vehicles.first { $0.make == make && $0.model == model && $0.year == year }
    }
}

struct PunisherVehicleGate<Content: View>: View {
    @AppStorage("punisher.vehicle.profileID") private var profileID = ""
    @AppStorage("punisher.vehicle.make") private var savedMake = ""
    @AppStorage("punisher.vehicle.model") private var savedModel = ""
    @AppStorage("punisher.vehicle.year") private var savedYear = 0

    @State private var showingSelector = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if profileID.isEmpty {
                selector
            } else {
                content
                Button {
                    showingSelector = true
                } label: {
                    Image(systemName: "car.badge.gearshape")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.cyan)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.82), in: Circle())
                        .overlay(Circle().stroke(.cyan.opacity(0.45), lineWidth: 1))
                }
                .padding(.top, 54)
                .padding(.trailing, 14)
                .accessibilityLabel("تغيير نوع السيارة")
            }
        }
        .sheet(isPresented: $showingSelector) {
            selector
        }
    }

    private var selector: some View {
        PunisherVehicleSelector(
            initialMake: savedMake,
            initialModel: savedModel,
            initialYear: savedYear
        ) { vehicle in
            profileID = vehicle.id
            savedMake = vehicle.make
            savedModel = vehicle.model
            savedYear = vehicle.year
            showingSelector = false
        }
    }
}

private struct PunisherVehicleSelector: View {
    @State private var make: String
    @State private var model: String
    @State private var year: Int
    let onSave: (PunisherVehicleChoice) -> Void

    init(initialMake: String, initialModel: String, initialYear: Int, onSave: @escaping (PunisherVehicleChoice) -> Void) {
        _make = State(initialValue: initialMake)
        _model = State(initialValue: initialModel)
        _year = State(initialValue: initialYear)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 34)
                        Image(systemName: "car.side.front.open")
                            .font(.system(size: 68, weight: .semibold))
                            .foregroundStyle(.cyan)
                        Text("PUNISHER DRIVE")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .tracking(2)
                        Text("اختيار نوع السيارة")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("اختَر ماركة الصنع والموديل وسنة الصنع حتى يتم تحديد بروفايل السيارة والإمكانيات المتاحة لها.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.horizontal)

                        VStack(spacing: 14) {
                            vehiclePicker(title: "ماركة الصنع", selection: $make, values: PunisherVehicleCatalog.makes)
                                .onChange(of: make) { _, _ in normalizeModelAndYear() }
                            vehiclePicker(title: "الموديل", selection: $model, values: PunisherVehicleCatalog.models(for: make))
                                .disabled(make.isEmpty)
                                .onChange(of: model) { _, _ in normalizeYear() }

                            Picker("سنة الصنع", selection: $year) {
                                Text("اختيار السنة").tag(0)
                                ForEach(PunisherVehicleCatalog.years(for: make, model: model), id: \.self) { value in
                                    Text(String(value)).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.cyan)
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .padding(.horizontal, 16)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                            .disabled(model.isEmpty)

                            Button {
                                if let vehicle = PunisherVehicleCatalog.resolve(make: make, model: model, year: year) {
                                    onSave(vehicle)
                                }
                            } label: {
                                Text("اعتماد نوع السيارة")
                                    .font(.headline.bold())
                                    .frame(maxWidth: .infinity, minHeight: 54)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(PunisherVehicleCatalog.resolve(make: make, model: model, year: year) == nil)
                        }
                        .padding(18)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.cyan.opacity(0.22), lineWidth: 1))
                    }
                    .padding(20)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func vehiclePicker(title: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) {
            Text(title).tag("")
            ForEach(values, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .tint(.cyan)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func normalizeModelAndYear() {
        let models = PunisherVehicleCatalog.models(for: make)
        if !models.contains(model) { model = models.first ?? "" }
        normalizeYear()
    }

    private func normalizeYear() {
        let years = PunisherVehicleCatalog.years(for: make, model: model)
        if !years.contains(year) { year = years.first ?? 0 }
    }
}
