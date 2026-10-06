import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var garage: VehicleProfileStore
    @State private var showAddVehicle = false
    @State private var pendingDelete: GarageVehicle?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("الكراج")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("\(garage.vehicles.count) سيارة")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showAddVehicle = true } label: {
                            Label("إضافة", systemImage: "plus")
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
            .sheet(isPresented: $showAddVehicle) { VehiclePickerView(title: "إضافة سيارة") }
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
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.white.opacity(0.055))
                        .frame(width: 86, height: 70)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(active ? .cyan : .white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(vehicle.displayName).font(.headline).lineLimit(1)
                        if active {
                            Text("نشطة")
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
                    Label(
                        vehicle.hasESP ? vehicle.espLabel : "ESP غير مربوط",
                        systemImage: vehicle.hasESP ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(vehicle.hasESP ? Color.green : Color.orange)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(.white.opacity(0.08))

            HStack(spacing: 9) {
                if !active {
                    Button { garage.setActive(vehicle) } label: {
                        Label("اعتماد", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GarageActionStyle(tint: .cyan))
                }

                NavigationLink {
                    ESPBindingView(vehicle: vehicle)
                } label: {
                    Label(vehicle.hasESP ? "إدارة ESP" : "ربط ESP", systemImage: "link")
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
            Text("الكراج فارغ").font(.title3.bold())
            Text("أضف أول سيارة حتى ينشئ Punisher Drive بروفايل مستقل إلها.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showAddVehicle = true } label: {
                Label("إضافة سيارة", systemImage: "plus.circle.fill")
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
