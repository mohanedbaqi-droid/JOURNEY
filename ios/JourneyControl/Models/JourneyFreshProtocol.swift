import Foundation

/// FRESH V0.1.1 carries its own small GATT status protocol. It is not the
/// legacy VehicleState JSON, and must never be used to fabricate car telemetry.
struct JourneyFreshStatus: Equatable {
    let version: String
    let phones: Int
    let owners: Int
    let pending: Int
    let advertising: Bool
    let remotePower: Bool
    let gpioEnabled: Bool
    let uptimeMs: Int
    let disconnections: Int
    let advRetries: Int
    let authFailures: Int
    let queueDrops: Int

    init?(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["mode"] as? String == "FRESH_HID" else { return nil }
        version = json["version"] as? String ?? "JOURNEY FRESH"
        phones = json["phones"] as? Int ?? 0
        owners = json["owners"] as? Int ?? 0
        pending = json["pending"] as? Int ?? 0
        advertising = json["advertising"] as? Bool ?? false
        remotePower = json["remotePower"] as? Bool ?? false
        gpioEnabled = json["gpioEnabled"] as? Bool ?? false
        uptimeMs = json["uptimeMs"] as? Int ?? 0
        disconnections = json["disconnects"] as? Int ?? 0
        advRetries = json["advRetries"] as? Int ?? 0
        authFailures = json["authFailures"] as? Int ?? 0
        queueDrops = json["queueDrops"] as? Int ?? 0
    }
}

struct JourneyFreshIdentity: Equatable {
    let approved: Bool
    let admin: Bool
}

struct JourneyFreshRequest: Identifiable, Equatable {
    let id: String  // Random token from ESP, not a device-provided identifier.
    let deviceIdentity: String
    let name: String
}

struct JourneyFreshOwnerEvent {
    let kind: String
    let token: String
    let id: String
    let name: String
    let approved: Bool
    let admin: Bool

    init?(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = json["event"] as? String else { return nil }
        self.kind = kind
        token = json["token"] as? String ?? ""
        id = json["id"] as? String ?? ""
        name = json["name"] as? String ?? ""
        approved = json["approved"] as? Bool ?? false
        admin = json["admin"] as? Bool ?? false
    }
}
