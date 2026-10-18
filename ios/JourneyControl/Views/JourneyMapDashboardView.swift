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
    @StateObject private var history = JourneyLocalHistory.shared
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
                    historyList
                case .stops:
                    stopsList
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
                        Text("المسافة المسجلة محلياً خلال أسبوع: \(history.distanceKm, specifier: "%.1f") كم. التسجيل قد يتوقف عند إغلاق التطبيق.")
                            .foregroundStyle(.secondary).font(.footnote)
                        Spacer()
                    }.padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .onAppear { capturePoint(); history.prune() }
        .onChange(of: vehicle.latitude) { _ in capturePoint() }
        .onChange(of: vehicle.longitude) { _ in capturePoint() }
    }

    private func capturePoint() {
        guard vehicle.gpsValid, vehicle.online else { return }
        history.record(latitude: vehicle.latitude, longitude: vehicle.longitude,
                       speedKph: vehicle.speedValid ? Double(vehicle.speedKph) : nil,
                       engineRunning: vehicle.rpmValid ? vehicle.simulatedEngineRunning : nil)
    }

    private var historyList: some View {
        List {
            Section(header: Text("نقاط GPS المسجلة خلال 7 أيام")) {
                ForEach(Array(history.points.reversed())) { point in
                    VStack(alignment: .leading) {
                        Text(point.timestamp, format: .dateTime.day().month().hour().minute())
                        Text(String(format: "%.5f, %.5f", point.latitude, point.longitude))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var stopsList: some View {
        VStack(spacing: 12) {
            Text("التوقفات").font(.headline)
            Text("النقاط محفوظة محلياً لمدة أسبوع؛ تحليل التوقفات التفصيلي قيد التطوير.")
                .foregroundStyle(.secondary)
            Text("عدد النقاط: \(history.points.count)")
            Spacer()
        }.padding()
    }


    private func placeholder(_ title: String, _ detail: String, _ symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
