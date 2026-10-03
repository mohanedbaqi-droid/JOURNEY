import CocoaMQTT
import Combine
import Foundation
import Security

@MainActor
final class MQTTService: ObservableObject {
    enum Connection: String {
        case notConfigured = "غير مهيأ"
        case disconnected = "غير متصل"
        case connecting = "جاري الاتصال"
        case connected = "متصل"
    }

    struct Settings {
        var host: String
        var port: UInt16
        var username: String
        var password: String
    }

    private struct OwnerSnapshot: Codable {
        var trustedPhoneConfigured: Bool
        var authorizedPhoneCount: Int
        var ownerAdminPhone: String
        var pendingOwnerPhone: String
        var uptimeSeconds: UInt64?
    }

    @Published private(set) var connection: Connection = .notConfigured
    @Published private(set) var vehicles: [String: VehicleState] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var lastCommand: BenchAction?
    @Published private(set) var lastCommandAt: Date?
    @Published private(set) var lastStateAt: [String: Date] = [:]
    @Published private(set) var commandHistory: [BenchEvent] = []
    @Published private(set) var bluetoothStatus = "غير متصل"
    // v12.52: independent real ESP button feedback. Do not use lastEvent because
    // the ESP immediately follows remote_button_*_on with lock/unlock/horn/etc.
    @Published private(set) var buttonFeedback: [String: Set<String>] = [:]

