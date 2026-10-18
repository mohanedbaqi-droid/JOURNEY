import SwiftUI
import MapKit

/// The existing live map stays intact. This screen adds JOURNEY's trip-history
/// navigation without touching BLE, MQTT, OBD or remote command handling.
struct JourneyMapDashboardView: View {
    @EnvironmentObject private var mqtt: MQTTService
    let vehicle: VehicleState
    let vehicleName: String
    let deviceID: String?
    @State private var selection: Section = .live
    @State private var mapStyle: MapKind = .standard

    private enum Section: String, CaseIterable, Identifiable {
        case live = "الخريطة", trips = "الرحلات", stops = "التوقفات", statistics = "الإحصائيات"
        var id: String { rawValue }
    }
    private enum MapKind: String, CaseIterable, Identifiable {
        case standard = "عادية", satellite = "أقمار صناعية", hybrid = "هجينة"
        var id: String { rawValue }
    }
    private var stateColor: Color {
        guard vehicle.online else { return .gray }
        guard vehicle.rpmValid else { return .gray }
        return vehicle.simulatedEngineRunning ? .green : .yellow
    }
    private var stateText: String {
        guard vehicle.online else { return "غير متصل" }
        guard vehicle.rpmValid else { return "حالة المحرك غير معروفة" }
        return vehicle.simulatedEngineRunning ? "المحرك يعمل" : "المحرك متوقف"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(stateColor).frame(width: 11, height: 11)
                Text(stateText).font(.subheadline).bold()
                Spacer()
                if vehicle.speedValid {
                    Text("\(vehicle.speedKph) كم/س").font(.subheadline.monospacedDigit())
                }
                if vehicle.gpsValid {
                    Image(systemName: "location.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "location.slash").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Picker("قسم الخريطة", selection: $selection) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10).padding(.vertical, 8)

            Group {
                switch selection {
                case .live:
                    // Reuse the existing map and its location handling.
                    VehicleMapView(vehicle: vehicle, vehicleName: vehicleName, deviceID: deviceID)
                        .environmentObject(mqtt)
                case .trips:
                    placeholder("سجل الرحلات", "راح تظهر الرحلات هنا بعد ربط تخزين الرحلات بالسيرفر.", "point.topleft.down.curvedto.point.bottomright.up")
                case .stops:
                    placeholder("سجل التوقفات", "راح تظهر مواقع التوقف ومددها هنا بعد ربط السجل بالسيرفر.", "parkingsign.circle")
                case .statistics:
                    VStack(alignment: .leading, spacing: 18) {
                        Label("معلومات السيارة المباشرة", systemImage: "chart.bar")
                            .font(.headline)
                        HStack {
                            Text("سرعة CAN")
                            Spacer()
                            Text(vehicle.speedValid ? "\(vehicle.speedKph) كم/س" : "غير متاحة")
                        }
                        HStack {
                            Text("حالة GPS")
                            Spacer()
                            Text(vehicle.gpsValid ? "متاح" : "غير متاح")
                        }
                        HStack {
                            Text("حالة المحرك")
                            Spacer()
                            Text(stateText)
                        }
                        Divider()
                        Text("إحصائيات المسافة والرحلات تحتاج سجل السيرفر؛ ما راح نعرض أرقام تخمينية.")
                            .foregroundStyle(.secondary).font(.footnote)
                        Spacer()
                    }.padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }

    private func placeholder(_ title: String, _ detail: String, _ symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
