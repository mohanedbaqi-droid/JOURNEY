@preconcurrency import CoreBluetooth
import Combine
import Foundation

final class ProximityMonitor: NSObject, ObservableObject, CBCentralManagerDelegate {
    struct DiscoveredDevice: Identifiable, Hashable {
        let id: UUID
        let deviceID: String
        var rssi: Int
    }

    enum Zone: String {
        case unavailable, near, middle, far

        var title: String {
            switch self {
            case .unavailable: return JL("غير متاح", "Unavailable")
            case .near: return JL("قريب", "Near")
            case .middle: return JL("متوسط", "Medium")
            case .far: return JL("بعيد", "Far")
            }
        }
    }

    @Published private(set) var zone: Zone = .unavailable
    @Published private(set) var averageRSSI: Int?
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []

    private var central: CBCentralManager!
    private var samples: [Int] = []
    private lazy var service = CBUUID(string: AppConfig.bleServiceUUID)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { start() }
        else {
            isScanning = false
            zone = .unavailable
        }
    }

    func start() {
        guard central.state == .poweredOn else { return }
        samples.removeAll()
        discoveredDevices.removeAll()
        central.scanForPeripherals(withServices: [service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    func stop() {
        central.stopScan()
        isScanning = false
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let value = RSSI.intValue
        guard value < 0 && value > -120 else { return }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let detectedID = (advertisedName ?? peripheral.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if detectedID.range(of: "^[A-Za-z0-9_-]{3,40}$", options: .regularExpression) != nil {
            let found = DiscoveredDevice(id: peripheral.identifier, deviceID: detectedID, rssi: value)
            if let index = discoveredDevices.firstIndex(where: { $0.deviceID == detectedID }) {
                discoveredDevices[index] = found
            } else {
                discoveredDevices.append(found)
            }
            discoveredDevices.sort { $0.rssi > $1.rssi }
        }

        samples.append(value)
        if samples.count > 8 { samples.removeFirst() }
        let average = samples.reduce(0, +) / samples.count
        averageRSSI = average

        // RSSI ليس قياس أمتار دقيقاً؛ هذه مناطق عرض تقريبية فقط.
        if average >= -58 { zone = .near }
        else if average >= -75 { zone = .middle }
        else { zone = .far }
    }
}

/// Direct local control transport for the ESP32.  It uses the same JSON
/// command and state payloads as MQTT, so the UI does not need a second set of
/// buttons when the car has no SIM card or data connection.
final class BluetoothVehicleService: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var isReady = false
    @Published private(set) var status = JL("غير متصل", "Disconnected")

    var onState: ((String, VehicleState) -> Void)?
    var onRSSI: ((String, Int) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [String: CBPeripheral] = [:]
    private var deviceIDs: [UUID: String] = [:]
    private var commandCharacteristic: CBCharacteristic?
    private var pending: (command: VehicleCommand, deviceID: String)?
    // Serialize confirmed GATT writes. CoreBluetooth accepts writeValue calls faster
    // than the ESP command task can drain them when OBD connect/discovery is busy.
    private var bleWriteInFlight = false
    private var bleWriteQueue: [Data] = []
    private var preferredDeviceID: String?
    private var keylessConfigs: [String: KeylessEntryConfig] = [:]
    private var nearSince: [String: Date] = [:]
    private var farSince: [String: Date] = [:]
    private var unlockedByKeyless: Set<String> = []
    private var lastPresenceSent: [String: Date] = [:]
    private let defaults = UserDefaults.standard
    private let service = CBUUID(string: AppConfig.bleServiceUUID)
    private let commandUUID = CBUUID(string: AppConfig.bleCommandCharacteristicUUID)
    private let stateUUID = CBUUID(string: AppConfig.bleStateCharacteristicUUID)

    override init() {
        super.init()
        preferredDeviceID = defaults.string(forKey: "journey.ble.preferredDevice")
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.example.JourneyControl.ble"]
        )
    }

    /// Keeps the known Journey ESP32 connected in the background.  iOS can
    /// restore this central manager after it suspends the app normally.
    func prepareConnection(to deviceID: String) {
        preferredDeviceID = deviceID
        defaults.set(deviceID, forKey: "journey.ble.preferredDevice")
        loadKeylessConfig(for: deviceID)
        reconnectPreferredDevice(forceScanFallback: true)
    }

    /// Called whenever the app becomes active again. `onAppear` is not
    /// guaranteed to run when iOS only backgrounds/foregrounds the existing
    /// view hierarchy, so explicitly wake the BLE reconnect path here.
    func resumeConnection(to deviceID: String) {
        preferredDeviceID = deviceID
        defaults.set(deviceID, forKey: "journey.ble.preferredDevice")
        loadKeylessConfig(for: deviceID)
        reconnectPreferredDevice(forceScanFallback: true)
    }

    /// Stores the owner's keyless policy locally. RSSI is evaluated while the
    /// authenticated app keeps a BLE connection to the selected ESP32.
    func configureKeyless(_ config: KeylessEntryConfig, for deviceID: String) {
        keylessConfigs[deviceID] = config
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "journey.keyless.config.\(deviceID)")
        }
        if !config.enabled {
            nearSince[deviceID] = nil
            farSince[deviceID] = nil
            unlockedByKeyless.remove(deviceID)
            lastPresenceSent[deviceID] = nil
        }
    }

    /// Confirms the local ESP command channel is ready, not merely MQTT.
    func isConnected(to deviceID: String) -> Bool {
        guard let peripheral = peripherals[deviceID], peripheral.state == .connected else {
            return false
        }
        return commandCharacteristic != nil
    }

    /// Queues the command while the app connects, then writes it without MQTT.
    @discardableResult
    func send(_ action: BenchAction, to deviceID: String) -> Bool {
        send(VehicleCommand(action: action), to: deviceID)
    }

    /// Sends the same complete JSON envelope used by MQTT, including settings
    /// payloads such as the smart-entry configuration.
    @discardableResult
    func send(_ command: VehicleCommand, to deviceID: String) -> Bool {
        pending = (command, deviceID)
        guard central.state == .poweredOn else {
            status = JL("فعّل البلوتوث", "Enable Bluetooth")
            return false
        }
        if let peripheral = peripherals[deviceID], peripheral.state == .connected,
           let commandCharacteristic {
            write(command, to: peripheral, characteristic: commandCharacteristic)
            return true
        }
        status = JL("جاري اتصال BLE", "Connecting BLE")
        // Reuse the preferred/cached peripheral first. Do not start a second
        // overlapping scan/connect cycle for every button press.
        preferredDeviceID = deviceID
        defaults.set(deviceID, forKey: "journey.ble.preferredDevice")
        reconnectPreferredDevice(forceScanFallback: true)
        return true
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isReady = central.state == .poweredOn
        status = isReady ? JL("جاهز للبلوتوث", "Bluetooth ready") : JL("فعّل البلوتوث", "Enable Bluetooth")
        if isReady { reconnectPreferredDevice(forceScanFallback: true) }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else { return }
        for peripheral in restored {
            guard let deviceID = preferredDeviceID else { continue }
            peripherals[deviceID] = peripheral
            deviceIDs[peripheral.identifier] = deviceID
            peripheral.delegate = self
            if peripheral.state == .connected { peripheral.discoverServices([service]) }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = ((advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wantedID = pending?.deviceID ?? preferredDeviceID
        guard let wantedID, name == wantedID || name == "JOURNEY-\(wantedID)" else { return }
        peripherals[wantedID] = peripheral
        deviceIDs[peripheral.identifier] = wantedID
        defaults.set(peripheral.identifier.uuidString, forKey: "journey.ble.peripheral.\(wantedID)")
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if central.isScanning { central.stopScan() }
        status = JL("BLE متصل", "BLE connected")
        peripheral.discoverServices([service])
        peripheral.readRSSI()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = JL("فشل اتصال BLE", "BLE connection failed")
        reconnectAfterDelay()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        bleWriteInFlight = false
        bleWriteQueue.removeAll()
        status = JL("انقطع BLE — إعادة اتصال", "BLE disconnected — reconnecting")
        if let deviceID = deviceIDs[peripheral.identifier] {
            nearSince[deviceID] = nil
            farSince[deviceID] = Date()
            loadKeylessConfig(for: deviceID)
            if let config = keylessConfigs[deviceID], config.enabled {
                unlockedByKeyless.remove(deviceID)
                Task { @MainActor in
                    VehicleNotificationService.shared.notifyKeylessDeparture(
                        vehicleName: "JOURNEY",
                        lockDelaySeconds: config.lockDelaySeconds
                    )
                }
            }
        }
        commandCharacteristic = nil
        reconnectAfterDelay()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services where service.uuid == self.service {
            peripheral.discoverCharacteristics([commandUUID, stateUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        var discoveredStateCharacteristic: CBCharacteristic?
        for characteristic in characteristics {
            if characteristic.uuid == commandUUID { commandCharacteristic = characteristic }
            if characteristic.uuid == stateUUID { discoveredStateCharacteristic = characteristic }
        }
        if let stateCharacteristic = discoveredStateCharacteristic {
            // Do not request owner state until notifications are actually enabled.
            // On iOS setNotifyValue() is asynchronous; sending owner_status here
            // could make the ESP notify before the CCCD subscription completed.
            peripheral.setNotifyValue(true, for: stateCharacteristic)
            peripheral.readValue(for: stateCharacteristic)
        }
        if let pending, let commandCharacteristic {
            write(pending.command, to: peripheral, characteristic: commandCharacteristic)
        }
    }


    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == stateUUID,
              error == nil,
              characteristic.isNotifying,
              let commandCharacteristic
        else { return }

        // Notification subscription is confirmed now, so the ESP owner reply
        // cannot be lost during app relaunch/reconnect.
        write(VehicleCommand(action: .ownerStatus), to: peripheral, characteristic: commandCharacteristic)
        peripheral.readValue(for: characteristic)

        // Re-send the persisted keyless policy after every reconnect.  This
        // keeps the ESP-side departure lock armed after firmware updates or a
        // power cycle without requiring the user to reopen Keyless Settings.
        if let deviceID = deviceIDs[peripheral.identifier] {
            loadKeylessConfig(for: deviceID)
            if let config = keylessConfigs[deviceID] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak peripheral] in
                    guard let self, let peripheral, peripheral.state == .connected,
                          let characteristic = self.commandCharacteristic else { return }
                    self.write(
                        VehicleCommand(action: .keylessConfig, keyless: config),
                        to: peripheral,
                        characteristic: characteristic
                    )
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == stateUUID,
              let data = characteristic.value,
              let state = try? JSONDecoder().decode(VehicleState.self, from: data),
              let deviceID = deviceIDs[peripheral.identifier]
        else { return }
        onState?(deviceID, state)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, peripheral.state == .connected,
              let deviceID = deviceIDs[peripheral.identifier]
        else { return }
        let rssi = RSSI.intValue
        status = JL("BLE متصل \(rssi) dBm", "BLE connected \(rssi) dBm")
        onRSSI?(deviceID, rssi)
        evaluateKeyless(rssi: rssi, deviceID: deviceID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak peripheral] in
            guard let peripheral, peripheral.state == .connected else { return }
            peripheral.readRSSI()
        }
    }

    private func write(_ command: VehicleCommand, to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard let data = try? JSONEncoder().encode(command) else {
            status = JL("تعذر تجهيز أمر BLE", "Could not prepare BLE command")
            return
        }
        guard characteristic.properties.contains(.write) else {
            status = JL("خاصية أوامر BLE غير متاحة", "BLE command characteristic unavailable")
            return
        }
        pending = nil
        // Only one .withResponse write may be outstanding. Queue the rest locally
        // instead of flooding the ESP FreeRTOS queue. Keep a hard ceiling so a
        // stale background session can never build an unbounded backlog.
        if bleWriteInFlight {
            if bleWriteQueue.count < 12 { bleWriteQueue.append(data) }
            return
        }
        bleWriteInFlight = true
        status = JL("جاري تأكيد أمر BLE (\(data.count) بايت)", "Confirming BLE command (\(data.count) bytes)")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func sendNextBleWrite(on peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard peripheral.state == .connected else {
            bleWriteInFlight = false
            bleWriteQueue.removeAll()
            return
        }
        guard !bleWriteQueue.isEmpty else {
            bleWriteInFlight = false
            return
        }
        let data = bleWriteQueue.removeFirst()
        bleWriteInFlight = true
        status = JL("جاري تأكيد أمر BLE (\(data.count) بايت)", "Confirming BLE command (\(data.count) bytes)")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == commandUUID else { return }
        if let error {
            status = JL("فشل إرسال أمر BLE: \(error.localizedDescription)", "BLE command failed: \(error.localizedDescription)")
            bleWriteInFlight = false
            bleWriteQueue.removeAll()
            return
        }
        status = JL("تم تأكيد أمر BLE", "BLE command confirmed")
        bleWriteInFlight = false
        sendNextBleWrite(on: peripheral, characteristic: characteristic)
    }

    private func reconnectPreferredDevice(forceScanFallback: Bool = false) {
        guard central.state == .poweredOn, let deviceID = preferredDeviceID else { return }

        // First reuse an already-connected Journey peripheral when iOS kept it
        // alive while the app was in the background.
        if let connected = central.retrieveConnectedPeripherals(withServices: [service]).first {
            peripherals[deviceID] = connected
            deviceIDs[connected.identifier] = deviceID
            defaults.set(connected.identifier.uuidString, forKey: "journey.ble.peripheral.\(deviceID)")
            connected.delegate = self
            status = JL("BLE متصل — مزامنة", "BLE connected — synchronizing")
            connected.discoverServices([service])
            connected.readRSSI()
            return
        }

        if let peripheral = peripherals[deviceID] {
            peripheral.delegate = self
            switch peripheral.state {
            case .connected:
                status = JL("BLE متصل — مزامنة", "BLE connected — synchronizing")
                peripheral.discoverServices([service])
                peripheral.readRSSI()
                return
            case .connecting:
                status = JL("جاري اتصال BLE", "Connecting BLE")
            default:
                status = JL("جاري اتصال BLE", "Connecting BLE")
                central.connect(peripheral)
            }
            if forceScanFallback { scheduleScanFallback(for: deviceID) }
            return
        }

        let key = "journey.ble.peripheral.\(deviceID)"
        if let value = defaults.string(forKey: key), let identifier = UUID(uuidString: value),
           let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            peripherals[deviceID] = peripheral
            deviceIDs[peripheral.identifier] = deviceID
            peripheral.delegate = self
            status = JL("جاري اتصال BLE", "Connecting BLE")
            central.connect(peripheral)
            if forceScanFallback { scheduleScanFallback(for: deviceID) }
        } else {
            startPreferredScan(deviceID: deviceID)
        }
    }

    private func startPreferredScan(deviceID: String) {
        guard central.state == .poweredOn, preferredDeviceID == deviceID else { return }
        if let p = peripherals[deviceID], p.state == .connected || p.state == .connecting { return }
        status = JL("جاري البحث عن ESP", "Searching for ESP")
        if central.isScanning { central.stopScan() }
        // Scan all BLE advertisements here instead of filtering by service UUID.
        // Some ESP32 advertising payloads omit the service UUID even though the
        // GATT service is available after connection. Name matching below keeps
        // this scan targeted to the selected JOURNEY ESP.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, self.preferredDeviceID == deviceID, !self.isConnected(to: deviceID) else { return }
            self.reconnectPreferredDevice(forceScanFallback: true)
        }
    }

    private func scheduleScanFallback(for deviceID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self,
                  self.preferredDeviceID == deviceID,
                  self.central.state == .poweredOn
            else { return }
            if self.isConnected(to: deviceID) { return }

            // A cached CBPeripheral can become stale after app suspension.
            // Do not wait for the user to press a command; scan for the ESP now.
            self.startPreferredScan(deviceID: deviceID)
        }
    }

    private func reconnectAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reconnectPreferredDevice(forceScanFallback: true)
        }
    }

    private func loadKeylessConfig(for deviceID: String) {
        guard keylessConfigs[deviceID] == nil,
              let data = defaults.data(forKey: "journey.keyless.config.\(deviceID)"),
              let config = try? JSONDecoder().decode(KeylessEntryConfig.self, from: data)
        else { return }
        keylessConfigs[deviceID] = config
    }

    private func evaluateKeyless(rssi: Int, deviceID: String) {
        loadKeylessConfig(for: deviceID)
        guard let config = keylessConfigs[deviceID], config.enabled,
              let peripheral = peripherals[deviceID], peripheral.state == .connected,
              let characteristic = commandCharacteristic
        else { return }

        // Log-distance estimate only; the wide unlock/lock gap provides
        // hysteresis because RSSI is not a precise distance sensor.
        let distance = pow(10.0, (-59.0 - Double(rssi)) / 22.0)
        let now = Date()
        if distance <= config.unlockDistanceMeters {
            farSince[deviceID] = nil
            Task { @MainActor in VehicleNotificationService.shared.clearKeylessDepartureNotice() }
            let started = nearSince[deviceID] ?? now
            nearSince[deviceID] = started
            if !unlockedByKeyless.contains(deviceID),
               now.timeIntervalSince(started) >= Double(config.unlockHoldSeconds) {
                unlockedByKeyless.insert(deviceID)
                sendPresence(nearby: true, rssi: rssi, deviceID: deviceID, peripheral: peripheral, characteristic: characteristic)
                status = JL("تم فتح الدخول الذكي", "Smart entry unlocked")
            } else if unlockedByKeyless.contains(deviceID) {
                sendPresence(nearby: true, rssi: rssi, deviceID: deviceID, peripheral: peripheral, characteristic: characteristic)
            }
        } else if distance >= config.lockDistanceMeters {
            nearSince[deviceID] = nil
            farSince[deviceID] = now
            if unlockedByKeyless.contains(deviceID) {
                unlockedByKeyless.remove(deviceID)
                sendPresence(nearby: false, rssi: rssi, deviceID: deviceID, peripheral: peripheral, characteristic: characteristic, force: true)
                Task { @MainActor in
                    VehicleNotificationService.shared.notifyKeylessDeparture(
                        vehicleName: "JOURNEY",
                        lockDelaySeconds: config.lockDelaySeconds
                    )
                }
                status = JL("تم تسجيل ابتعاد الدخول الذكي", "Smart entry departure recorded")
            }
        } else {
            nearSince[deviceID] = nil
            farSince[deviceID] = nil
            if unlockedByKeyless.contains(deviceID) {
                sendPresence(nearby: true, rssi: rssi, deviceID: deviceID, peripheral: peripheral, characteristic: characteristic)
            }
        }
    }

    private func sendPresence(
        nearby: Bool,
        rssi: Int,
        deviceID: String,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        force: Bool = false
    ) {
        let now = Date()
        if !force, let last = lastPresenceSent[deviceID], now.timeIntervalSince(last) < 5 { return }
        lastPresenceSent[deviceID] = now
        write(
            VehicleCommand(action: .keylessPresence, presence: KeylessPresence(nearby: nearby, rssi: rssi)),
            to: peripheral,
            characteristic: characteristic
        )
    }
}
