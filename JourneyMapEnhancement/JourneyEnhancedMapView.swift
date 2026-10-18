import SwiftUI
import MapKit
import CoreLocation

// JOURNEY map enhancement: one vehicle, no changes to remote/BLE/OBD controls.
struct JourneyMapPoint: Codable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(latitude)-\(longitude)" }
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speedKmh: Double?
    let heading: Double?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

enum JourneyVehicleMapState {
    case running, parked, alert, offline
    var tint: Color {
        switch self {
        case .running: return .green
        case .parked: return .yellow
        case .alert: return .red
        case .offline: return .gray
        }
    }
}

struct JourneyMapTrip: Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let points: [JourneyMapPoint]
    var distanceKm: Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { total, pair in
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            let meters = a.distance(from: b)
            // Ignore implausible GPS jumps; server remains authoritative for final mileage.
            return total + (meters <= 2000 ? meters / 1000 : 0)
        }
    }
}

struct JourneyEnhancedMapView: View {
    enum Tab: String, CaseIterable { case map = "الخريطة", trips = "الرحلات", stops = "التوقفات", stats = "الإحصائيات" }
    @State private var tab: Tab = .map
    @State private var style: MapStyleChoice = .standard
    @State private var position: MapCameraPosition = .automatic
    let current: JourneyMapPoint?
    let vehicleState: JourneyVehicleMapState
    let activeTrip: [JourneyMapPoint]
    let trips: [JourneyMapTrip]
    let stopSummaries: [String]
    var onLock: (() -> Void)? = nil
    var onUnlock: (() -> Void)? = nil

    enum MapStyleChoice: String, CaseIterable { case standard = "عادية", satellite = "أقمار", hybrid = "هجينة"
        var mapStyle: MapStyle {
            switch self { case .standard: return .standard; case .satellite: return .imagery; case .hybrid: return .hybrid }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Occupies the formerly empty space between JOURNEY header and map.
            HStack(spacing: 10) {
                Button(action: { onUnlock?() }) { Label("فتح", systemImage: "lock.open") }
                    .disabled(onUnlock == nil)
                Button(action: { onLock?() }) { Label("قفل", systemImage: "lock") }
                    .disabled(onLock == nil)
                Spacer()
                Picker("الخريطة", selection: $style) {
                    ForEach(MapStyleChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu)
            }.buttonStyle(.bordered).padding(.horizontal, 12)

            Picker("العرض", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 12)

            Group {
                switch tab {
                case .map:
                    Map(position: $position) {
                        if activeTrip.count >= 2 {
                            MapPolyline(coordinates: activeTrip.map(\.coordinate))
                                .stroke(.cyan, lineWidth: 4)
                        }
                        if let current {
                            Annotation("JOURNEY", coordinate: current.coordinate) {
                                Image(systemName: "car.fill")
                                    .foregroundStyle(.white)
                                    .padding(11)
                                    .background(vehicleState.tint, in: Circle())
                                    .rotationEffect(.degrees(current.heading ?? 0))
                            }
                        }
                    }.mapStyle(style.mapStyle)
                case .trips:
                    List(trips) { trip in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.startedAt, style: .date)
                            Text("المسافة التقريبية: \(trip.distanceKm, specifier: "%.1f") كم")
                            Text(trip.startedAt, style: .time)
                        }
                    }
                case .stops:
                    List(stopSummaries, id: \.self) { Text($0) }
                case .stats:
                    VStack(alignment: .leading, spacing: 12) {
                        Text("عدد الرحلات: \(trips.count)")
                        Text("المسافة المسجلة تقريبياً: \(trips.reduce(0) { $0 + $1.distanceKm }, specifier: "%.1f") كم")
                        Text("الإحصائيات النهائية تعتمد على بيانات السيرفر")
                        Spacer()
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
        }
        .background(Color.black)
        .foregroundStyle(.white)
    }
}
