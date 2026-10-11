import ActivityKit
import Foundation

/// State is delivered by ActivityKit from the containing app to the lock
/// screen. No App Group file or shared UserDefaults is required.
struct JourneyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var demoMode: Bool
        var online: Bool
        var locked: Bool?
        var engineRunning: Bool?
        var rpm: Int?
        var coolantC: Int?
        var batteryV: Double?
        var espTemperatureC: Double?
        var doorKnownMask: Int
        var doorOpenMask: Int
        var lowBeam: Bool?
        var leftTurn: Bool?
        var rightTurn: Bool?
        var lastReading: Date?

        func door(_ bit: Int) -> Bool? {
            (doorKnownMask & bit) == 0 ? nil : (doorOpenMask & bit) != 0
        }

        var openDoorCount: Int {
            [2, 4, 8, 16, 32, 64].filter { door($0) == true }.count
        }
    }

    var vehicleID: String
    var vehicleName: String
}
