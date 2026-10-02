import Foundation

struct DeviceProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var deviceID: String

    init(id: UUID = UUID(), name: String, deviceID: String) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

