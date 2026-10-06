import Foundation

struct GarageVehicle: Codable, Identifiable, Hashable {
    let id: UUID
    let profileID: String
    let year: Int
    var nickname: String
    var espDeviceID: String?
    var espDisplayName: String?

    // Visual identity is per garage vehicle, not per model/profile.
    // Optional keeps existing saved garages backward-compatible.
    var colorHex: String?
    var plateText: String?
    var plateGovernorateCode: String?
    var plateLetter: String?
    var plateNumber: String?

    // Customer / owner information. All fields are optional for backward compatibility.
    var customerName: String?
    var customerPhone: String?
    var annualCardDocumentPath: String?
    var unifiedIDDocumentPath: String?
    var customerDocumentsUpdatedAt: Date?
    var customerServerSyncState: String?

    // Live telemetry is stored per garage vehicle so fleet map can show all cars.
    // Optional fields preserve compatibility with vehicles already saved by older builds.
    var latitude: Double?
    var longitude: Double?
    var speedKmh: Double?
    var telemetryOnline: Bool?
    var telemetryUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        profileID: String,
        year: Int,
        nickname: String = "",
        espDeviceID: String? = nil,
        espDisplayName: String? = nil,
        colorHex: String? = "#F2F2F2",
        plateText: String? = nil,
        plateGovernorateCode: String? = nil,
        plateLetter: String? = nil,
        plateNumber: String? = nil,
        customerName: String? = nil,
        customerPhone: String? = nil,
        annualCardDocumentPath: String? = nil,
        unifiedIDDocumentPath: String? = nil,
        customerDocumentsUpdatedAt: Date? = nil,
        customerServerSyncState: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        speedKmh: Double? = nil,
        telemetryOnline: Bool? = nil,
        telemetryUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.year = year
        self.nickname = nickname
        self.espDeviceID = espDeviceID
        self.espDisplayName = espDisplayName
        self.colorHex = colorHex
        self.plateText = plateText
        self.plateGovernorateCode = plateGovernorateCode
        self.plateLetter = plateLetter
        self.plateNumber = plateNumber
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.annualCardDocumentPath = annualCardDocumentPath
        self.unifiedIDDocumentPath = unifiedIDDocumentPath
        self.customerDocumentsUpdatedAt = customerDocumentsUpdatedAt
        self.customerServerSyncState = customerServerSyncState
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmh = speedKmh
        self.telemetryOnline = telemetryOnline
        self.telemetryUpdatedAt = telemetryUpdatedAt
    }

    var profile: VehicleProfile? {
        VehicleCatalog.profiles.first { $0.id == profileID }
    }

    var displayName: String {
        if !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nickname }
        guard let profile else { return "سيارة" }
        return "\(profile.make) \(profile.model) \(year)"
    }

    var hasESP: Bool {
        guard let espDeviceID else { return false }
        return !espDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var espLabel: String {
        if let espDisplayName, !espDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return espDisplayName
        }
        return espDeviceID ?? "غير مربوط"
    }

    var vehicleColorHex: String {
        let clean = (colorHex ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "#F2F2F2" : clean
    }

    var vehiclePlateText: String {
        let code = (plateGovernorateCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let letter = (plateLetter ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let number = (plateNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty && !letter.isEmpty && !number.isEmpty {
            return IraqPlateData.formatted(code: code, letter: letter, number: number)
        }
        return (plateText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var vehiclePlateGovernorateCode: String {
        if let code = plateGovernorateCode, !code.isEmpty { return code }
        return IraqPlateData.parse(vehiclePlateText)?.code ?? "14"
    }

    var vehiclePlateLetter: String {
        if let letter = plateLetter, !letter.isEmpty { return letter.uppercased() }
        return IraqPlateData.parse(vehiclePlateText)?.letter ?? "A"
    }

    var vehiclePlateNumber: String {
        if let number = plateNumber, !number.isEmpty { return IraqPlateData.normalizeNumber(number) }
        return IraqPlateData.parse(vehiclePlateText)?.number ?? ""
    }

    var hasAnnualCardDocument: Bool {
        guard let annualCardDocumentPath else { return false }
        return !annualCardDocumentPath.isEmpty
    }

    var hasUnifiedIDDocument: Bool {
        guard let unifiedIDDocumentPath else { return false }
        return !unifiedIDDocumentPath.isEmpty
    }

    var customerDisplayName: String {
        let clean = (customerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "—" : clean
    }

    var customerDisplayPhone: String {
        let clean = (customerPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "—" : clean
    }

    var hasGPSFix: Bool {
        guard let latitude, let longitude else { return false }
        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    var currentSpeedKmh: Double { max(0, speedKmh ?? 0) }
    var isTelemetryOnline: Bool { telemetryOnline ?? false }
}

@MainActor
final class VehicleProfileStore: ObservableObject {
    @Published private(set) var vehicles: [GarageVehicle] = []
    @Published private(set) var activeVehicleID: UUID?

    private let vehiclesKey = "punisher.garage.vehicles"
    private let activeKey = "punisher.garage.activeVehicleID"
    private let legacySelectedKey = "punisher.selectedVehicleProfileID"

    init() {
        load()
        migrateLegacySelectionIfNeeded()
        normalizeActiveVehicle()
    }

    var activeVehicle: GarageVehicle? {
        guard let activeVehicleID else { return nil }
        return vehicles.first { $0.id == activeVehicleID }
    }

    var selected: VehicleProfile? { activeVehicle?.profile }
    var activeESPDeviceID: String? { activeVehicle?.espDeviceID }

    @discardableResult
    func add(profile: VehicleProfile, year: Int, nickname: String = "") -> GarageVehicle {
        let vehicle = GarageVehicle(profileID: profile.id, year: year, nickname: nickname)
        vehicles.append(vehicle)
        activeVehicleID = vehicle.id
        persistAndNotify(vehicle)
        return vehicle
    }

    func select(_ profile: VehicleProfile) {
        let year = profile.years.max() ?? Calendar.current.component(.year, from: Date())
        _ = add(profile: profile, year: year)
    }

    func setActive(_ vehicle: GarageVehicle) {
        guard vehicles.contains(where: { $0.id == vehicle.id }) else { return }
        activeVehicleID = vehicle.id
        persist()
        postVehicleChanged(vehicle)
    }

    func rename(_ vehicle: GarageVehicle, to nickname: String) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        vehicles[index].nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func updateAppearance(
        _ vehicle: GarageVehicle,
        colorHex: String,
        governorateCode: String,
        plateLetter: String,
        plateNumber: String
    ) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        let code = governorateCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let letter = plateLetter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let number = IraqPlateData.normalizeNumber(plateNumber)
        vehicles[index].colorHex = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicles[index].plateGovernorateCode = code
        vehicles[index].plateLetter = letter
        vehicles[index].plateNumber = number
        vehicles[index].plateText = IraqPlateData.formatted(code: code, letter: letter, number: number)
        persist()
        if activeVehicleID == vehicle.id { postVehicleChanged(vehicles[index]) }
    }

    func updateAppearance(_ vehicle: GarageVehicle, colorHex: String, plateText: String) {
        if let parsed = IraqPlateData.parse(plateText) {
            updateAppearance(
                vehicle,
                colorHex: colorHex,
                governorateCode: parsed.code,
                plateLetter: parsed.letter,
                plateNumber: parsed.number
            )
        } else {
            guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
            vehicles[index].colorHex = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
            vehicles[index].plateText = plateText.trimmingCharacters(in: .whitespacesAndNewlines)
            persist()
            if activeVehicleID == vehicle.id { postVehicleChanged(vehicles[index]) }
        }
    }

    func updateCustomerDocuments(
        _ vehicle: GarageVehicle,
        customerName: String,
        customerPhone: String,
        annualCardPath: String?,
        unifiedIDPath: String?
    ) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        vehicles[index].customerName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicles[index].customerPhone = customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicles[index].annualCardDocumentPath = annualCardPath
        vehicles[index].unifiedIDDocumentPath = unifiedIDPath
        vehicles[index].customerDocumentsUpdatedAt = Date()
        vehicles[index].customerServerSyncState = "local-only"
        persist()
        if activeVehicleID == vehicle.id { postVehicleChanged(vehicles[index]) }
        NotificationCenter.default.post(
            name: .punisherCustomerDocumentsChanged,
            object: nil,
            userInfo: ["garageVehicleID": vehicle.id.uuidString]
        )
    }

    func clearCustomerDocument(_ vehicle: GarageVehicle, kind: String) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        if kind == "annual" {
            vehicles[index].annualCardDocumentPath = nil
        } else if kind == "unified" {
            vehicles[index].unifiedIDDocumentPath = nil
        }
        vehicles[index].customerDocumentsUpdatedAt = Date()
        vehicles[index].customerServerSyncState = "local-only"
        persist()
        if activeVehicleID == vehicle.id { postVehicleChanged(vehicles[index]) }
    }

    func updateTelemetry(
        vehicleID: UUID,
        latitude: Double?,
        longitude: Double?,
        speedKmh: Double?,
        online: Bool,
        updatedAt: Date = Date()
    ) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicleID }) else { return }
        if let latitude, (-90...90).contains(latitude) { vehicles[index].latitude = latitude }
        if let longitude, (-180...180).contains(longitude) { vehicles[index].longitude = longitude }
        if let speedKmh { vehicles[index].speedKmh = max(0, speedKmh) }
        vehicles[index].telemetryOnline = online
        vehicles[index].telemetryUpdatedAt = updatedAt
        persist()
        NotificationCenter.default.post(
            name: .punisherTelemetryChanged,
            object: nil,
            userInfo: ["garageVehicleID": vehicleID.uuidString]
        )
    }

    func updateTelemetry(
        espDeviceID: String,
        latitude: Double?,
        longitude: Double?,
        speedKmh: Double?,
        online: Bool,
        updatedAt: Date = Date()
    ) {
        guard let vehicle = vehicles.first(where: { $0.espDeviceID == espDeviceID }) else { return }
        updateTelemetry(
            vehicleID: vehicle.id,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speedKmh,
            online: online,
            updatedAt: updatedAt
        )
    }

    func bindESP(_ vehicle: GarageVehicle, deviceID: String, displayName: String = "") {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        let cleanID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }

        for otherIndex in vehicles.indices where otherIndex != index && vehicles[otherIndex].espDeviceID == cleanID {
            vehicles[otherIndex].espDeviceID = nil
            vehicles[otherIndex].espDisplayName = nil
        }

        vehicles[index].espDeviceID = cleanID
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicles[index].espDisplayName = cleanName.isEmpty ? nil : cleanName
        persist()
        postVehicleChanged(vehicles[index])
        NotificationCenter.default.post(
            name: .punisherESPBindingChanged,
            object: nil,
            userInfo: ["garageVehicleID": vehicle.id.uuidString, "espDeviceID": cleanID]
        )
    }

    func unbindESP(_ vehicle: GarageVehicle) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        vehicles[index].espDeviceID = nil
        vehicles[index].espDisplayName = nil
        persist()
        if activeVehicleID == vehicle.id { postVehicleChanged(vehicles[index]) }
        NotificationCenter.default.post(
            name: .punisherESPBindingChanged,
            object: nil,
            userInfo: ["garageVehicleID": vehicle.id.uuidString]
        )
    }

    func remove(_ vehicle: GarageVehicle) {
        let wasActive = activeVehicleID == vehicle.id
        vehicles.removeAll { $0.id == vehicle.id }
        if wasActive { activeVehicleID = vehicles.first?.id }
        persist()
        if let activeVehicle { postVehicleChanged(activeVehicle) }
        else { NotificationCenter.default.post(name: .punisherVehicleProfileChanged, object: nil) }
    }

    func clear() {
        vehicles = []
        activeVehicleID = nil
        persist()
        NotificationCenter.default.post(name: .punisherVehicleProfileChanged, object: nil)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: vehiclesKey),
           let decoded = try? JSONDecoder().decode([GarageVehicle].self, from: data) {
            vehicles = decoded.filter { $0.profile != nil }
        }
        if let raw = UserDefaults.standard.string(forKey: activeKey) {
            activeVehicleID = UUID(uuidString: raw)
        }
    }

    private func migrateLegacySelectionIfNeeded() {
        guard vehicles.isEmpty,
              let profileID = UserDefaults.standard.string(forKey: legacySelectedKey),
              let profile = VehicleCatalog.profiles.first(where: { $0.id == profileID }) else { return }
        let year = profile.years.max() ?? Calendar.current.component(.year, from: Date())
        let migrated = GarageVehicle(profileID: profile.id, year: year)
        vehicles = [migrated]
        activeVehicleID = migrated.id
        UserDefaults.standard.removeObject(forKey: legacySelectedKey)
        persist()
    }

    private func normalizeActiveVehicle() {
        if activeVehicle == nil { activeVehicleID = vehicles.first?.id }
        persist()
    }

    private func persistAndNotify(_ vehicle: GarageVehicle) {
        persist()
        postVehicleChanged(vehicle)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(vehicles) {
            UserDefaults.standard.set(data, forKey: vehiclesKey)
        }
        if let activeVehicleID {
            UserDefaults.standard.set(activeVehicleID.uuidString, forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }

    private func postVehicleChanged(_ vehicle: GarageVehicle) {
        guard let profile = vehicle.profile else { return }
        var info: [String: Any] = [
            "profileID": profile.id,
            "garageVehicleID": vehicle.id.uuidString,
            "year": vehicle.year,
            "colorHex": vehicle.vehicleColorHex,
            "plateText": vehicle.vehiclePlateText,
            "plateGovernorateCode": vehicle.vehiclePlateGovernorateCode,
            "plateLetter": vehicle.vehiclePlateLetter,
            "plateNumber": vehicle.vehiclePlateNumber
        ]
        if let espDeviceID = vehicle.espDeviceID { info["espDeviceID"] = espDeviceID }
        NotificationCenter.default.post(name: .punisherVehicleProfileChanged, object: nil, userInfo: info)
    }
}

extension Notification.Name {
    static let punisherCustomerDocumentsChanged = Notification.Name("punisher.customerDocumentsChanged")
    static let punisherVehicleProfileChanged = Notification.Name("punisherVehicleProfileChanged")
    static let punisherESPBindingChanged = Notification.Name("punisherESPBindingChanged")
    static let punisherTelemetryChanged = Notification.Name("punisherTelemetryChanged")
}
