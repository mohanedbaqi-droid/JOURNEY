import Combine
import Foundation

@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [DeviceProfile] {
        didSet { saveDevices() }
    }

    @Published var selectedID: UUID? {
        didSet { saveSelection() }
    }

    private let devicesKey = "journey.devices.v1"
    private let selectionKey = "journey.selected-device.v1"
    private static let productionDeviceID = "journey-esp32s3-01"

    init() {
        if let data = UserDefaults.standard.data(forKey: devicesKey),
           let decoded = try? JSONDecoder().decode([DeviceProfile].self, from: data) {
            devices = decoded.isEmpty ? [DeviceProfile(name: JL("سيارة جورني", "Journey vehicle"), deviceID: Self.productionDeviceID)] : decoded
        } else {
            devices = [DeviceProfile(name: JL("سيارة جورني", "Journey vehicle"), deviceID: Self.productionDeviceID)]
        }

        // Migrate only the old placeholder used by earlier build packages.
        if let index = devices.firstIndex(where: { $0.deviceID == "demo-local" || $0.deviceID == "journey-bench-01" }) {
            devices[index].name = JL("سيارة جورني", "Journey vehicle")
            devices[index].deviceID = Self.productionDeviceID
        }

        if let value = UserDefaults.standard.string(forKey: selectionKey) {
            selectedID = UUID(uuidString: value)
        } else {
            selectedID = devices.first?.id
        }

        if selectedDevice == nil { selectedID = devices.first?.id }
    }

    var selectedDevice: DeviceProfile? {
        devices.first { $0.id == selectedID }
    }

    func add(name: String, deviceID: String) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanID.isEmpty else { return JL("أدخل الاسم ومعرّف الجهاز", "Enter a name and device ID") }
        guard cleanID.range(of: "^[A-Za-z0-9_-]{3,40}$", options: .regularExpression) != nil else {
            return JL("المعرّف يقبل حروف إنكليزية وأرقام و - أو _ فقط", "Use English letters, numbers, - or _ for the ID")
        }
        guard !devices.contains(where: { $0.deviceID.caseInsensitiveCompare(cleanID) == .orderedSame }) else {
            return JL("هذا المعرّف مضاف مسبقاً", "This device ID is already added")
        }

        let profile = DeviceProfile(name: cleanName, deviceID: cleanID)
        devices.append(profile)
        selectedID = profile.id
        return nil
    }

    func delete(at offsets: IndexSet) {
        let selectedWasDeleted = offsets.contains { devices[$0].id == selectedID }
        for index in offsets.sorted(by: >) { devices.remove(at: index) }
        if selectedWasDeleted { selectedID = devices.first?.id }
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: devicesKey)
        }
    }

    private func saveSelection() {
        UserDefaults.standard.set(selectedID?.uuidString, forKey: selectionKey)
    }
}
