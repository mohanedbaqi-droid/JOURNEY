import SwiftUI
import MapKit

struct FleetMapView: View {
    @EnvironmentObject private var garage: VehicleProfileStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedVehicleID: UUID?

    private var locatedVehicles: [GarageVehicle] {
        garage.vehicles.filter { $0.hasGPSFix }
    }

    private var selectedVehicle: GarageVehicle? {
        guard let selectedVehicleID else { return nil }
        return garage.vehicles.first { $0.id == selectedVehicleID }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(locatedVehicles) { vehicle in
                    if let latitude = vehicle.latitude, let longitude = vehicle.longitude {
                        Annotation(vehicle.displayName, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedVehicleID = vehicle.id
                                }
                            } label: {
                                FleetVehiclePin(
                                    vehicle: vehicle,
                                    active: garage.activeVehicleID == vehicle.id,
                                    selected: selectedVehicleID == vehicle.id
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(vehicle.displayName)، \(Int(vehicle.currentSpeedKmh.rounded())) كيلومتر بالساعة")
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .top) {
                fleetHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }

            if locatedVehicles.isEmpty {
                emptyGPSState
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
            } else if let selectedVehicle {
                vehicleInfoCard(selectedVehicle)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: garage.vehicles) { _, vehicles in
            if let selectedVehicleID, !vehicles.contains(where: { $0.id == selectedVehicleID }) {
                self.selectedVehicleID = nil
            }
        }
    }

    private var fleetHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "map.fill")
                .foregroundStyle(.cyan)

            VStack(alignment: .leading, spacing: 1) {
                Text(pdt("fleet_map"))
                    .font(.subheadline.bold())
                Text("\(locatedVehicles.count) من \(garage.vehicles.count) سيارة عندها موقع")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !locatedVehicles.isEmpty {
                Button {
                    selectedVehicleID = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        cameraPosition = .automatic
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.72), in: Circle())
                        .overlay(Circle().stroke(.cyan.opacity(0.30)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(colors: [.red.opacity(0.28), .cyan.opacity(0.28)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
        )
    }

    private var emptyGPSState: some View {
        VStack(spacing: 10) {
            PunisherBrandMark(size: 70)
            Text(pdt("waiting_gps"))
                .font(.headline)
            Text("كل سيارة مرتبطة بجهاز ESP مستقل. أول ما يوصل موقعها الحقيقي راح تظهر هنا بدون أي مواقع وهمية.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10)))
    }

    private func vehicleInfoCard(_ vehicle: GarageVehicle) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(hex: vehicle.vehicleColorHex).opacity(0.18))
                        .frame(width: 58, height: 50)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundStyle(Color(hex: vehicle.vehicleColorHex))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(vehicle.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        if garage.activeVehicleID == vehicle.id {
                            Text(pdt("active"))
                                .font(.caption2.bold())
                                .foregroundStyle(.red)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.red.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(vehicle.vehiclePlateText.isEmpty ? "—" : vehicle.vehiclePlateText)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedVehicleID = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 9) {
                metric(title: pdt("speed"), value: "\(Int(vehicle.currentSpeedKmh.rounded()))", unit: "كم/س", icon: "speedometer")
                metric(title: pdt("status"), value: vehicle.currentSpeedKmh > 1 ? pdt("moving") : pdt("stopped"), unit: "", icon: vehicle.currentSpeedKmh > 1 ? "location.north.fill" : "parkingsign.circle.fill")
                metric(title: pdt("connection"), value: vehicle.isTelemetryOnline ? pdt("online") : pdt("offline"), unit: "", icon: vehicle.isTelemetryOnline ? "antenna.radiowaves.left.and.right" : "wifi.slash")
            }

            HStack {
                Label(lastUpdateText(vehicle.telemetryUpdatedAt), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if garage.activeVehicleID != vehicle.id {
                    Button {
                        garage.setActive(vehicle)
                    } label: {
                        Label(pdt("make_active"), systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.red.opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(.red.opacity(0.35)))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(colors: [.red.opacity(0.38), .cyan.opacity(0.34)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
        )
    }

    private func metric(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(.cyan)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(value)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07)))
    }

    private func lastUpdateText(_ date: Date?) -> String {
        guard let date else { return "ماكو تحديث بعد" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "آخر تحديث قبل أقل من دقيقة" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "آخر تحديث قبل \(minutes) د" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "آخر تحديث قبل \(hours) س" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct FleetVehiclePin: View {
    let vehicle: GarageVehicle
    let active: Bool
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.90))
                    .frame(width: selected ? 54 : 46, height: selected ? 54 : 46)
                    .overlay(
                        Circle().stroke(
                            active ? Color.red : Color.cyan,
                            lineWidth: selected ? 3 : 2
                        )
                    )
                    .shadow(color: (active ? Color.red : Color.cyan).opacity(0.35), radius: 7)

                Image(systemName: "car.fill")
                    .font(.system(size: selected ? 22 : 19, weight: .bold))
                    .foregroundStyle(Color(hex: vehicle.vehicleColorHex))
            }

            Text("\(Int(vehicle.currentSpeedKmh.rounded()))")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.80), in: Capsule())
        }
    }
}
