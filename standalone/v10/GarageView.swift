import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @State private var showAddVehicle = false
    @State private var pendingDelete: GarageVehicle?
    @State private var documentsVehicle: GarageVehicle?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pdt("garage"))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text(String(garage.vehicles.count) + " " + pdt("vehicles"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showAddVehicle = true } label: {
                            Label(pdt("add_car"), systemImage: "plus")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .background(.cyan, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }

                    if garage.vehicles.isEmpty {
                        emptyState
                    } else {
                        ForEach(garage.vehicles) { vehicle in
                            vehicleCard(vehicle)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddVehicle) { VehiclePickerView(title: pdt("add_car")) }
            .sheet(item: $documentsVehicle) { vehicle in
                NavigationStack {
                    CustomerDocumentsView(vehicle: vehicle)
                        .environmentObject(garage)
                }
            }
            .confirmationDialog(
                "حذف السيارة من الكراج؟",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("حذف", role: .destructive) {
                    if let pendingDelete { garage.remove(pendingDelete) }
                    pendingDelete = nil
                }
                Button("إلغاء", role: .cancel) { pendingDelete = nil }
            }
        }
    }

    private func vehicleCard(_ vehicle: GarageVehicle) -> some View {
        let active = garage.activeVehicleID == vehicle.id
        let profile = vehicle.profile

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [.red.opacity(0.06), .cyan.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 138, height: 102)

                    if let profile {
                        VehicleAssetImage(
                            profile: profile,
                            colorHex: vehicle.vehicleColorHex,
                            maxHeight: 96,
                            plateText: vehicle.vehiclePlateText,
                    plateShiftX: vehicle.vehiclePlateShiftX,
                    plateShiftY: vehicle.vehiclePlateShiftY,
                    plateScale: vehicle.vehiclePlateScale,
                    plateAngleOffset: vehicle.vehiclePlateAngleOffset
                        )
                        .frame(width: 132, height: 98)
                    } else {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(active ? .cyan : .white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(vehicle.displayName).font(.headline).lineLimit(1)
                        if active {
                            Text(pdt("active"))
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.green.opacity(0.12), in: Capsule())
                        }
                    }
                    if let profile {
                        Text("\(profile.make) \(profile.model) • \(String(vehicle.year))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: vehicle.vehicleColorHex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(0.25)))
                        Text(vehicle.vehiclePlateText.isEmpty ? "—" : vehicle.vehiclePlateText)
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(1)
                    }

                    Label(
                        vehicle.hasESP ? vehicle.espLabel : "ESP • " + pdt("not_linked"),
                        systemImage: vehicle.hasESP ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(vehicle.hasESP ? Color.green : Color.orange)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Button {
                documentsVehicle = vehicle
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle.fill")
                    Text(pd("معلومات الزبون والمستمسكات", "Customer & documents", "زانیاری و بەڵگەکانی کڕیار", "Müşteri ve belgeler", "مشتری و مدارک"))
                    Spacer()
                    let count = (vehicle.hasAnnualCardDocument ? 1 : 0) + (vehicle.hasUnifiedIDDocument ? 1 : 0)
                    Text("\(count)/2")
                        .font(.caption2.bold())
                        .foregroundStyle(count == 2 ? .green : .cyan)
                }
                .font(.caption.bold())
                .foregroundStyle(.cyan)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.cyan.opacity(0.18)))
            }
            .buttonStyle(.plain)

            Divider().overlay(.white.opacity(0.08))

            HStack(spacing: 9) {
                if !active {
                    Button { garage.setActive(vehicle) } label: {
                        Label(pdt("make_active"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GarageActionStyle(tint: .cyan))
                }

                NavigationLink {
                    VehicleAppearanceView(vehicle: vehicle)
                } label: {
                    Label(pdt("vehicle_color_plate"), systemImage: "paintpalette.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GarageActionStyle(tint: .cyan))

                NavigationLink {
                    ESPBindingView(vehicle: vehicle)
                } label: {
                    Label(vehicle.hasESP ? "ESP" : "ربط ESP", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GarageActionStyle(tint: vehicle.hasESP ? .green : .orange))

                Button { pendingDelete = vehicle } label: {
                    Image(systemName: "trash").frame(width: 44)
                }
                .buttonStyle(GarageActionStyle(tint: .red))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [.white.opacity(active ? 0.09 : 0.06), .white.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke((active ? Color.cyan : Color.white).opacity(active ? 0.30 : 0.07), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.2.fill")
                .font(.system(size: 52))
                .foregroundStyle(.cyan)
            Text(pdt("garage_empty")).font(.title3.bold())
            Text("أضف أول سيارة حتى ينشئ Punisher Drive بروفايل مستقل إلها.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showAddVehicle = true } label: {
                Label(pdt("add_car"), systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.cyan, in: RoundedRectangle(cornerRadius: 15))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07)))
    }
}

private struct GarageActionStyle: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.vertical, 10)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(tint.opacity(0.22)))
    }
}