    private var client: CocoaMQTT?
    private let bluetooth = BluetoothVehicleService()
    private let defaults = UserDefaults.standard
    private let passwordAccount = "mqtt-password"
    private var bluetoothRSSIByDevice: [String: Int] = [:]
    private var feedbackGeneration: [String: UUID] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init() {
        bluetooth.onState = { [weak self] deviceID, state in
            Task { @MainActor in
                self?.receive(state, from: deviceID)
            }
        }
        bluetooth.onRSSI = { [weak self] deviceID, rssi in
            Task { @MainActor in
                guard let self else { return }
                self.bluetoothRSSIByDevice[deviceID] = rssi
                var state = self.vehicles[deviceID] ?? VehicleState()
                state.bluetoothRSSI = rssi
                self.vehicles[deviceID] = state
            }
        }
        bluetooth.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.bluetoothStatus = $0 }
            .store(in: &cancellables)
        // Heartbeat watchdog: stale cached state must never look connected.
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                for (deviceID, seenAt) in self.lastStateAt where now.timeIntervalSince(seenAt) > 4.0 {
                    // BLE transport state is authoritative for iPhone <-> ESP connectivity.
                    // A stale state packet or command timeout must never mark an actually
                    // connected CBPeripheral as disconnected.
                    if self.bluetooth.isConnected(to: deviceID) {
                        if var state = self.vehicles[deviceID], !state.online {
                            state.online = true
                            self.vehicles[deviceID] = state
                        }
                        continue
                    }
                    guard var state = self.vehicles[deviceID], state.online else { continue }
                    state.online = false
                    state.remotePowered = false
                    state.simulatedEngineRunning = false
                    state.lastEvent = "esp_disconnected"
                    self.vehicles[deviceID] = state
                }
            }
            .store(in: &cancellables)
    }

    var settings: Settings {
        let savedPort = UInt16(exactly: defaults.integer(forKey: "journey.mqtt.port"))
        return Settings(
            host: defaults.string(forKey: "journey.mqtt.host") ?? "",
            port: (savedPort ?? 0) == 0 ? AppConfig.defaultBrokerPort : (savedPort ?? AppConfig.defaultBrokerPort),
            username: defaults.string(forKey: "journey.mqtt.username") ?? "",
            password: readPassword()
        )
    }

    var isConfigured: Bool {
        !settings.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveSettings(host: String, port: UInt16, username: String, password: String) {
        disconnect()
        defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "journey.mqtt.host")
        defaults.set(Int(port), forKey: "journey.mqtt.port")
        defaults.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "journey.mqtt.username")
        savePassword(password)
        connection = isConfigured ? .disconnected : .notConfigured
        lastError = nil
    }

    func connect() {
        let config = settings
        guard isConfigured else {
            connection = .notConfigured
            lastError = "أدخل إعدادات MQTT أولاً"
            return
        }

        client?.disconnect()
        let mqtt = CocoaMQTT(
            clientID: "journey-ios-\(UUID().uuidString)",
            host: config.host,
            port: config.port
        )
        mqtt.username = config.username.isEmpty ? nil : config.username
        mqtt.password = config.password.isEmpty ? nil : config.password
        mqtt.enableSSL = true
        mqtt.manuallyEvaluateTrust = false
        mqtt.keepAlive = 30
        mqtt.autoReconnect = true
        connection = .connecting

        mqtt.didConnectAck = { [weak self] mqtt, ack in
            DispatchQueue.main.async {
                guard let self else { return }
                if ack == .accept {
                    self.connection = .connected
                    self.lastError = nil
                    mqtt.subscribe(AppConfig.allStateTopics, qos: .qos1)
                } else {
                    self.connection = .disconnected
                    self.lastError = "رفض خادم MQTT الاتصال: \(ack)"
                }
            }
        }

        mqtt.didReceiveMessage = { [weak self] _, message, _ in
            let parts = message.topic.split(separator: "/")
            guard parts.count == 3,
                  parts[0] == "journey",
                  parts[2] == "state",
                  let data = message.string?.data(using: .utf8),
                  let state = try? JSONDecoder().decode(VehicleState.self, from: data)
            else { return }
            let deviceID = String(parts[1])
            DispatchQueue.main.async {
                self?.receive(state, from: deviceID)
            }
        }

        mqtt.didDisconnect = { [weak self] _, error in
            DispatchQueue.main.async {
                self?.connection = .disconnected
                if let error { self?.lastError = error.localizedDescription }
            }
        }

        client = mqtt
        _ = mqtt.connect()
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        connection = isConfigured ? .disconnected : .notConfigured
    }

    func state(for deviceID: String) -> VehicleState {
        if let state = vehicles[deviceID] { return state }
        return cachedOwnerState(for: deviceID) ?? VehicleState()
    }

    /// Registers the selected ESP32 for BLE background reconnection.
    func prepareBluetooth(for deviceID: String) {
        restoreCachedOwnerStateIfNeeded(for: deviceID)
        bluetooth.prepareConnection(to: deviceID)
    }

    /// Reconnect immediately when the app returns to the foreground. This is
    /// separate from sending a vehicle command, so the status becomes connected
    /// before the user touches any control.
    func resumeBluetooth(for deviceID: String) {
        restoreCachedOwnerStateIfNeeded(for: deviceID)
        bluetooth.resumeConnection(to: deviceID)
    }

    @discardableResult
    func send(_ action: BenchAction, to deviceID: String) -> Bool {
        // A broker may be connected while the ESP is offline. Prefer the
        // confirmed nearby BLE command channel in that case.
        if bluetooth.isConnected(to: deviceID), bluetooth.send(action, to: deviceID) {
            // Do not fake button feedback locally. Wait for the ESP event/state.
            lastCommand = action
            lastCommandAt = Date()
            record(action)
            lastError = nil
            return true
        }
        guard connection == .connected, let client else {
            if bluetooth.send(action, to: deviceID) {
                // Command is queued while BLE reconnects. Feedback comes only
                // from the ESP after the real remote output becomes active.
                lastCommand = action
                lastCommandAt = Date()
                record(action)
                lastError = nil
                return true
            }
            lastError = "لا يوجد إنترنت ولا اتصال BLE؛ فعّل البلوتوث واقترب من السيارة"
            return false
        }

        do {
            let data = try JSONEncoder().encode(VehicleCommand(action: action))
            guard let json = String(data: data, encoding: .utf8) else {
                lastError = "تعذر تجهيز الأمر"
                return false
            }
            client.publish(AppConfig.commandTopic(for: deviceID), withString: json, qos: .qos1, retained: false)
            lastCommand = action
            lastCommandAt = Date()
            record(action)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Saves the desired smart-entry behaviour in the ESP32.  The ESP32 must
    /// still enforce authenticated BLE and its own RSSI calibration.
    @discardableResult
    func sendKeylessConfig(_ config: KeylessEntryConfig, to deviceID: String) -> Bool {
        bluetooth.configureKeyless(config, for: deviceID)
        let command = VehicleCommand(action: .keylessConfig, keyless: config)
        // Registration must be delivered to the live local ESP, even when
        // the phone's MQTT connection is also active.
        if bluetooth.isConnected(to: deviceID), bluetooth.send(VehicleCommand(action: .ownerRegister), to: deviceID) {
            lastCommand = .keylessConfig
            lastCommandAt = Date()
            record(.keylessConfig)
            lastError = nil
            return true
        }
        guard connection == .connected, let client else {
            if bluetooth.send(command, to: deviceID) {
                lastCommand = .keylessConfig
                lastCommandAt = Date()
                record(.keylessConfig)
                lastError = nil
                return true
            }
            lastError = "لا يوجد إنترنت ولا اتصال BLE؛ فعّل البلوتوث واقترب من السيارة"
            return false
        }

        do {
            let data = try JSONEncoder().encode(command)
            guard let json = String(data: data, encoding: .utf8) else {
                lastError = "تعذر تجهيز إعدادات الدخول الذكي"
                return false
            }
            client.publish(AppConfig.commandTopic(for: deviceID), withString: json, qos: .qos1, retained: false)
            lastCommand = .keylessConfig
            lastCommandAt = Date()
            record(.keylessConfig)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func sendESPSettings(_ settings: ESPRuntimeSettings, to deviceID: String) -> Bool {
        let command = VehicleCommand(action: .espSettings, espSettings: settings)
        guard connection == .connected, let client else {
            if bluetooth.send(command, to: deviceID) {
                lastCommand = .espSettings
                lastCommandAt = Date()
                record(.espSettings)
                lastError = nil
                return true
            }
            lastError = "تعذر الاتصال بـ ESP عبر BLE أو الإنترنت"
            return false
        }
        do {
            let data = try JSONEncoder().encode(command)
            guard let json = String(data: data, encoding: .utf8) else { return false }
            client.publish(AppConfig.commandTopic(for: deviceID), withString: json, qos: .qos1, retained: false)
            lastCommand = .espSettings
            lastCommandAt = Date()
            record(.espSettings)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func sendFirmwareURL(_ url: String, to deviceID: String) -> Bool {
        let command = VehicleCommand(action: .otaURL, firmwareURL: url)
        guard connection == .connected, let client else {
            if bluetooth.send(command, to: deviceID) {
                lastCommand = .otaURL
                lastCommandAt = Date()
                record(.otaURL)
                lastError = nil
                return true
            }
            lastError = "تعذر إرسال رابط التحديث"
            return false
        }
        do {
            let data = try JSONEncoder().encode(command)
            guard let json = String(data: data, encoding: .utf8) else { return false }
            client.publish(AppConfig.commandTopic(for: deviceID), withString: json, qos: .qos1, retained: false)
            lastCommand = .otaURL
            lastCommandAt = Date()
            record(.otaURL)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func sendESPCommand(_ command: VehicleCommand, to deviceID: String) -> Bool {
        // OBD setup must reach the nearby ESP immediately. A remembered or
        // stale MQTT session must not steal this command from the BLE link.
        if bluetooth.send(command, to: deviceID) {
            // Show the first-owner action immediately after the GATT write.
            // The following ESP state notification remains authoritative.
            applyLocal(command.action, to: deviceID)
            lastCommand = command.action
            lastCommandAt = Date()
            record(command.action)
            lastError = nil
            return true
        }
        guard connection == .connected, let client else {
            if bluetooth.send(command, to: deviceID) {
                applyLocal(command.action, to: deviceID)
                lastCommand = command.action
                lastCommandAt = Date()
                record(command.action)
                lastError = nil
                return true
            }
            lastError = "تعذر الاتصال بـ ESP"
            return false
        }
        do {
            let data = try JSONEncoder().encode(command)
            guard let json = String(data: data, encoding: .utf8) else { return false }
            client.publish(AppConfig.commandTopic(for: deviceID), withString: json, qos: .qos1, retained: false)
            lastCommand = command.action
            lastCommandAt = Date()
            record(command.action)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// v12.37: commands never fake vehicle/remote state locally.
    /// The ESP state packet is authoritative, so the key icon and notifications
    /// change only when the real remote-power GPIO changes on the ESP.
    private func applyLocal(_ action: BenchAction, to deviceID: String) {
        // v12.38: intentionally no optimistic UI mutation. The ESP is the only
        // source of truth for connection, remote power and button feedback.
    }

    func isButtonActive(_ button: String, for deviceID: String) -> Bool {
        buttonFeedback[deviceID]?.contains(button) == true
    }

    private func updateButtonFeedback(event: String, deviceID: String) {
        func set(_ button: String, active isActive: Bool) {
            var buttons = buttonFeedback[deviceID] ?? []
            let key = "\(deviceID)|\(button)"
            if isActive {
                buttons.insert(button)
                let token = UUID()
                feedbackGeneration[key] = token
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2.2))
                    guard let self, self.feedbackGeneration[key] == token else { return }
                    var latest = self.buttonFeedback[deviceID] ?? []
                    latest.remove(button)
                    self.buttonFeedback[deviceID] = latest
                    self.feedbackGeneration.removeValue(forKey: key)
                }
            } else {
                buttons.remove(button)
                feedbackGeneration.removeValue(forKey: key)
            }
            buttonFeedback[deviceID] = buttons
        }

        switch event {
        case "remote_button_lock_on": set("lock", active: true)
        case "remote_button_lock_off": set("lock", active: false)
        case "remote_button_unlock_on": set("unlock", active: true)
        case "remote_button_unlock_off": set("unlock", active: false)
        case "remote_button_start_on": set("start", active: true)
        case "remote_button_start_off": set("start", active: false)
        case "remote_button_alarm_on": set("alarm", active: true)
        case "remote_button_alarm_off": set("alarm", active: false)
        default: break
        }
    }

    private func receive(_ state: VehicleState, from deviceID: String) {
        let previous = vehicles[deviceID] ?? cachedOwnerState(for: deviceID)
        // Capture button edges before lastEvent is replaced by the following core packet.
        if !state.lastEvent.isEmpty { updateButtonFeedback(event: state.lastEvent, deviceID: deviceID) }

        if state.vehicleEventPacket {
            updateButtonFeedback(event: state.vehicleEventType, deviceID: deviceID)

            if state.vehicleEventType == "engine_stopped_obd", (previous?.speedKph ?? 0) > 5 {
                if !state.vehicleEventId.isEmpty {
                    _ = sendESPCommand(
                        VehicleCommand(action: .eventAck, ownerTarget: state.vehicleEventId),
                        to: deviceID
                    )
                }
                lastStateAt[deviceID] = Date()
                return
            }

            if state.vehicleEventType == "engine_started_obd", (previous?.rpm ?? 0) > 300 {
                if !state.vehicleEventId.isEmpty {
                    _ = sendESPCommand(
                        VehicleCommand(action: .eventAck, ownerTarget: state.vehicleEventId),
                        to: deviceID
                    )
                }
                lastStateAt[deviceID] = Date()
                return
            }

            // BLE event delivery works without Internet. The ESP keeps this
            // event in NVS and replays it until this iPhone acknowledges it.
            let accepted = VehicleNotificationService.shared.notifyVehicleEvent(
                id: state.vehicleEventId,
                type: state.vehicleEventType,
                text: state.vehicleEventText,
                vehicleName: "JOURNEY"
            )
            if accepted, !state.vehicleEventId.isEmpty {
                _ = sendESPCommand(
                    VehicleCommand(action: .eventAck, ownerTarget: state.vehicleEventId),
                    to: deviceID
                )
            }
            lastStateAt[deviceID] = Date()
            return
        }

        if state.ownerStatePacket {
            var merged = previous ?? VehicleState()
            merged.online = bluetooth.isConnected(to: deviceID) || state.online
            merged.trustedPhoneConfigured = state.trustedPhoneConfigured
            merged.authorizedPhoneCount = state.authorizedPhoneCount
            merged.ownerAdminPhone = state.ownerAdminPhone
            merged.pendingOwnerPhone = state.pendingOwnerPhone
            merged.lastEvent = state.lastEvent
            merged.uptimeSeconds = state.uptimeSeconds
            merged.ownerStateKnown = true
            if let rssi = bluetoothRSSIByDevice[deviceID] { merged.bluetoothRSSI = rssi }
            vehicles[deviceID] = merged
            persistOwnerState(merged, for: deviceID)
            lastStateAt[deviceID] = Date()
            return
        }

        if state.partialState, var merged = previous {
            // v12.38: partial packets are typed. A keyless/core packet must never
            // erase OBD telemetry, and an OBD packet must never erase keyless state.
            if state.coreStatePacket {
                merged.online = bluetooth.isConnected(to: deviceID) || state.online
                merged.remotePowered = state.remotePowered
                // v12.51: some compact core packets can arrive while rp is stale/omitted.
                // The ESP event is authoritative for the real BD140 output, so keep
                // the remote-power button green from *_on until *_off.
                switch state.lastEvent {
                case "remote_power_on", "remote_power_actual_on":
                    merged.remotePowered = true
                case "remote_power_off", "remote_power_actual_off":
                    merged.remotePowered = false
                default:
                    break
                }
                merged.simulatedLocked = state.simulatedLocked
                merged.simulatedDoorsOpen = state.simulatedDoorsOpen
                merged.simulatedEngineRunning = state.simulatedEngineRunning
                merged.feedbackLock = state.feedbackLock
                merged.feedbackUnlock = state.feedbackUnlock
                merged.feedbackStart = state.feedbackStart
                merged.feedbackAlarm = state.feedbackAlarm
                // Keep event-driven feedback authoritative. Compact packets from
                // older firmware omit these booleans and otherwise clear feedback instantly.
                if !state.lastEvent.isEmpty && state.lastEvent != "waiting" { merged.lastEvent = state.lastEvent }
            } else if state.obdTelemetryPacket {
                merged.obdConnected = state.obdConnected
                merged.obdStatus = state.obdStatus
                merged.obdResponseRate = state.obdResponseRate
                merged.obdTotalResponses = state.obdTotalResponses
                merged.obdScanProgress = state.obdScanProgress
                merged.obdScannedPids = state.obdScannedPids
                merged.obdSupportedPids = state.obdSupportedPids
                merged.obdStandardScanComplete = state.obdStandardScanComplete
                merged.obdCurrentPid = state.obdCurrentPid
                if !state.obdAdapterName.isEmpty { merged.obdAdapterName = state.obdAdapterName }
                // Zero is a real live value for RPM/speed; never discard it.
                merged.rpm = state.rpm
                merged.speedKph = state.speedKph
                merged.coolantC = state.coolantC
                merged.fuelLevelPercent = state.fuelLevelPercent
                merged.fuelLevelValid = state.fuelLevelValid
                if state.batteryVoltage > 0 { merged.batteryVoltage = state.batteryVoltage }
                merged.canAwake = state.canAwake
                merged.ignitionState = state.ignitionState
                merged.simulatedEngineRunning = state.rpm > 0 && state.canAwake
            } else {
                // Discovery-only partial packets.
                if state.obdDiscoveryKind == "BLE" {
                    if state.obdDiscoveryReset { merged.obdDiscoveredAdapters = "" }
                    if !state.obdDiscoveredAdapters.isEmpty {
                        let current = Set(merged.obdDiscoveredAdapters.components(separatedBy: " | ").filter { !$0.isEmpty })
                        let additions = state.obdDiscoveredAdapters.components(separatedBy: " | ").filter { !$0.isEmpty && !current.contains($0) }
                        if !additions.isEmpty {
                            if !merged.obdDiscoveredAdapters.isEmpty { merged.obdDiscoveredAdapters += " | " }
                            merged.obdDiscoveredAdapters += additions.joined(separator: " | ")
                        }
                    }
                } else if state.obdDiscoveryKind == "WIFI" {
                    if state.obdDiscoveryReset { merged.obdDiscoveredWifiNetworks = "" }
                    if !state.obdDiscoveredWifiNetworks.isEmpty { merged.obdDiscoveredWifiNetworks = state.obdDiscoveredWifiNetworks }
                }
            }
            if let rssi = bluetoothRSSIByDevice[deviceID] { merged.bluetoothRSSI = rssi }
            vehicles[deviceID] = merged
            lastStateAt[deviceID] = Date()
            // v12.51: keyless/core updates are partial packets too. They previously
            // returned before notification processing, so approach/departure events
            // were visible in state but produced no local notification.
            if state.coreStatePacket {
                VehicleNotificationService.shared.notifyChanges(
                    from: previous,
                    to: merged,
                    vehicleName: "JOURNEY"
                )
            }
            return
        }

        var merged = state
        // Every non-partial ESP/MQTT state is authoritative for owner fields.
        merged.ownerStateKnown = true
        if let rssi = bluetoothRSSIByDevice[deviceID] { merged.bluetoothRSSI = rssi }
        vehicles[deviceID] = merged
        persistOwnerState(merged, for: deviceID)
        lastStateAt[deviceID] = Date()
        VehicleNotificationService.shared.notifyChanges(
            from: previous,
            to: merged,
            vehicleName: "JOURNEY"
        )
    }

    private func ownerCacheKey(for deviceID: String) -> String {
        "journey.owner.snapshot.\(deviceID)"
    }

    private func persistOwnerState(_ state: VehicleState, for deviceID: String) {
        let snapshot = OwnerSnapshot(
            trustedPhoneConfigured: state.trustedPhoneConfigured,
            authorizedPhoneCount: state.authorizedPhoneCount,
            ownerAdminPhone: state.ownerAdminPhone,
            pendingOwnerPhone: state.pendingOwnerPhone,
            uptimeSeconds: state.uptimeSeconds
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: ownerCacheKey(for: deviceID))
        }
    }

    private func cachedOwnerState(for deviceID: String) -> VehicleState? {
        guard let data = defaults.data(forKey: ownerCacheKey(for: deviceID)),
              let snapshot = try? JSONDecoder().decode(OwnerSnapshot.self, from: data)
        else { return nil }
        var state = VehicleState()
        state.trustedPhoneConfigured = snapshot.trustedPhoneConfigured
        state.authorizedPhoneCount = snapshot.authorizedPhoneCount
        state.ownerAdminPhone = snapshot.ownerAdminPhone
        state.pendingOwnerPhone = snapshot.pendingOwnerPhone
        state.uptimeSeconds = snapshot.uptimeSeconds ?? 0
        state.ownerStateKnown = true
        return state
    }

    private func restoreCachedOwnerStateIfNeeded(for deviceID: String) {
        guard vehicles[deviceID] == nil, let cached = cachedOwnerState(for: deviceID) else { return }
        vehicles[deviceID] = cached
    }

    func stateAge(for deviceID: String) -> TimeInterval? {
        lastStateAt[deviceID].map { Date().timeIntervalSince($0) }
    }

    private func record(_ action: BenchAction) {
        commandHistory.insert(BenchEvent(action: action), at: 0)
        commandHistory = Array(commandHistory.prefix(20))
    }

    private func readPassword() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    private func savePassword(_ password: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: passwordAccount
        ]
        SecItemDelete(base as CFDictionary)
        guard !password.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
