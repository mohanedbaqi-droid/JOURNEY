import CocoaMQTT
import Combine
import Foundation
import Security

@MainActor
final class MQTTService: ObservableObject {
    enum Connection: String {
        case notConfigured, disconnected, connecting, connected

        var title: String {
            switch self {
            case .notConfigured: return JL("غير مهيأ", "Not configured")
            case .disconnected: return JL("غير متصل", "Disconnected")
            case .connecting: return JL("جاري الاتصال", "Connecting")
            case .connected: return JL("متصل", "Connected")
            }
        }
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
    @Published private(set) var pendingRemotePower: [String: Bool] = [:]
    private var remotePowerUpdates: [String: Int] = [:]
    private var lastFeedbackAt: [String: Date] = [:]

    /// Confirm a fresh ESP power report; a BLE write alone is not GPIO feedback.
    @MainActor
    func setRemotePower(_ enabled: Bool, for deviceID: String) async -> Bool {
        guard pendingRemotePower[deviceID] == nil else { return false }
        let baseline = remotePowerUpdates[deviceID, default: 0]
        pendingRemotePower[deviceID] = enabled
        defer { pendingRemotePower.removeValue(forKey: deviceID) }
        guard send(enabled ? .remotePowerOn : .remotePowerOff, to: deviceID) else { return false }
        for _ in 0..<30 {
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return false }
            if remotePowerUpdates[deviceID, default: 0] > baseline,
               vehicles[deviceID]?.remotePowered == enabled {
                lastError = nil
                return true
            }
            if vehicles[deviceID]?.lastEvent == "rejected_unknown_phone" {
                lastError = JL("هذا الآيفون غير مسجّل كمالك على ESP. سجّله من أجهزة المالك.", "This iPhone is not registered as an ESP owner. Register it in Owner devices.")
                return false
            }
        }
        lastError = JL("وصل طلب طاقة الريموت لمسار الاتصال، لكن ESP لم يؤكد تغيير الحالة. راجع الاتصال وإصدار ESP.", "The remote power request was sent, but ESP did not confirm the state change. Check the connection and ESP firmware.")
        return false
    }
    @Published private(set) var lastStateAt: [String: Date] = [:]
    @Published private(set) var commandHistory: [BenchEvent] = []
    @Published private(set) var bluetoothStatus = JL("غير متصل", "Disconnected")
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
                for (deviceID, feedbackAt) in self.lastFeedbackAt where now.timeIntervalSince(feedbackAt) > 1.5 {
                    guard var state = self.vehicles[deviceID] else { continue }
                    if state.feedbackLock || state.feedbackUnlock || state.feedbackStart || state.feedbackAlarm {
                        state.feedbackLock = false
                        state.feedbackUnlock = false
                        state.feedbackStart = false
                        state.feedbackAlarm = false
                        self.vehicles[deviceID] = state
                    }
                }
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
                    // Keep the car online through either route:
                    // nearby BLE, or fresh ESP->MQTT cloud telemetry over Wi-Fi.
                    if self.bluetooth.isConnected(to: deviceID) {
                        if var state = self.vehicles[deviceID], !state.online {
                            state.online = true
                            self.vehicles[deviceID] = state
                        }
                        continue
                    }
                    guard var state = self.vehicles[deviceID], state.online else { continue }
                    state.online = false
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
            lastError = JL("أدخل إعدادات MQTT أولاً", "Enter MQTT settings first")
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
                    self.lastError = JL("رفض خادم MQTT الاتصال: \(ack)", "MQTT server refused connection: \(ack)")
                }
            }
        }

        mqtt.didReceiveMessage = { [weak self] _, message, _ in
            let parts = message.topic.split(separator: "/")
            guard !message.retained, parts.count == 3,
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

    private func cloudPathAvailable(for deviceID: String) -> Bool {
        guard connection == .connected, client != nil,
              let state = vehicles[deviceID],
              state.cloudConnected,
              let seenAt = lastStateAt[deviceID],
              Date().timeIntervalSince(seenAt) <= 6.0
        else { return false }
        return true
    }

    private func isKeylessAction(_ action: BenchAction) -> Bool {
        switch action {
        case .keylessUnlock, .keylessLock, .keylessPresence, .keylessConfig:
            return true
        default:
            return false
        }
    }

    private var connectionPriorityOrder: [String] {
        let raw = defaults.string(forKey: "journey.settings.connectionPriority") ?? "CELLULAR,WIFI,BLE"
        let parsed = raw.split(separator: ",").map { String($0) }
        let allowed = ["BLE", "CELLULAR", "WIFI"]
        let clean = parsed.filter { allowed.contains($0) }
        return clean.count == 3 && Set(clean).count == 3 ? clean : ["CELLULAR", "WIFI", "BLE"]
    }

    private func cloudRouteMatches(_ route: String, deviceID: String) -> Bool {
        guard cloudPathAvailable(for: deviceID), let state = vehicles[deviceID] else { return false }
        return state.internetRoute == route
    }

    @discardableResult
    private func sendByConfiguredPriority(_ command: VehicleCommand, to deviceID: String) -> Bool {
        // Keyless remains BLE-first regardless of the configurable order.
        if isKeylessAction(command.action) || command.action == .remotePowerOn || command.action == .remotePowerOff {
            if bluetooth.isConnected(to: deviceID), bluetooth.send(command, to: deviceID) {
                lastCommand = command.action
                lastCommandAt = Date()
                record(command.action)
                lastError = nil
                return true
            }
            if publishCloud(command, to: deviceID) { return true }
            return false
        }

        for route in connectionPriorityOrder {
            switch route {
            case "BLE":
                if bluetooth.isConnected(to: deviceID), bluetooth.send(command, to: deviceID) {
                    lastCommand = command.action
                    lastCommandAt = Date()
                    record(command.action)
                    lastError = nil
                    return true
                }
            case "CELLULAR", "WIFI":
                if cloudRouteMatches(route, deviceID: deviceID), publishCloud(command, to: deviceID) {
                    return true
                }
            default:
                break
            }
        }

        // If the configured Internet route has just changed but state has not
        // caught up yet, use any confirmed cloud path before giving up.
        if publishCloud(command, to: deviceID) { return true }
        if bluetooth.isConnected(to: deviceID), bluetooth.send(command, to: deviceID) {
            lastCommand = command.action
            lastCommandAt = Date()
            record(command.action)
            lastError = nil
            return true
        }
        return false
    }

    func saveConnectionPriority(_ order: [String], to deviceID: String) -> Bool {
        guard order.count == 3, Set(order) == Set(["BLE", "CELLULAR", "WIFI"]) else {
            lastError = JL("ترتيب الاتصال غير صحيح", "Invalid connection order")
            return false
        }
        defaults.set(order.joined(separator: ","), forKey: "journey.settings.connectionPriority")
        let command = VehicleCommand(
            action: .connectionPriority,
            connectionPriority: ESPConnectionPriority(order: order)
        )
        return sendByConfiguredPriority(command, to: deviceID)
    }

    @discardableResult
    private func publishCloud(_ command: VehicleCommand, to deviceID: String) -> Bool {
        guard cloudPathAvailable(for: deviceID), let client else { return false }
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
        let command = VehicleCommand(action: action)
        if sendByConfiguredPriority(command, to: deviceID) { return true }
        lastError = JL("لا يوجد مسار اتصال متاح حسب الأولوية المحددة", "No connection route is available in the selected order")
        return false
    }

    /// Saves the desired smart-entry behaviour in the ESP32.  The ESP32 must
    /// still enforce authenticated BLE and its own RSSI calibration.
    @discardableResult
    func sendKeylessConfig(_ config: KeylessEntryConfig, to deviceID: String) -> Bool {
        bluetooth.configureKeyless(config, for: deviceID)
        let command = VehicleCommand(action: .keylessConfig, keyless: config)

        // Keyless configuration remains BLE-first by design.
        if bluetooth.isConnected(to: deviceID), bluetooth.send(command, to: deviceID) {
            lastCommand = .keylessConfig
            lastCommandAt = Date()
            record(.keylessConfig)
            lastError = nil
            return true
        }
        if publishCloud(command, to: deviceID) { return true }

        lastError = JL("تعذر إرسال إعدادات الدخول الذكي", "Could not send smart entry settings")
        return false
    }

    @discardableResult
    func sendESPSettings(_ settings: ESPRuntimeSettings, to deviceID: String) -> Bool {
        sendESPCommand(VehicleCommand(action: .espSettings, espSettings: settings), to: deviceID)
    }

    @discardableResult
    func sendFirmwareURL(_ url: String, to deviceID: String) -> Bool {
        sendESPCommand(VehicleCommand(action: .otaURL, firmwareURL: url), to: deviceID)
    }

    @discardableResult
    func sendESPCommand(_ command: VehicleCommand, to deviceID: String) -> Bool {
        if sendByConfiguredPriority(command, to: deviceID) {
            applyLocal(command.action, to: deviceID)
            return true
        }
        lastError = JL("تعذر الاتصال بـ ESP حسب الأولوية المحددة", "Could not connect to ESP using the selected order")
        return false
    }

    /// v12.37: commands never fake vehicle/remote state locally.
    /// The ESP state packet is authoritative, so the key icon and notifications
    /// change only when the real remote-power GPIO changes on the ESP.
    private func applyLocal(_ action: BenchAction, to deviceID: String) {
        // v12.38: intentionally no optimistic UI mutation. The ESP is the only
        // source of truth for connection, remote power and button feedback.
    }

    func isButtonActive(_ button: String, for deviceID: String) -> Bool {
        // A local tap or old event name cannot prove an active ESP output.
        guard let state = vehicles[deviceID], state.online,
              let receivedAt = lastFeedbackAt[deviceID],
              Date().timeIntervalSince(receivedAt) <= 1.5 else { return false }
        if let state = vehicles[deviceID] {
            switch button {
            case "lock": if state.feedbackLock { return true }
            case "unlock": if state.feedbackUnlock { return true }
            case "start": if state.feedbackStart { return true }
            case "alarm": if state.feedbackAlarm { return true }
            default: break
            }
        }
        return false
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
        if state.feedbackStatePresent && (!state.partialState || state.coreStatePacket) {
            lastFeedbackAt[deviceID] = Date()
        }
        if state.remotePowerStatePresent && (!state.partialState || state.coreStatePacket) {
            remotePowerUpdates[deviceID, default: 0] += 1
        }
        let previous = vehicles[deviceID] ?? cachedOwnerState(for: deviceID)
        // Capture button edges before lastEvent is replaced by the following core packet.

        if state.vehicleEventPacket {

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
                if state.remotePowerStatePresent {
                    merged.remotePowered = state.remotePowered
                }
                // v12.51: some compact core packets can arrive while rp is stale/omitted.
                // The ESP event is authoritative for the real BD140 output, so keep
                // the remote-power button green from *_on until *_off.
                switch state.remotePowerStatePresent ? "" : state.lastEvent {
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
                // v12.66 body state is decoded by ESP from confirmed Journey CAN IDs.
                merged.bcmStateValid = state.bcmStateValid
                if state.bcmStateValid {
                    merged.headlightsOn = state.headlightsOn
                    merged.leftSignalOn = state.leftSignalOn
                    merged.rightSignalOn = state.rightSignalOn
                }
                merged.feedbackLock = state.feedbackLock
                merged.feedbackUnlock = state.feedbackUnlock
                merged.feedbackStart = state.feedbackStart
                merged.feedbackAlarm = state.feedbackAlarm
                // Keep event-driven feedback authoritative. Compact packets from
                // older firmware omit these booleans and otherwise clear feedback instantly.
                if !state.lastEvent.isEmpty && state.lastEvent != "waiting" { merged.lastEvent = state.lastEvent }
            } else if state.cellularStatePacket {
                merged.cellularEnabled = state.cellularEnabled
                merged.cellularRegistered = state.cellularRegistered
                merged.cellularDataAttached = state.cellularDataAttached
                merged.cellularAPN = state.cellularAPN
                merged.cellularNetwork = state.cellularNetwork
                merged.cellularSignalDBm = state.cellularSignalDBm
                merged.cellularStatus = state.cellularStatus
                merged.hotspotEnabled = state.hotspotEnabled
                merged.hotspotRunning = state.hotspotRunning
                merged.hotspotSSID = state.hotspotSSID
                merged.internetRoute = state.internetRoute
            } else if state.wifiStatePacket {
                merged.wifiEnabled = state.wifiEnabled
                merged.wifiConnected = state.wifiConnected
                if !state.wifiSSID.isEmpty { merged.wifiSSID = state.wifiSSID }
                merged.wifiRSSI = state.wifiRSSI
                merged.wifiIP = state.wifiIP
                merged.wifiStatus = state.wifiStatus
                merged.cloudConnected = state.cloudConnected
                if !state.otaAddress.isEmpty || !state.wifiConnected { merged.otaAddress = state.otaAddress }
                if state.wifiDiscoveryReset { merged.wifiDiscoveredNetworks = "" }
                if !state.wifiDiscoveredNetworks.isEmpty {
                    let current = Set(merged.wifiDiscoveredNetworks.components(separatedBy: " | ").filter { !$0.isEmpty })
                    let additions = state.wifiDiscoveredNetworks.components(separatedBy: " | ").filter { !$0.isEmpty && !current.contains($0) }
                    if !additions.isEmpty {
                        if !merged.wifiDiscoveredNetworks.isEmpty { merged.wifiDiscoveredNetworks += " | " }
                        merged.wifiDiscoveredNetworks += additions.joined(separator: " | ")
                    }
                }
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
        // A fresh full state received from the broker proves the ESP is reachable
        // through the Internet even when BLE is out of range.
        if connection == .connected && !bluetooth.isConnected(to: deviceID) {
            merged.online = true
            merged.cloudConnected = true
        }
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
