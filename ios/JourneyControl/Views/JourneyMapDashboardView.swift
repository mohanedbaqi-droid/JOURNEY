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
    @StateObject private var serverHistory = JourneyHistoryAPI()
    @State private var showServerSettings = false
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
                    serverHistory.baseURL.isEmpty ? historyList : serverTrips
                case .stops:
                    serverHistory.baseURL.isEmpty ? stopsList : serverStops
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
                        if let stats = serverHistory.stats {
                            Text("رحلات السيرفر: \(stats.trip_count)")
                            Text(String(format:"مسافة السيرفر: %.1f كم",stats.distance_m / 1000))
                            Text(String(format:"أعلى سرعة مسجلة: %.0f كم/س",stats.max_speed_kph))
                        }
                        Text("المسافة المسجلة محلياً خلال أسبوع: \(history.distanceKm, specifier: "%.1f") كم. التسجيل قد يتوقف عند إغلاق التطبيق.")
                            .foregroundStyle(.secondary).font(.footnote)
                        Spacer()
                    }.padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .onAppear { capturePoint(); history.prune(); Task { await serverHistory.refresh() } }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    showServerSettings = true
                } label: {
                    Label("سيرفر الرحلات", systemImage: "server.rack")
                        .font(.footnote)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showServerSettings) {
            NavigationStack {
                Form {
                    TextField("https://history.example.com", text: $serverHistory.baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("History API token", text: $serverHistory.token)
                    Button("حفظ وربط السيرفر") {
                        serverHistory.saveConfiguration()
                        showServerSettings = false
                        Task { await serverHistory.refresh() }
                    }
                    Text("HTTPS مطلوب. لا تستخدم باسورد MQTT هنا؛ هذا رمز API مستقل.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.navigationTitle("سيرفر الرحلات")
            }
        }
        .onChange(of: vehicle.latitude) { _ in capturePoint() }
        .onChange(of: vehicle.longitude) { _ in capturePoint() }
    }

    private func capturePoint() {
        guard vehicle.gpsValid, vehicle.online else { return }
        history.record(latitude: vehicle.latitude, longitude: vehicle.longitude,
                       speedKph: vehicle.speedValid ? Double(vehicle.speedKph) : nil,
                       engineRunning: vehicle.rpmValid ? vehicle.simulatedEngineRunning : nil)
    }

    private var serverTrips: some View {
        List {
            if let error = serverHistory.error { Text(error).foregroundStyle(.orange) }
            Button("تحديث سجل الرحلات") { Task { await serverHistory.refresh() } }
            ForEach(serverHistory.trips) { trip in
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.started_at, format: .dateTime.day().month().year().hour().minute())
                        .font(.headline)
                    Text(String(format: "المسافة %.2f كم • أعلى سرعة %.0f كم/س",
                                trip.distance_m / 1000, trip.max_speed_kph))
                    Text(trip.ended_at == nil ? "الرحلة جارية" : "الرحلة مكتملة")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("عرض نقاط المسار") {
                        Task { await serverHistory.loadPoints(tripID: trip.id) }
                    }
                }
            }
            if !serverHistory.selectedTripPoints.isEmpty {
                SwiftUI.Section("نقاط المسار") {
                    ForEach(Array(serverHistory.selectedTripPoints.enumerated()), id: \.offset) { _, point in
                        Text(String(format:"%.5f, %.5f",point.lat,point.lon))
                            .font(.caption.monospaced())
                    }
                }
            }
        }
    }

    private var serverStops: some View {
        List {
            if let error = serverHistory.error { Text(error).foregroundStyle(.orange) }
            Button("تحديث التوقفات") { Task { await serverHistory.refresh() } }
            ForEach(serverHistory.stops) { stop in
                VStack(alignment: .leading) {
                    Text(stop.arrived_at,format:.dateTime.day().month().hour().minute())
                    if let departure = stop.departed_at {
                        Text(String(format:"مدة التوقف %.0f دقيقة", departure.timeIntervalSince(stop.arrived_at)/60))
                    } else { Text("التوقف مستمر") }
                    Text(String(format:"%.5f, %.5f",stop.lat,stop.lon))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var historyList: some View {
        List {
            SwiftUI.Section(header: Text("نقاط GPS المسجلة خلال 7 أيام")) {
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
