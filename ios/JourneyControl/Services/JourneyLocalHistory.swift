import Foundation
import CoreLocation
import Combine

struct JourneyHistoryPoint: Codable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var speedKph: Double?
    var engineRunning: Bool?
}

@MainActor
final class JourneyLocalHistory: ObservableObject {
    static let shared = JourneyLocalHistory()
    @Published private(set) var points: [JourneyHistoryPoint] = []
    private let retention: TimeInterval = 7 * 24 * 3600
    private let maximumPoints = 25000
    private let url: URL
    private var lastWrite: Date = .distantPast

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("journey-history-week.json")
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([JourneyHistoryPoint].self, from: data) {
            points = stored
        }
        prune()
    }

    func record(latitude: Double, longitude: Double, speedKph: Double?, engineRunning: Bool?) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              !(latitude == 0 && longitude == 0) else { return }
        let timestamp = Date()
        // Save at most one point every ten seconds; skip obvious GPS jumps.
        guard timestamp.timeIntervalSince(lastWrite) >= 10 else { return }
        if let previous = points.last {
            let a = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let b = CLLocation(latitude: latitude, longitude: longitude)
            let seconds = timestamp.timeIntervalSince(previous.timestamp)
            if seconds > 0 && a.distance(from: b) / seconds > 85 { return }
        }
        points.append(.init(timestamp: timestamp, latitude: latitude, longitude: longitude,
                            speedKph: speedKph, engineRunning: engineRunning))
        lastWrite = timestamp
        prune()
    }

    func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        points.removeAll { $0.timestamp < cutoff }
        if points.count > maximumPoints { points.removeFirst(points.count - maximumPoints) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(points) else { return }
        try? data.write(to: url, options: .atomic)
    }

    var distanceKm: Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0.0) { sum, pair in
            let seconds = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard seconds > 0 && seconds < 300 else { return sum }
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            let distance = a.distance(from: b)
            return sum + (distance / seconds <= 85 ? distance / 1000 : 0)
        }
    }
}
