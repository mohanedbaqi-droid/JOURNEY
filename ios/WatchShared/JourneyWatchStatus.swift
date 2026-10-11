import Foundation

/// Sanitized, read-only vehicle state sent from the trusted iPhone companion
/// to Apple Watch. No credentials, owner tokens, or raw ESP commands.
struct JourneyWatchStatus: Codable, Equatable {
    var deviceID: String = ""
    var vehicleName: String = "JOURNEY"
    var demoMode: Bool = false
    var online: Bool = false
    var locked: Bool? = nil
    var running: Bool? = nil
    var rpm: Int? = nil
    var speedKph: Int? = nil
    var coolantC: Int? = nil
    var vehicleBattery: Double? = nil
    var doorKnownMask: Int = 0
    var doorOpenMask: Int = 0
    var headlights: Bool? = nil
    var leftTurn: Bool? = nil
    var rightTurn: Bool? = nil
    var readingAt: Date? = nil
    var transferredAt: Date = Date()

    func door(_ bit: Int) -> Bool? {
        (doorKnownMask & bit) == 0 ? nil : (doorOpenMask & bit) != 0
    }

    var openDoorCount: Int {
        [2, 4, 8, 16, 32, 64].filter { door($0) == true }.count
    }

    func fresh(at date: Date = Date()) -> Bool {
        if demoMode { return true }
        guard online, let readingAt else { return false }
        let elapsed = date.timeIntervalSince(readingAt)
        return elapsed >= 0 && elapsed < 15
    }
}
