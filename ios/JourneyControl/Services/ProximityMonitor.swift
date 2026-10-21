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
        if central.state == .poweredOn {
            // ManageDevicesView starts discovery on demand. A second central
            // scanning continuously can contend with the live BLE connection.
            isScanning = false
        }
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
    @Published private(set) var isSessionReady = false
    @Published private(set) var commandStatus = ""
    @Published private(set) var linkDropCount = 0
    @Published private(set) var lastLinkError = ""

    var onState: ((String, VehicleState) -> Void)?
    var onDiagnosticChunk: ((String, String) -> Void)?
    var onRSSI: ((String, Int) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [String: CBPeripheral] = [:]
    private var deviceIDs: [UUID: String] = [:]
    private var commandCharacteristic: CBCharacteristic?
    private var secureStateCharacteristic: CBCharacteristic?
    // GATT is ready after the notification subscription succeeds (not after Pair).
    // before this transport is considered available for vehicle commands.
    private var secureSessionReady = false
    private var secureReadPending = false
    // Only one discovery/encrypted-read/notification setup per BLE link.
    // Lifecycle resumes and scan fallbacks must not start overlapping GATT work.
    private var gattSetupInProgress = false
    private var pending: (command: VehicleCommand, deviceID: String)?
    // Serialize confirmed GATT writes. CoreBluetooth accepts writeValue calls faster
    // than the ESP command task can drain them when OBD connect/discovery is busy.
    private var bleWriteInFlight = false
    private var bleWriteQueue: [Data] = []
    private var preferredDeviceID: String?
    private var demoSuspended = UserDefaults.standard.bool(forKey: "journey.demo.enabled")
    private var keylessConfigs: [String: KeylessEntryConfig] = [:]
    private var nearSince: [String: Date] = [:]
    private var farSince: [String: Date] = [:]
    private var unlockedByKeyless: Set<String> = []
    private var lastPresenceSent: [String: Date] = [:]
    private var reconnectScheduled = false
    private var reconnectFailures = 0
    private var disconnectGeneration = 0
    // Poll RSSI once per authenticated connection session. Old delayed poll
    // closures must never survive a disconnect/reconnect and start new loops.
    private var rssiPollGeneration = 0
    private var rssiPollScheduled = false
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

    /// Suspend all local BLE traffic while the app is in isolated demo mode.
    func suspendForDemo() {
        demoSuspended = true
        pending = nil
        bleWriteQueue.removeAll()
        bleWriteInFlight = false
        commandCharacteristic = nil
        secureStateCharacteristic = nil
        secureSessionReady = false
        isSessionReady = false
        secureReadPending = false
        gattSetupInProgress = false
        rssiPollGeneration += 1
        rssiPollScheduled = false
        nearSince.removeAll()
        farSince.removeAll()
        unlockedByKeyless.removeAll()
        if central.isScanning { central.stopScan() }
        for peripheral in peripherals.values where peripheral.state == .connected || peripheral.state == .connecting {
            central.cancelPeripheralConnection(peripheral)
        }
        status = JL("BLE متوقف بوضع الديمو", "BLE suspended in demo mode")
    }

    func resumeFromDemo() {
        demoSuspended = false
        reconnectPreferredDevice(forceScanFallback: true)
    }

    /// Keeps the known Journey ESP32 connected in the background.  iOS can
    /// restore this central manager after it suspends the app normally.
    func prepareConnection(to deviceID: String) {
        guard !demoSuspended else { return }
        preferredDeviceID = deviceID
        defaults.set(deviceID, forKey: "journey.ble.preferredDevice")
        loadKeylessConfig(for: deviceID)
        reconnectPreferredDevice(forceScanFallback: true)
    }

    /// Called whenever the app becomes active again. `onAppear` is not
    /// guaranteed to run when iOS only backgrounds/foregrounds the existing
    /// view hierarchy, so explicitly wake the BLE reconnect path here.
    func resumeConnection(to deviceID: String) {
        guard !demoSuspended else { return }
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
        return secureSessionReady && commandCharacteristic != nil
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
        guard !demoSuspended else { return false }
        pending = (command, deviceID)
        guard central.state == .poweredOn else {
            status = JL("فعّل البلوتوث", "Enable Bluetooth")
            return false
        }
        if let peripheral = peripherals[deviceID], peripheral.state == .connected,
           secureSessionReady, let commandCharacteristic {
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
        if isReady && !demoSuspended { reconnectPreferredDevice(forceScanFallback: true) }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if demoSuspended {
            for peripheral in (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? [] {
                central.cancelPeripheralConnection(peripheral)
            }
            return
        }
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else { return }
        for peripheral in restored {
            guard let deviceID = preferredDeviceID else { continue }
            peripherals[deviceID] = peripheral
            deviceIDs[peripheral.identifier] = deviceID
            peripheral.delegate = self
            if peripheral.state == .connected { beginGattSetup(on: peripheral) }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !demoSuspended else { return }
        let name = ((advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wantedID = pending?.deviceID ?? preferredDeviceID
        guard let wantedID else { return }
        // Match the previously paired CoreBluetooth identifier directly even when
        // advertising omits the device name. RSSI must never gate the connection.
        let savedIdentifier = defaults.string(forKey: "journey.ble.peripheral.\(wantedID)")
        let isKnownPeripheral = savedIdentifier == peripheral.identifier.uuidString
        guard isKnownPeripheral || name == wantedID || name == "JOURNEY-\(wantedID)" else { return }
        peripherals[wantedID] = peripheral
        deviceIDs[peripheral.identifier] = wantedID
        defaults.set(peripheral.identifier.uuidString, forKey: "journey.ble.peripheral.\(wantedID)")
        peripheral.delegate = self
        central.stopScan()
        // Duplicate advertisements must never issue overlapping connect calls.
        if peripheral.state == .disconnected {
            central.connect(peripheral)
        }
    }

    /// Serializes initial GATT discovery and CCCD subscription; never issue overlapping discovery.
    private func beginGattSetup(on peripheral: CBPeripheral) {
        guard !demoSuspended, peripheral.state == .connected,
              !gattSetupInProgress, !secureSessionReady else { return }
        gattSetupInProgress = true
        status = JL("BLE متصل — اكتشاف الخدمة", "BLE connected — discovering service")
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !demoSuspended else { central.cancelPeripheralConnection(peripheral); return }
        if central.isScanning { central.stopScan() }
        reconnectFailures = 0
        reconnectScheduled = false
        secureSessionReady = false
        isSessionReady = false
        secureReadPending = false
        secureStateCharacteristic = nil
        commandCharacteristic = nil
        gattSetupInProgress = false
        bleWriteInFlight = false
        bleWriteQueue.removeAll()
        rssiPollGeneration += 1
        rssiPollScheduled = false
        disconnectGeneration += 1
        Task { @MainActor in VehicleNotificationService.shared.clearKeylessDepartureNotice() }
        beginGattSetup(on: peripheral)
        // Poll RSSI only after GATT notification subscription is confirmed.
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isSessionReady = false
        let failure = error as NSError?
        lastLinkError = failure.map { "\($0.domain) / \($0.code): \($0.localizedDescription)" } ?? "connection failed"
        status = JL("فشل اتصال BLE", "BLE connection failed")
        reconnectFailures = min(reconnectFailures + 1, 6)
        reconnectAfterDelay()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if demoSuspended {
            commandCharacteristic = nil
            secureStateCharacteristic = nil
            secureSessionReady = false
            secureReadPending = false
            gattSetupInProgress = false
            bleWriteInFlight = false
            bleWriteQueue.removeAll()
            rssiPollGeneration += 1
            rssiPollScheduled = false
            status = JL("BLE متوقف بوضع الديمو", "BLE suspended in demo mode")
            return
        }
        bleWriteInFlight = false
        bleWriteQueue.removeAll()
        isSessionReady = false
        rssiPollGeneration += 1
        rssiPollScheduled = false
        linkDropCount += 1
        let failure = error as NSError?
        lastLinkError = failure.map { "\($0.domain) / \($0.code): \($0.localizedDescription)" } ?? "BLE disconnected without CoreBluetooth error"
        status = JL("انقطع BLE — إعادة اتصال", "BLE disconnected — reconnecting")
        let duration = Int(Date().timeIntervalSince1970)
        NSLog("[JOURNEY BLE] didDisconnect peripheral=%@ error=%@ timestamp=%d", peripheral.identifier.uuidString, error?.localizedDescription ?? "nil", duration)
        reconnectFailures = min(reconnectFailures + 1, 6)
        disconnectGeneration += 1
        // A transient BLE link loss is not physical departure. Keep the
        // proximity history intact and let authenticated distance samples
        // drive departure/lock notifications.
        if let deviceID = deviceIDs[peripheral.identifier] {
            loadKeylessConfig(for: deviceID)
        }
        commandCharacteristic = nil
        secureStateCharacteristic = nil
        secureSessionReady = false
        secureReadPending = false
        gattSetupInProgress = false
        reconnectAfterDelay()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !demoSuspended, gattSetupInProgress else { return }
        guard error == nil, let services = peripheral.services else {
            gattSetupInProgress = false
            status = JL("فشل اكتشاف خدمة BLE", "BLE service discovery failed")
            if let error { NSLog("[JOURNEY BLE] discoverServices failed: %@", error.localizedDescription) }
            return
        }
        guard let matchedService = services.first(where: { $0.uuid == self.service }) else {
            gattSetupInProgress = false
            status = JL("خدمة JOURNEY غير موجودة", "JOURNEY GATT service missing")
            return
        }
        status = JL("BLE متصل — اكتشاف الخصائص", "BLE connected — discovering characteristics")
        peripheral.discoverCharacteristics([commandUUID, stateUUID], for: matchedService)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !demoSuspended, gattSetupInProgress, service.uuid == self.service else { return }
        guard error == nil, let characteristics = service.characteristics else {
            gattSetupInProgress = false
            status = JL("فشل اكتشاف خصائص BLE", "BLE characteristic discovery failed")
            if let error { NSLog("[JOURNEY BLE] discoverCharacteristics failed: %@", error.localizedDescription) }
            return
        }
        var discoveredStateCharacteristic: CBCharacteristic?
        for characteristic in characteristics {
            if characteristic.uuid == commandUUID { commandCharacteristic = characteristic }
            if characteristic.uuid == stateUUID { discoveredStateCharacteristic = characteristic }
        }
        // Oct 04 legacy BLE path: both GATT characteristics are intentionally
        // unencrypted on the KR17.9 BENCH firmware. Subscribe to notifications
        // directly and complete readiness only after iOS confirms the CCCD.
        // Never claim that a direct GATT session is encrypted or bonded.
        guard commandCharacteristic != nil, let stateCharacteristic = discoveredStateCharacteristic else {
            gattSetupInProgress = false
            status = JL("خصائص BLE غير مكتملة", "BLE GATT characteristics missing")
            return
        }
        secureStateCharacteristic = stateCharacteristic
        secureSessionReady = false
        secureReadPending = false
        status = JL("BLE — تفعيل إشعارات GATT", "BLE — subscribing to GATT notifications")
        peripheral.setNotifyValue(true, for: stateCharacteristic)
    }


    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard !demoSuspended else { return }
        guard characteristic.uuid == stateUUID else { return }
        guard error == nil, characteristic.isNotifying, let commandCharacteristic else {
            secureSessionReady = false
            gattSetupInProgress = false
            status = JL("فشل تفعيل إشعارات BLE", "BLE notification subscription failed")
            if let error { NSLog("[JOURNEY BLE] setNotifyValue failed: %@", error.localizedDescription) }
            return
        }
        gattSetupInProgress = false
        secureSessionReady = true
        isSessionReady = true
        status = JL("BLE GATT متصل وجاهز", "BLE GATT connected and ready")
        // Begin one RSSI loop only after the GATT notification subscription.
        rssiPollGeneration += 1
        rssiPollScheduled = false
        scheduleRSSIPoll(on: peripheral, generation: rssiPollGeneration, after: 0.2)
        // Flush queued commands only after CCCD activation. BENCH firmware
        // rejects vehicle commands and disables all remote output GPIOs.
        if let pending, pending.deviceID == deviceIDs[peripheral.identifier] {
            write(pending.command, to: peripheral, characteristic: commandCharacteristic)
        }

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
                          let characteristic = self.commandCharacteristic, !self.demoSuspended else { return }
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
        guard !demoSuspended, characteristic.uuid == stateUUID else { return }
        if secureReadPending {
            secureReadPending = false
            if let error {
                secureSessionReady = false
                isSessionReady = false
                gattSetupInProgress = false
                let failure = error as NSError
                status = JL("فشل القراءة المشفّرة BLE (\(failure.code))", "Encrypted BLE read failed (\(failure.code))")
                NSLog("[JOURNEY BLE] encrypted GATT read failed (%@/%ld): %@", failure.domain, failure.code, error.localizedDescription)
                return
            }
            guard let stateCharacteristic = secureStateCharacteristic else { return }
            // This sequence is essential: encrypted read first, then CCCD
            // notification subscription, then authorized owner commands.
            status = JL("BLE — تفعيل الإشعارات الآمنة", "BLE — enabling secure notifications")
            peripheral.setNotifyValue(true, for: stateCharacteristic)
        }
        guard error == nil,
              let data = characteristic.value,
              let deviceID = deviceIDs[peripheral.identifier] else { return }
        // Diagnostic chunks are not VehicleState messages.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["ds"] != nil, object["di"] != nil,
           object["dn"] != nil, object["dx"] != nil {
            onDiagnosticChunk?(deviceID, String(decoding: data, as: UTF8.self))
            return
        }
        if let state = try? JSONDecoder().decode(VehicleState.self, from: data) {
            onState?(deviceID, state)
        }
    }

    /// Exactly one queued timer and one RSSI read sequence per BLE session.
    /// A queued read from an old link is discarded even if iOS reconnects the
    /// same peripheral quickly and its CoreBluetooth state is .connected again.
    private func scheduleRSSIPoll(on peripheral: CBPeripheral, generation: Int, after delay: Double) {
        guard !rssiPollScheduled, secureSessionReady, !demoSuspended else { return }
        rssiPollScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak peripheral] in
            guard let self, self.rssiPollGeneration == generation else { return }
            self.rssiPollScheduled = false
            guard let peripheral,
                  peripheral.state == .connected,
                  self.secureSessionReady,
                  !self.demoSuspended else { return }
            peripheral.readRSSI()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard !demoSuspended, secureSessionReady, peripheral.state == .connected else { return }
        if error == nil, let deviceID = deviceIDs[peripheral.identifier] {
            let rssi = RSSI.intValue
            // Invalid CoreBluetooth RSSI values are never proximity evidence.
            // RSSI must not reject or tear down a healthy BLE connection.
            if rssi < 0 && rssi != -127 && rssi > -120 {
                status = JL("BLE متصل \(rssi) dBm", "BLE connected \(rssi) dBm")
                onRSSI?(deviceID, rssi)
                evaluateKeyless(rssi: rssi, deviceID: deviceID)
            }
        }
        // 2 s is enough for keyless hold/hysteresis. Avoid 1 Hz GATT polling
        // alongside repeated MQTT/OBD status traffic on the ESP radio.
        scheduleRSSIPoll(on: peripheral, generation: rssiPollGeneration, after: 2.0)
    }

    private func write(_ command: VehicleCommand, to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard !demoSuspended else { return }
        guard let data = try? JSONEncoder().encode(command) else {
            commandStatus = JL("تعذر تجهيز أمر BLE", "Could not prepare BLE command")
            return
        }
        guard characteristic.properties.contains(.write) else {
            commandStatus = JL("خاصية أوامر BLE غير متاحة", "BLE command characteristic unavailable")
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
        commandStatus = JL("جاري تأكيد أمر BLE (\(data.count) بايت)", "Confirming BLE command (\(data.count) bytes)")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func sendNextBleWrite(on peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard !demoSuspended else { bleWriteQueue.removeAll(); bleWriteInFlight = false; return }
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
        commandStatus = JL("جاري تأكيد أمر BLE (\(data.count) بايت)", "Confirming BLE command (\(data.count) bytes)")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !demoSuspended else { return }
        guard characteristic.uuid == commandUUID else { return }
        if let error {
            commandStatus = JL("فشل إرسال أمر BLE: \(error.localizedDescription)", "BLE command failed: \(error.localizedDescription)")
            bleWriteInFlight = false
            bleWriteQueue.removeAll()
            return
        }
        commandStatus = JL("تم تأكيد أمر BLE", "BLE command confirmed")
        bleWriteInFlight = false
        sendNextBleWrite(on: peripheral, characteristic: characteristic)
    }

    private func reconnectPreferredDevice(forceScanFallback: Bool = false) {
        guard !demoSuspended else { return }
        guard central.state == .poweredOn, let deviceID = preferredDeviceID else { return }

        // First reuse an already-connected Journey peripheral when iOS kept it
        // alive while the app was in the background.
        if let connected = central.retrieveConnectedPeripherals(withServices: [service]).first(where: {
            $0.identifier == peripherals[deviceID]?.identifier ||
            $0.identifier.uuidString == defaults.string(forKey: "journey.ble.peripheral.\(deviceID)")
        }) {
            peripherals[deviceID] = connected
            deviceIDs[connected.identifier] = deviceID
            defaults.set(connected.identifier.uuidString, forKey: "journey.ble.peripheral.\(deviceID)")
            connected.delegate = self
            // Never overlap discovery with an in-progress encrypted read/CCCD.
            if gattSetupInProgress { return }
            if secureSessionReady { return }
            beginGattSetup(on: connected)
            return
        }

        if let peripheral = peripherals[deviceID] {
            peripheral.delegate = self
            switch peripheral.state {
            case .connected:
                if gattSetupInProgress || secureSessionReady { return }
                beginGattSetup(on: peripheral)
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
        guard !demoSuspended else { return }
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
        // Prefer the cached direct connection long enough to complete GATT setup.
        // Fall back to a short scan only when the cached path has not completed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self,
                  self.preferredDeviceID == deviceID,
                  self.central.state == .poweredOn
            else { return }
            if self.isConnected(to: deviceID) { return }
            // A physically connected peripheral must not be scanned again just
            // because its GATT command characteristic is still being discovered.
            if let saved = self.peripherals[deviceID], saved.state == .connected {
                self.beginGattSetup(on: saved)
                return
            }

            // A cached CBPeripheral can become stale after app suspension.
            // Do not wait for the user to press a command; scan for the ESP now.
            self.startPreferredScan(deviceID: deviceID)
        }
    }

    private func reconnectAfterDelay() {
        guard !reconnectScheduled, !demoSuspended else { return }
        reconnectScheduled = true
        let delay = min(2.0 * pow(2.0, Double(max(0, reconnectFailures - 1))), 30.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            guard !self.demoSuspended else { return }
            self.reconnectPreferredDevice(forceScanFallback: true)
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
        guard !demoSuspended else { return }
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
