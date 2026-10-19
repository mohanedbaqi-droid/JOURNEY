import CocoaMQTT
import Combine
import Foundation
import Security

@MainActor
final class MQTTService: ObservableObject {
    static let shared = MQTTService()
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
    private var remotePowerRejections: [String: Int] = [:]
    private var lastFullAt: [String: Date] = [:]
    private var lastHealthAt: [String: Date] = [:]
    private var lastObdAt: [String: Date] = [:]
    private var lastBodyAt: [String: Date] = [:]
    private var lastFeedbackAt: [String: Date] = [:]

    /// Confirm a fresh ESP power report; a BLE write alone is not GPIO feedback.
    @MainActor
    func setRemotePower(_ enabled: Bool, for deviceID: String) async -> Bool {
        guard pendingRemotePower[deviceID] == nil else { return false }
        let baseline = remotePowerUpdates[deviceID, default: 0]
        let rejectionBaseline = remotePowerRejections[deviceID, default: 0]
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
            if remotePowerRejections[deviceID, default: 0] > rejectionBaseline {
                lastError = JL("هذا الآيفون غير مسجّل كمالك على ESP. سجّله من أجهزة المالك.", "This iPhone is not registered as an ESP owner. Register it in Owner devices.")
                return false
            }
        }
        lastError = JL("وصل طلب طاقة الريموت لمسار الاتصال، لكن ESP لم يؤكد تغيير الحالة. راجع الاتصال وإصدار ESP.", "The remote power request was sent, but ESP did not confirm the state change. Check the connection and ESP firmware.")
        return false
    }
    @Published private(set) var lastStateAt: [String: Date] = [:]
    // Only broker-delivered telemetry proves the cloud route; BLE packets do not.
    private var lastCloudStateAt: [String: Date] = [:]
    // Distinguish fresh Internet data from local BLE presence during field tests.
    func cloudTelemetryAge(for deviceID: String) -> TimeInterval? {
        lastCloudStateAt[deviceID].map { Date().timeIntervalSince($0) }
    }
    // KR20: finite, on-demand MQTT diagnostic transfer. No background logging controls.
    @Published private(set) var fullDiagnosticReport = ""
    @Published private(set) var diagnosticTransferStatus = ""
    @Published private(set) var diagnosticTransferBusy = false
    private var diagnosticSequence: Int?
    private var diagnosticExpectedChunks = 0
    private var diagnosticChunks: [Int: Data] = [:]
    private var diagnosticDeviceID: String?
    private var diagnosticStartedAt: Date?

    @discardableResult
    func requestFullDiagnostics(for deviceID: String) -> Bool {
        requestFullDiagnostics(for: deviceID, via: .cloud)
    }

    enum DiagnosticRoute { case cloud, bluetooth }

    func requestFullDiagnostics(for deviceID: String, via route: DiagnosticRoute) -> Bool {
        guard !diagnosticTransferBusy else { return false }
        let useBLE = bluetooth.isConnected(to: deviceID)
        guard (route == .bluetooth && useBLE) || (route == .cloud && connection == .connected) else {
            diagnosticTransferStatus = route == .bluetooth
                ? JL("اتصل بالـ ESP عبر البلوتوث أولاً", "Connect to ESP over Bluetooth first")
                : JL("اتصل بالسيرفر عبر الإنترنت أولاً", "Connect to the MQTT server first")
            return false
        }
        diagnosticDeviceID = deviceID
        diagnosticSequence = nil
        diagnosticExpectedChunks = 0
        diagnosticChunks.removeAll()
        fullDiagnosticReport = ""
        diagnosticStartedAt = Date()
        diagnosticTransferBusy = true
        diagnosticTransferStatus = route == .cloud
            ? JL("بانتظار التشخيص عبر الإنترنت…", "Waiting for Internet diagnostics…")
            : JL("بانتظار التشخيص عبر البلوتوث…", "Waiting for Bluetooth diagnostics…")
        // Full diagnostics use MQTT first; BLE is the offline fallback.
        let request = VehicleCommand(action: .espDiagnostics, diagnosticSince: 0)
        if connection == .connected, let client {
            subscribeToSelectedVehicle(using: client)
        }
        let sentViaCloud = route == .cloud && connection == .connected &&
            publishCloud(request, to: deviceID)
        let sentViaBLE = route == .bluetooth && useBLE &&
            bluetooth.send(request, to: deviceID)
        if sentViaBLE || sentViaCloud {
            // A lost MQTT chunk must not leave the download spinner running forever.
            let startedAt = diagnosticStartedAt
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(90))
                guard let self, self.diagnosticTransferBusy,
                      self.diagnosticStartedAt == startedAt else { return }
                self.diagnosticTransferBusy = false
                self.diagnosticTransferStatus = JL("انتهت مهلة السحب؛ الملف غير مكتمل. اضغط سحب التشخيص لإعادة المحاولة.",
                                                   "Download timed out; incomplete file discarded. Tap again to retry.")
                self.diagnosticChunks.removeAll()
                self.diagnosticExpectedChunks = 0
            }
            return true
        }
        diagnosticTransferBusy = false
        diagnosticTransferStatus = JL("تعذر إرسال طلب التشخيص", "Could not request diagnostics")
        return false
    }

    private func receiveDiagnosticChunk(_ payload: String, deviceID: String) {
        guard diagnosticTransferBusy, diagnosticDeviceID == deviceID,
              let bytes = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let sequence = json["ds"] as? Int, let index = json["di"] as? Int,
              let count = json["dn"] as? Int, let hex = json["dx"] as? String,
              count > 0, count <= 512, index >= 0, index < count,
              hex.count <= 96, hex.count.isMultiple(of: 2)
        else { return }
        if diagnosticSequence == nil {
            diagnosticSequence = sequence
            diagnosticExpectedChunks = count
        }
        guard diagnosticSequence == sequence, diagnosticExpectedChunks == count else { return }
        var chunk = Data()
        let chars = Array(hex.utf8)
        for offset in stride(from: 0, to: chars.count, by: 2) {
            func nibble(_ c: UInt8) -> UInt8? {
                switch c {
                case 48...57: return c - 48
                case 65...70: return c - 55
                case 97...102: return c - 87
                default: return nil
                }
            }
            guard let hi = nibble(chars[offset]), let lo = nibble(chars[offset + 1]) else { return }
            chunk.append((hi << 4) | lo)
        }
        if diagnosticChunks[index] == nil { diagnosticChunks[index] = chunk }
        diagnosticTransferStatus = JL("استلام التشخيص", "Receiving diagnostics") +
            " \(diagnosticChunks.count)/\(count)"
        guard diagnosticChunks.count == count else { return }
        var result = Data()
        for i in 0..<count {
            guard let part = diagnosticChunks[i] else { return }
            result.append(part)
        }
        fullDiagnosticReport = String(decoding: result, as: UTF8.self)
        diagnosticTransferBusy = false
        diagnosticTransferStatus = JL("اكتمل استلام التشخيص", "Diagnostics received successfully")
    }

    @Published private(set) var commandHistory: [BenchEvent] = []
    @Published private(set) var bluetoothStatus = JL("غير متصل", "Disconnected")
    // v12.52: independent real ESP button feedback. Do not use lastEvent because
    // the ESP immediately follows remote_button_*_on with lock/unlock/horn/etc.
    @Published private(set) var buttonFeedback: [String: Set<String>] = [:]

    private var client: CocoaMQTT?
    private var subscribedCloudDeviceID: String?
    private let bluetooth = BluetoothVehicleService()
    private let defaults = UserDefaults.standard
    private let passwordAccount = "mqtt-password"
    private var bluetoothRSSIByDevice: [String: Int] = [:]
    private var feedbackGeneration: [String: UUID] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init() {
        bluetooth.onDiagnosticChunk = { [weak self] deviceID, payload in
            Task { @MainActor in
                self?.receiveDiagnosticChunk(payload, deviceID: deviceID)
            }
        }
        bluetooth.onState = { [weak self] deviceID, state in
            Task { @MainActor in
                // BLE packets are local only; they must not refresh the MQTT freshness clock.
                self?.receive(state, from: deviceID, transport: .ble)
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
                defer { self.syncSelectedWidget() }
                for (deviceID, seenAt) in self.lastHealthAt where now.timeIntervalSince(seenAt) > 10 {
                    guard var state = self.vehicles[deviceID] else { continue }
                    state.espTemperatureC = nil; state.espBatteryVoltage = nil; state.espBatteryPercent = nil
                    state.espThermalLevel = -1
                    self.vehicles[deviceID] = state
                }
                for (deviceID, seenAt) in self.lastObdAt where now.timeIntervalSince(seenAt) > 12 {
                    guard var state = self.vehicles[deviceID] else { continue }
                    state.rpmValid = false; state.speedValid = false; state.coolantValid = false
                    state.simulatedEngineRunning = false
                    self.vehicles[deviceID] = state
                }
                for (deviceID, seenAt) in self.lastBodyAt where now.timeIntervalSince(seenAt) > 12 {
                    guard var state = self.vehicles[deviceID] else { continue }
                    state.doorsValid = false; state.lightsValid = false; state.turnsValid = false
                    state.leftSignalOn = false; state.rightSignalOn = false; state.headlightsOn = false
                    state.canLockValid = false
                    self.vehicles[deviceID] = state
                }
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
                for (deviceID, seenAt) in self.lastStateAt where now.timeIntervalSince(seenAt) > 4.0 {
                    // Do not mark offline when the broker still delivers fresh 4G/Wi-Fi state.
                    let cloudFresh = self.connection == .connected &&
                        self.lastCloudStateAt[deviceID].map { now.timeIntervalSince($0) <= 12.0 } == true
                    if self.bluetooth.isConnected(to: deviceID) || cloudFresh {
                        if var state = self.vehicles[deviceID], !state.online {
                            state.online = true
                            self.vehicles[deviceID] = state
                        }
                        continue
                    }
                    guard var state = self.vehicles[deviceID], state.online else { continue }
                    // Connectivity loss is not a vehicle event. Preserve the last
                    // known engine and event state until fresh ESP telemetry arrives.
                    // Otherwise transient BLE/MQTT handoffs create false alerts.
                    state.online = false
                    self.vehicles[deviceID] = state
                }
            }
            .store(in: &cancellables)
    }

    func syncSelectedWidget(force: Bool = false) {
        if defaults.bool(forKey: "journey.demo.enabled") {
            // Reconcile lock/unlock AppIntents that ran in the widget
            // extension before replacing the shared demo snapshot.
            JourneyWidgetStore.reconcilePendingDemoLock()
            let d = defaults
            var snapshot = JourneyWidgetSnapshot()
            snapshot.demoMode = true
            snapshot.name = "JOURNEY DEMO"
            snapshot.deviceID = "journey-demo"
            snapshot.english = d.string(forKey: "journey.settings.language") == "en"
            snapshot.speedUnit = d.string(forKey: "journey.settings.speedUnit") ?? "kmh"
            snapshot.temperatureUnit = d.string(forKey: "journey.settings.temperatureUnit") ?? "c"
            snapshot.online = true
            snapshot.locked = (d.object(forKey: "journey.demo.locked") as? Bool) ?? true
            snapshot.rpm = d.bool(forKey: "journey.demo.engine") ? 850 : 0
            snapshot.speed = 0
            snapshot.coolant = 86
            snapshot.fuel = 65
            snapshot.battery = 12.6
            snapshot.espTemperature = 36
            snapshot.espBattery = 85
            snapshot.doorKnownMask = 2 | 4 | 8 | 16 | 32 | 64
            for (key, bit) in [
                ("journey.demo.driverDoor", 2),
                ("journey.demo.passengerDoor", 4),
                ("journey.demo.rearDriverDoor", 8),
                ("journey.demo.rearPassengerDoor", 16),
                ("journey.demo.hood", 32),
                ("journey.demo.trunk", 64)
            ] where d.bool(forKey: key) {
                snapshot.doorOpenMask |= bit
            }
            snapshot.lowBeam = d.bool(forKey: "journey.demo.headlights")
            snapshot.parking = snapshot.lowBeam
            snapshot.leftTurn = d.bool(forKey: "journey.demo.leftTurn")
            snapshot.rightTurn = d.bool(forKey: "journey.demo.rightTurn")
            snapshot.remotePowered = true
            snapshot.firmware = "DEMO"
            // Demo data must never expire as if it were live vehicle telemetry.
            // Update the timestamp only when the simulated values change.
            let previous = JourneyWidgetStore.read()
            if let previous, previous.demoMode {
                var comparison = snapshot
                comparison.stateAt = previous.stateAt
                comparison.obdAt = previous.obdAt
                comparison.bodyAt = previous.bodyAt
                comparison.healthAt = previous.healthAt
                if comparison == previous {
                    JourneyLiveActivityService.shared.refresh(previous)
                    JourneyWatchBridge.shared.publish(previous)
                    _ = JourneyWidgetStore.write(previous, force: force)
                    return
                }
            }
            snapshot.stateAt = Date()
            snapshot.obdAt = snapshot.stateAt
            snapshot.bodyAt = snapshot.stateAt
            snapshot.healthAt = snapshot.stateAt
            JourneyLiveActivityService.shared.refresh(snapshot)
            JourneyWatchBridge.shared.publish(snapshot)
            _ = JourneyWidgetStore.write(snapshot, force: force)
            return
        }
        let devices = DeviceStore()
        guard let device = devices.selectedDevice else {
            JourneyLiveActivityService.shared.refresh(JourneyWidgetSnapshot())
            JourneyWatchBridge.shared.publish(JourneyWidgetSnapshot())
            _ = JourneyWidgetStore.write(JourneyWidgetSnapshot(), force: true)
            return
        }
        let state = state(for: device.deviceID)
        var snapshot = JourneyWidgetSnapshot()
        snapshot.deviceID = device.deviceID; snapshot.name = device.name
        snapshot.english = defaults.string(forKey: "journey.settings.language") == "en"
        snapshot.speedUnit = defaults.string(forKey: "journey.settings.speedUnit") ?? "kmh"
        snapshot.temperatureUnit = defaults.string(forKey: "journey.settings.temperatureUnit") ?? "c"
        snapshot.stateAt = lastStateAt[device.deviceID]
        snapshot.obdAt = lastObdAt[device.deviceID]; snapshot.bodyAt = lastBodyAt[device.deviceID]
        snapshot.healthAt = lastHealthAt[device.deviceID]; snapshot.gpsAt = lastFullAt[device.deviceID]
        snapshot.online = state.online
        snapshot.rpm = state.rpmValid ? state.rpm : nil
        snapshot.speed = state.speedValid ? state.speedKph : nil
        snapshot.coolant = state.coolantValid ? state.coolantC : nil
        snapshot.fuel = state.fuelLevelValid ? state.fuelLevelPercent : nil
        snapshot.battery = state.obdConnected && state.batteryVoltage > 0 ? state.batteryVoltage : nil
        snapshot.locked = state.doorsValid ? state.simulatedLocked : nil
        snapshot.doorKnownMask = state.doorsValid ? state.doorKnownMask : 0
        snapshot.doorOpenMask = state.doorsValid ? state.doorOpenMask : 0
        snapshot.lowBeam = state.lightsValid ? state.headlightsOn : nil
        snapshot.parking = state.lightsValid && state.parkingLightsValid ? state.parkingLightsOn : nil
        snapshot.leftTurn = state.turnsValid ? state.leftSignalOn : nil
        snapshot.rightTurn = state.turnsValid ? state.rightSignalOn : nil
        snapshot.remotePowered = state.online ? state.remotePowered : nil
        snapshot.obdConnected = state.obdConnected
        snapshot.espTemperature = state.espTemperatureC; snapshot.espBattery = state.espBatteryPercent
        snapshot.firmware = state.firmwareVersion
        snapshot.latitude = state.gpsValid ? state.latitude : nil; snapshot.longitude = state.gpsValid ? state.longitude : nil
        JourneyLiveActivityService.shared.refresh(snapshot)
        JourneyWatchBridge.shared.publish(snapshot)
        _ = JourneyWidgetStore.write(snapshot, force: force)
    }

    var settings: Settings {
        let savedPort = UInt16(exactly: defaults.integer(forKey: "journey.mqtt.port"))
        return Settings(
            host: defaults.string(forKey: "journey.mqtt.host").flatMap { $0.isEmpty ? nil : $0 } ?? AppConfig.defaultBrokerHost,
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
        guard !UserDefaults.standard.bool(forKey: "journey.demo.enabled") else {
            disconnect()
            return
        }
        let config = settings
        guard isConfigured else {
            connection = .notConfigured
            lastError = JL("أدخل إعدادات MQTT أولاً", "Enter MQTT settings first")
            return
        }

        client?.disconnect()
        subscribedCloudDeviceID = nil
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
                guard let self, self.client === mqtt else { return }
                if ack == .accept {
                    self.connection = .connected
                    self.lastError = nil
                    // Subscribe only to the selected vehicle. EMQX restricts journey_app
                    // to its assigned device topic; a wildcard subscription is denied.
                    self.subscribeToSelectedVehicle(using: mqtt)
                } else {
                    self.connection = .disconnected
                    self.lastError = JL("رفض خادم MQTT الاتصال: \(ack)", "MQTT server refused connection: \(ack)")
                }
            }
        }

        mqtt.didReceiveMessage = { [weak self] _, message, _ in
            let parts = message.topic.split(separator: "/")
            guard !message.retained, parts.count == 4, parts[0] == "journey" else { return }
            if parts[2] == "diagnostics", parts[3] == "chunk", let payload = message.string {
                DispatchQueue.main.async {
                    guard let self, self.client === mqtt else { return }
                    self.receiveDiagnosticChunk(payload, deviceID: String(parts[1]))
                }
                return
            }
            guard parts[2] == "telemetry", parts[3] == "state",
                  let data = message.string?.data(using: .utf8),
                  let state = try? JSONDecoder().decode(VehicleState.self, from: data)
            else { return }
            let deviceID = String(parts[1])
            DispatchQueue.main.async {
                guard let self, self.client === mqtt else { return }
                self.lastCloudStateAt[deviceID] = Date()
                self.receive(state, from: deviceID, transport: .cloud)
            }
        }

        mqtt.didDisconnect = { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.client === mqtt else { return }
                self.connection = .disconnected
                self.lastCloudStateAt.removeAll()
                if let error { self.lastError = error.localizedDescription }
            }
        }

        client = mqtt
        _ = mqtt.connect()
    }

    /// Refresh the cloud telemetry subscription when the selected vehicle changes.
    /// This is also called after every successful MQTT reconnect.
    func refreshVehicleSubscription() {
        guard connection == .connected, let client else { return }
        subscribeToSelectedVehicle(using: client)
    }

    private func subscribeToSelectedVehicle(using mqtt: CocoaMQTT) {
        guard let deviceID = DeviceStore().selectedDevice?.deviceID,
              !deviceID.isEmpty,
              !deviceID.contains("/") && !deviceID.contains("+") && !deviceID.contains("#")
        else {
            lastError = JL("اختَر سيارة صحيحة حتى يتم الاشتراك ببياناتها عبر MQTT",
                           "Select a valid vehicle to subscribe to MQTT telemetry")
            return
        }
        if let previousID = subscribedCloudDeviceID, previousID != deviceID {
            mqtt.unsubscribe("journey/\(previousID)/telemetry/state")
            mqtt.unsubscribe("journey/\(previousID)/diagnostics/chunk")
            lastCloudStateAt.removeValue(forKey: previousID)
        }
        subscribedCloudDeviceID = deviceID
        mqtt.subscribe("journey/\(deviceID)/telemetry/state", qos: .qos1)
        mqtt.subscribe("journey/\(deviceID)/diagnostics/chunk", qos: .qos1)
    }

    /// Demo must suspend the underlying CoreBluetooth session, not just UI commands.
    func setDemoMode(_ enabled: Bool) {
        if enabled {
            bluetooth.suspendForDemo()
            disconnect()
        } else {
            bluetooth.resumeFromDemo()
        }
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        subscribedCloudDeviceID = nil
        lastCloudStateAt.removeAll()
        connection = isConfigured ? .disconnected : .notConfigured
    }

    func state(for deviceID: String) -> VehicleState {
        if let state = vehicles[deviceID] { return state }
        return cachedOwnerState(for: deviceID) ?? VehicleState()
    }

    private func cloudPathAvailable(for deviceID: String) -> Bool {
        // A live authenticated broker session can publish commands even when
        // the ESP telemetry is delayed or temporarily unavailable. Requiring
        // a state packet in the last 12 seconds incorrectly disabled 4G
        // control immediately after the iPhone BLE link dropped.
        guard connection == .connected, client != nil,
              !deviceID.isEmpty,
              !deviceID.contains("/"), !deviceID.contains("+"), !deviceID.contains("#")
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
        let raw = defaults.string(forKey: "journey.settings.connectionPriority") ?? "BLE,CELLULAR"
        let parsed = raw.split(separator: ",").map { String($0) }
        let allowed = ["BLE", "CELLULAR"]
        let clean = parsed.filter { allowed.contains($0) }
        return clean.count == 2 && Set(clean).count == 2 ? clean : ["BLE", "CELLULAR"]
    }

    private func cloudRouteMatches(_ route: String, deviceID: String) -> Bool {
        guard cloudPathAvailable(for: deviceID), let state = vehicles[deviceID] else { return false }
        return state.internetRoute == route
    }

    @discardableResult
    private func sendByConfiguredPriority(_ command: VehicleCommand, to deviceID: String) -> Bool {
        guard !defaults.bool(forKey: "journey.demo.enabled") else { return false }

        // Proximity/keyless presence must stay local to prevent remote presence spoofing.
        if isKeylessAction(command.action) {
            guard bluetooth.isConnected(to: deviceID),
                  bluetooth.send(command, to: deviceID) else { return false }
            lastCommand = command.action
            lastCommandAt = Date()
            record(command.action)
            lastError = nil
            return true
        }

        // Prefer the selected transport when it is actually available.
        // Cellular uses authenticated MQTT; BLE remains local. Wi-Fi is unsupported.
        for route in connectionPriorityOrder {
            if route == "BLE" {
                if bluetooth.isConnected(to: deviceID), bluetooth.send(command, to: deviceID) {
                    lastCommand = command.action
                    lastCommandAt = Date()
                    record(command.action)
                    lastError = nil
                    return true
                }
            } else if cloudRouteMatches(route, deviceID: deviceID) {
                if publishCloud(command, to: deviceID) { return true }
            }
        }
        // Some older ESP firmware omits internetRoute. Permit its fresh MQTT
        // telemetry as fallback, without accepting a stale cached online flag.
        if publishCloud(command, to: deviceID) { return true }
        lastError = JL("لا يوجد اتصال مؤكد بالسيارة عبر الإنترنت أو البلوتوث", "No confirmed vehicle connection over Internet or Bluetooth")
        return false
    }

    func saveConnectionPriority(_ order: [String], to deviceID: String) -> Bool {
        guard order.count == 2, Set(order) == Set(["BLE", "CELLULAR"]) else {
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
        guard !defaults.bool(forKey: "journey.demo.enabled") else { return false }
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
        guard !defaults.bool(forKey: "journey.demo.enabled") else { return }
        restoreCachedOwnerStateIfNeeded(for: deviceID)
        bluetooth.prepareConnection(to: deviceID)
    }

    /// Reconnect immediately when the app returns to the foreground. This is
    /// separate from sending a vehicle command, so the status becomes connected
    /// before the user touches any control.
    func resumeBluetooth(for deviceID: String) {
        guard !defaults.bool(forKey: "journey.demo.enabled") else { return }
        restoreCachedOwnerStateIfNeeded(for: deviceID)
        bluetooth.resumeConnection(to: deviceID)
    }

    @discardableResult
    func send(_ action: BenchAction, to deviceID: String) -> Bool {
        guard !UserDefaults.standard.bool(forKey: "journey.demo.enabled") else { return false }
        let command = VehicleCommand(action: action)
        if sendByConfiguredPriority(command, to: deviceID) { return true }
        lastError = JL("لا يوجد مسار اتصال متاح حسب الأولوية المحددة", "No connection route is available in the selected order")
        return false
    }

    /// Saves the desired smart-entry behaviour in the ESP32.  The ESP32 must
    /// still enforce authenticated BLE and its own RSSI calibration.
    @discardableResult
    func sendKeylessConfig(_ config: KeylessEntryConfig, to deviceID: String) -> Bool {
        guard !UserDefaults.standard.bool(forKey: "journey.demo.enabled") else { return false }
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
        guard !UserDefaults.standard.bool(forKey: "journey.demo.enabled") else { return false }
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

    // Vehicle telemetry is cloud-authoritative. BLE stays a small, independent
    // control plane for owner enrolment, keyless state and local event delivery.
    // Older ESP firmware may still *transmit* telemetry over BLE until updated;
    // the iPhone intentionally does not decode/merge that into the dashboard.
    private enum VehicleTransport { case ble, cloud }

    private func receive(_ state: VehicleState, from deviceID: String, transport: VehicleTransport) {
        if transport == .ble {
            let localControlPacket = state.ownerStatePacket || state.coreStatePacket || state.vehicleEventPacket
            // No dashboard/OBD/body/GPS/health stream from BLE. Preserve the
            // owner's local events and command feedback, even without Internet.
            guard localControlPacket else { return }
        }
        defer { syncSelectedWidget() }
        if !state.partialState { lastFullAt[deviceID] = Date() }
        if state.lastEvent == "rejected_unknown_phone" && (state.coreStatePacket || !state.partialState) {
            remotePowerRejections[deviceID, default: 0] += 1
        }
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

        if state.espHealthPacket {
            var merged = previous ?? VehicleState()
            merged.online = true
            merged.firmwareVersion = state.firmwareVersion
            merged.espTemperatureC = state.espTemperatureC
            merged.espBatteryVoltage = state.espBatteryVoltage
            merged.espBatteryPercent = state.espBatteryPercent
            merged.espTempWarningC = state.espTempWarningC
            merged.espThermalLevel = state.espThermalLevel
            merged.espResetReason = state.espResetReason
            vehicles[deviceID] = merged
            lastHealthAt[deviceID] = Date()
            lastStateAt[deviceID] = Date()
            return
        }
        if !state.partialState { lastHealthAt[deviceID] = Date() }

        if state.ownerStatePacket {
            var merged = previous ?? VehicleState()
            merged.online = bluetooth.isConnected(to: deviceID) || state.online
            // A transient zero-owner packet must not downgrade an existing verified owner.
            // The ESP remains authoritative once a non-empty owner snapshot arrives.
            let previousHasOwner = (previous?.authorizedPhoneCount ?? 0) > 0
            let incomingOwnerEmpty = state.authorizedPhoneCount == 0 && !state.trustedPhoneConfigured
            if !(previousHasOwner && incomingOwnerEmpty) {
                merged.trustedPhoneConfigured = state.trustedPhoneConfigured
                merged.authorizedPhoneCount = state.authorizedPhoneCount
                merged.ownerAdminPhone = state.ownerAdminPhone
            }
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

        // Packet freshness is separate from owner/keyless heartbeat freshness.
        if state.obdTelemetryPacket { lastObdAt[deviceID] = Date() }
        if state.bodyStatePacket { lastBodyAt[deviceID] = Date() }
        if !state.partialState {
            lastObdAt[deviceID] = Date()
            lastBodyAt[deviceID] = Date()
        }

        if state.partialState, var merged = previous {
            // v12.38: partial packets are typed. A keyless/core packet must never
            // erase OBD telemetry, and an OBD packet must never erase keyless state.
            if state.bodyStatePacket {
                lastBodyAt[deviceID] = Date()
                merged.doorOpenMask = state.doorOpenMask; merged.doorKnownMask = state.doorKnownMask
                merged.parkingLightsOn = state.parkingLightsOn; merged.parkingLightsValid = state.parkingLightsValid
                merged.doorsValid = state.doorsValid; merged.lightsValid = state.lightsValid; merged.turnsValid = state.turnsValid
                merged.simulatedDoorsOpen = state.doorsValid && state.simulatedDoorsOpen
                if state.doorsValid { merged.simulatedLocked = state.simulatedLocked }
                merged.canLockValid = state.canLockValid
                merged.canLocked = state.canLockValid && state.canLocked
                merged.headlightsOn = state.lightsValid && state.headlightsOn
                merged.leftSignalOn = state.turnsValid && state.leftSignalOn
                merged.rightSignalOn = state.turnsValid && state.rightSignalOn
                merged.readDiagnostics = state.readDiagnostics
            } else if state.coreStatePacket {
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
                if !merged.doorsValid { merged.simulatedLocked = state.simulatedLocked }
                // Live body/engine fields are owned by their dedicated packets.
                // v12.66 body state is decoded by ESP from confirmed Journey CAN IDs.
                if transport == .cloud {
                    merged.bcmStateValid = state.bcmStateValid
                    if state.bcmStateValid && !merged.turnsValid && !merged.lightsValid {
                        merged.headlightsOn = state.headlightsOn
                        merged.leftSignalOn = state.leftSignalOn
                        merged.rightSignalOn = state.rightSignalOn
                    }
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
                lastObdAt[deviceID] = Date()
                merged.rpmValid = state.rpmValid; merged.coolantValid = state.coolantValid; merged.speedValid = state.speedValid
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
                merged.simulatedEngineRunning = state.rpmValid && state.rpm > 0
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
        // Full telemetry is not always an owner roster. Keep the last verified
        // owner snapshot when the ESP temporarily omits owner fields.
        if merged.authorizedPhoneCount == 0 && !merged.trustedPhoneConfigured,
           let previous, previous.ownerStateKnown, previous.authorizedPhoneCount > 0 {
            merged.authorizedPhoneCount = previous.authorizedPhoneCount
            merged.trustedPhoneConfigured = previous.trustedPhoneConfigured
            merged.ownerAdminPhone = previous.ownerAdminPhone
            merged.pendingOwnerPhone = previous.pendingOwnerPhone
        }
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
        // Never overwrite a verified owner snapshot with a disconnected/default 0/10 packet.
        guard state.ownerStateKnown else { return }
        if state.authorizedPhoneCount == 0,
           let previous = cachedOwnerState(for: deviceID),
           previous.authorizedPhoneCount > 0 { return }
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
