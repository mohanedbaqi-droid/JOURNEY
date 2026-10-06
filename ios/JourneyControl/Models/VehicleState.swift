import Foundation

struct VehicleState: Codable {
    /// Small BLE discovery packets carry only OBD results.  They must merge
    /// into, rather than replace, the last complete vehicle state.
    var bodyStatePacket = false
    var rpmValid = false
    var coolantValid = false
    var speedValid = false
    var doorsValid = false
    var lightsValid = false
    var turnsValid = false
    var readDiagnostics = ""
    var engineStateText: String { rpmValid ? (simulatedEngineRunning ? JL("تعمل", "Running") : JL("متوقفة", "Stopped")) : JL("غير متاح", "Unavailable") }
    var partialState = false
    var ownerStatePacket = false
    var ownerStateKnown = false
    var coreStatePacket = false
    var obdTelemetryPacket = false
    var wifiStatePacket = false
    var cellularStatePacket = false
    var vehicleEventPacket = false
    var vehicleEventId = ""
    var vehicleEventType = ""
    var vehicleEventText = ""
    var vehicleEventUptime: UInt64 = 0
    var online = false
    var benchMode = false
    var simulatedLocked = true
    var simulatedEngineRunning = false
    var simulatedDoorsOpen = false
    // Local demo controls; these are never decoded from live ESP packets.
    var demoDriverFrontOpen = false
    var demoPassengerFrontOpen = false
    var demoDriverRearOpen = false
    var demoPassengerRearOpen = false
    var demoLiftgateOpen = false
    var demoHoodOpen = false
    var demoDRLOn = false
    var remotePowered = false
    var remotePowerStatePresent = false
    var feedbackStatePresent = false
    var feedbackLock = false
    var feedbackUnlock = false
    var feedbackStart = false
    var feedbackAlarm = false
    var trustedPhoneConfigured = false
    var authorizedPhoneCount = 0
    var ownerAdminPhone = ""
    var pendingOwnerPhone = ""
    var hornActive = false
    var headlightsOn = false
    var leftSignalOn = false
    var rightSignalOn = false
    var bcmStateValid = false
    var gpsValid = false
    /// Published by the 4G/3G modem on the ESP when available.
    var cellularNetwork = JL("غير متاح", "Unavailable")
    var cellularSignalDBm = -120
    var cellularEnabled = false
    var cellularRegistered = false
    var cellularDataAttached = false
    var cellularAPN = ""
    var cellularStatus = "off"
    var hotspotEnabled = false
    var hotspotRunning = false
    var hotspotSSID = ""
    var internetRoute = "NONE"
    /// Bluetooth RSSI measured by the ESP / phone proximity link.
    var bluetoothRSSI = -58
    var espSleeping = false
    var latitude = 0.0
    var longitude = 0.0
    var obdConnected = false
    var obdStatus = "waiting"
    var obdResponseRate = 0
    var obdTotalResponses: UInt64 = 0
    var obdScanProgress = 0
    var obdScannedPids = 0
    var obdSupportedPids = 0
    var obdStandardScanComplete = false
    var obdCurrentPid = ""
    var obdLastReply = ""
    var obdAdapterName = ""
    var obdDiscoveredAdapters = ""
    var obdDiscoveredWifiNetworks = ""
    var obdDiscoveryKind = ""
    var obdDiscoveryReset = false
    var obdDiscoveryDone = false
    var obdClearInProgress = false
    var rpm = 0
    var speedKph = 0
    var coolantC = 0
    var intakeAirC = 0
    var engineLoadPercent = 0
    var throttlePercent = 0
    var fuelLevelPercent = 0
    var fuelLevelValid = false
    var engineRuntimeSeconds = 0
    var controlVoltage = 0.0
    var batteryVoltage = 0.0
    var canAwake = false
    var ignitionState = "UNKNOWN"
    var diagnosticCodes: [String] = []
    var lastEvent = "waiting"
    var uptimeSeconds: UInt64 = 0
    var remotePulseMs = 450
    var remoteWakeDelayMs = 1000
    var remotePowerOffDelayMs = 2000
    var hudBrightness = 5
    var otaAddress = ""
    var wifiEnabled = false
    var wifiConnected = false
    var wifiSSID = ""
    var wifiRSSI = -120
    var wifiIP = ""
    var wifiStatus = "off"
    var cloudConnected = false
    var wifiDiscoveredNetworks = ""
    var wifiDiscoveryReset = false
    var wifiDiscoveryDone = false
    var maintenanceMode = false
    var powerSaveMode = 0
    var powerSaveIdleMinutes = 30
    var powerSaveActive = false

    private enum CompactCodingKeys: String, CodingKey {
        case bodyPacket = "bp"
        case doorsValid = "dv", lightsValid = "lv", turnsValid = "iv"
        case lampOn = "lo", leftOn = "il", rightOn = "ir", diagnostics = "dg"
        case rpmValid = "rv", coolantValid = "tv", speedValid = "sv"
        case packet = "p"       // 1 = owner/core BLE packet
        case online = "on"
        case trusted = "tc"
        case count = "ac"
        case admin = "oa"
        case pending = "po"
        case event = "ev"
        case uptime = "up"
        case remotePowered = "rp"
        case locked = "lk"
        case doorsOpen = "do"
        case engineRunning = "er"
        case obdTelemetry = "ot"
        case obdConnected = "oc"
        case obdStatus = "os"
        case obdResponseRate = "rr"
        case obdTotalResponses = "tr"
        case obdScannedPids = "sp"
        case obdSupportedPids = "su"
        case obdScanProgress = "pg"
        case obdScanComplete = "sc"
        case obdCurrentPid = "cp"
        case obdAdapterName = "an"
        case rpm = "r"
        case speed = "v"
        case coolant = "t"
        case batteryVoltage = "bv"
        case canAwake = "ca"
        case ignition = "ig"
        case fuelLevel = "fl"
        case fuelValid = "fv"
    }

    enum CodingKeys: String, CodingKey {
        case bodyStatePacket, rpmValid, coolantValid, speedValid, doorsValid, lightsValid, turnsValid, readDiagnostics
        case partialState, ownerStatePacket, ownerStateKnown, coreStatePacket, obdTelemetryPacket, wifiStatePacket, cellularStatePacket, vehicleEventPacket, vehicleEventId, vehicleEventType, vehicleEventText, vehicleEventUptime, online, benchMode, simulatedLocked, simulatedEngineRunning
        case simulatedDoorsOpen, remotePowered, feedbackLock, feedbackUnlock, feedbackStart, feedbackAlarm, trustedPhoneConfigured, authorizedPhoneCount, ownerAdminPhone, pendingOwnerPhone, hornActive, headlightsOn, leftSignalOn, rightSignalOn, bcmStateValid
        case cellularNetwork, cellularSignalDBm, cellularEnabled, cellularRegistered, cellularDataAttached, cellularAPN, cellularStatus, hotspotEnabled, hotspotRunning, hotspotSSID, internetRoute, bluetoothRSSI, espSleeping
        case gpsValid, latitude, longitude, obdConnected, obdStatus, obdResponseRate, obdTotalResponses, obdScanProgress, obdScannedPids, obdSupportedPids, obdStandardScanComplete, obdCurrentPid, obdLastReply, obdAdapterName, obdDiscoveredAdapters, obdDiscoveredWifiNetworks, obdDiscoveryKind, obdDiscoveryReset, obdDiscoveryDone, obdClearInProgress
        case rpm, speedKph, coolantC, intakeAirC, engineLoadPercent, throttlePercent, fuelLevelPercent, fuelLevelValid, engineRuntimeSeconds, controlVoltage
        case batteryVoltage, canAwake, ignitionState, diagnosticCodes
        case lastEvent, uptimeSeconds, remotePulseMs, remoteWakeDelayMs, remotePowerOffDelayMs, hudBrightness, otaAddress, wifiEnabled, wifiConnected, wifiSSID, wifiRSSI, wifiIP, wifiStatus, cloudConnected, wifiDiscoveredNetworks, wifiDiscoveryReset, wifiDiscoveryDone, maintenanceMode, powerSaveMode, powerSaveIdleMinutes, powerSaveActive
    }

    init() {}

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let compact = try decoder.container(keyedBy: CompactCodingKeys.self)
        let compactPacket = (try compact.decodeIfPresent(Int.self, forKey: .packet) ?? 0) == 1
        partialState = try box.decodeIfPresent(Bool.self, forKey: .partialState) ?? compactPacket
        ownerStatePacket = try box.decodeIfPresent(Bool.self, forKey: .ownerStatePacket) ?? compactPacket
        ownerStateKnown = try box.decodeIfPresent(Bool.self, forKey: .ownerStateKnown) ?? false
        coreStatePacket = try box.decodeIfPresent(Bool.self, forKey: .coreStatePacket) ?? false
        let fullObdTelemetryPacket = try box.decodeIfPresent(Bool.self, forKey: .obdTelemetryPacket) ?? false
        let compactObdTelemetryPacket = (try compact.decodeIfPresent(Int.self, forKey: .obdTelemetry) ?? 0) == 1
        obdTelemetryPacket = fullObdTelemetryPacket || compactObdTelemetryPacket
        wifiStatePacket = try box.decodeIfPresent(Bool.self, forKey: .wifiStatePacket) ?? false
        cellularStatePacket = try box.decodeIfPresent(Bool.self, forKey: .cellularStatePacket) ?? false
        if obdTelemetryPacket || wifiStatePacket || cellularStatePacket { partialState = true }
        vehicleEventPacket = try box.decodeIfPresent(Bool.self, forKey: .vehicleEventPacket) ?? false
        vehicleEventId = try box.decodeIfPresent(String.self, forKey: .vehicleEventId) ?? ""
        vehicleEventType = try box.decodeIfPresent(String.self, forKey: .vehicleEventType) ?? ""
        vehicleEventText = try box.decodeIfPresent(String.self, forKey: .vehicleEventText) ?? ""
        vehicleEventUptime = try box.decodeIfPresent(UInt64.self, forKey: .vehicleEventUptime) ?? 0
        online = try box.decodeIfPresent(Bool.self, forKey: .online) ?? ((try compact.decodeIfPresent(Int.self, forKey: .online) ?? 0) == 1)
        benchMode = try box.decodeIfPresent(Bool.self, forKey: .benchMode) ?? false
        simulatedLocked = try box.decodeIfPresent(Bool.self, forKey: .simulatedLocked) ?? ((try compact.decodeIfPresent(Int.self, forKey: .locked) ?? 1) == 1)
        simulatedEngineRunning = try box.decodeIfPresent(Bool.self, forKey: .simulatedEngineRunning) ?? ((try compact.decodeIfPresent(Int.self, forKey: .engineRunning) ?? 0) == 1)
        simulatedDoorsOpen = try box.decodeIfPresent(Bool.self, forKey: .simulatedDoorsOpen) ?? ((try compact.decodeIfPresent(Int.self, forKey: .doorsOpen) ?? 0) == 1)
        remotePowered = try box.decodeIfPresent(Bool.self, forKey: .remotePowered) ?? ((try compact.decodeIfPresent(Int.self, forKey: .remotePowered) ?? 0) == 1)
        remotePowerStatePresent = box.contains(.remotePowered) || compact.contains(.remotePowered)
        feedbackLock = try box.decodeIfPresent(Bool.self, forKey: .feedbackLock) ?? false
        feedbackUnlock = try box.decodeIfPresent(Bool.self, forKey: .feedbackUnlock) ?? false
        feedbackStart = try box.decodeIfPresent(Bool.self, forKey: .feedbackStart) ?? false
        feedbackAlarm = try box.decodeIfPresent(Bool.self, forKey: .feedbackAlarm) ?? false
        feedbackStatePresent = box.contains(.feedbackLock) || box.contains(.feedbackUnlock)
            || box.contains(.feedbackStart) || box.contains(.feedbackAlarm)
        trustedPhoneConfigured = try box.decodeIfPresent(Bool.self, forKey: .trustedPhoneConfigured) ?? ((try compact.decodeIfPresent(Int.self, forKey: .trusted) ?? 0) == 1)
        authorizedPhoneCount = try box.decodeIfPresent(Int.self, forKey: .authorizedPhoneCount) ?? (try compact.decodeIfPresent(Int.self, forKey: .count) ?? 0)
        ownerAdminPhone = try box.decodeIfPresent(String.self, forKey: .ownerAdminPhone) ?? (try compact.decodeIfPresent(String.self, forKey: .admin) ?? "")
        pendingOwnerPhone = try box.decodeIfPresent(String.self, forKey: .pendingOwnerPhone) ?? (try compact.decodeIfPresent(String.self, forKey: .pending) ?? "")
        hornActive = try box.decodeIfPresent(Bool.self, forKey: .hornActive) ?? false
        headlightsOn = try box.decodeIfPresent(Bool.self, forKey: .headlightsOn) ?? false
        leftSignalOn = try box.decodeIfPresent(Bool.self, forKey: .leftSignalOn) ?? false
        rightSignalOn = try box.decodeIfPresent(Bool.self, forKey: .rightSignalOn) ?? false
        bcmStateValid = try box.decodeIfPresent(Bool.self, forKey: .bcmStateValid) ?? false
        bodyStatePacket = (try compact.decodeIfPresent(Int.self, forKey: .bodyPacket) ?? 0) == 1
        if bodyStatePacket { partialState = true }
        rpmValid = try box.decodeIfPresent(Bool.self, forKey: .rpmValid) ?? (try compact.decodeIfPresent(Bool.self, forKey: .rpmValid) ?? false)
        coolantValid = try box.decodeIfPresent(Bool.self, forKey: .coolantValid) ?? (try compact.decodeIfPresent(Bool.self, forKey: .coolantValid) ?? false)
        speedValid = try box.decodeIfPresent(Bool.self, forKey: .speedValid) ?? (try compact.decodeIfPresent(Bool.self, forKey: .speedValid) ?? false)
        doorsValid = try box.decodeIfPresent(Bool.self, forKey: .doorsValid) ?? (try compact.decodeIfPresent(Bool.self, forKey: .doorsValid) ?? false)
        lightsValid = try box.decodeIfPresent(Bool.self, forKey: .lightsValid) ?? (try compact.decodeIfPresent(Bool.self, forKey: .lightsValid) ?? false)
        turnsValid = try box.decodeIfPresent(Bool.self, forKey: .turnsValid) ?? (try compact.decodeIfPresent(Bool.self, forKey: .turnsValid) ?? false)
        readDiagnostics = try box.decodeIfPresent(String.self, forKey: .readDiagnostics) ?? (try compact.decodeIfPresent(String.self, forKey: .diagnostics) ?? "")
        if bodyStatePacket {
            headlightsOn = try compact.decodeIfPresent(Bool.self, forKey: .lampOn) ?? false
            leftSignalOn = try compact.decodeIfPresent(Bool.self, forKey: .leftOn) ?? false
            rightSignalOn = try compact.decodeIfPresent(Bool.self, forKey: .rightOn) ?? false
        }

        gpsValid = try box.decodeIfPresent(Bool.self, forKey: .gpsValid) ?? false
        cellularNetwork = try box.decodeIfPresent(String.self, forKey: .cellularNetwork) ?? JL("غير متاح", "Unavailable")
        cellularSignalDBm = try box.decodeIfPresent(Int.self, forKey: .cellularSignalDBm) ?? -120
        cellularEnabled = try box.decodeIfPresent(Bool.self, forKey: .cellularEnabled) ?? false
        cellularRegistered = try box.decodeIfPresent(Bool.self, forKey: .cellularRegistered) ?? false
        cellularDataAttached = try box.decodeIfPresent(Bool.self, forKey: .cellularDataAttached) ?? false
        cellularAPN = try box.decodeIfPresent(String.self, forKey: .cellularAPN) ?? ""
        cellularStatus = try box.decodeIfPresent(String.self, forKey: .cellularStatus) ?? "off"
        hotspotEnabled = try box.decodeIfPresent(Bool.self, forKey: .hotspotEnabled) ?? false
        hotspotRunning = try box.decodeIfPresent(Bool.self, forKey: .hotspotRunning) ?? false
        hotspotSSID = try box.decodeIfPresent(String.self, forKey: .hotspotSSID) ?? ""
        internetRoute = try box.decodeIfPresent(String.self, forKey: .internetRoute) ?? "NONE"
        bluetoothRSSI = try box.decodeIfPresent(Int.self, forKey: .bluetoothRSSI) ?? -120
        espSleeping = try box.decodeIfPresent(Bool.self, forKey: .espSleeping) ?? false
        latitude = try box.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try box.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        obdConnected = try box.decodeIfPresent(Bool.self, forKey: .obdConnected) ?? ((try compact.decodeIfPresent(Int.self, forKey: .obdConnected) ?? 0) == 1)
        obdStatus = try box.decodeIfPresent(String.self, forKey: .obdStatus) ?? (try compact.decodeIfPresent(String.self, forKey: .obdStatus) ?? "waiting")
        obdResponseRate = try box.decodeIfPresent(Int.self, forKey: .obdResponseRate) ?? (try compact.decodeIfPresent(Int.self, forKey: .obdResponseRate) ?? 0)
        obdTotalResponses = try box.decodeIfPresent(UInt64.self, forKey: .obdTotalResponses) ?? (try compact.decodeIfPresent(UInt64.self, forKey: .obdTotalResponses) ?? 0)
        obdScanProgress = try box.decodeIfPresent(Int.self, forKey: .obdScanProgress) ?? (try compact.decodeIfPresent(Int.self, forKey: .obdScanProgress) ?? 0)
        obdScannedPids = try box.decodeIfPresent(Int.self, forKey: .obdScannedPids) ?? (try compact.decodeIfPresent(Int.self, forKey: .obdScannedPids) ?? 0)
        obdSupportedPids = try box.decodeIfPresent(Int.self, forKey: .obdSupportedPids) ?? (try compact.decodeIfPresent(Int.self, forKey: .obdSupportedPids) ?? 0)
        obdStandardScanComplete = try box.decodeIfPresent(Bool.self, forKey: .obdStandardScanComplete) ?? ((try compact.decodeIfPresent(Int.self, forKey: .obdScanComplete) ?? 0) == 1)
        obdCurrentPid = try box.decodeIfPresent(String.self, forKey: .obdCurrentPid) ?? (try compact.decodeIfPresent(String.self, forKey: .obdCurrentPid) ?? "")
        obdLastReply = try box.decodeIfPresent(String.self, forKey: .obdLastReply) ?? ""
        obdAdapterName = try box.decodeIfPresent(String.self, forKey: .obdAdapterName) ?? (try compact.decodeIfPresent(String.self, forKey: .obdAdapterName) ?? "")
        obdDiscoveredAdapters = try box.decodeIfPresent(String.self, forKey: .obdDiscoveredAdapters) ?? ""
        obdDiscoveredWifiNetworks = try box.decodeIfPresent(String.self, forKey: .obdDiscoveredWifiNetworks) ?? ""
        obdDiscoveryKind = try box.decodeIfPresent(String.self, forKey: .obdDiscoveryKind) ?? ""
        obdDiscoveryReset = try box.decodeIfPresent(Bool.self, forKey: .obdDiscoveryReset) ?? false
        obdDiscoveryDone = try box.decodeIfPresent(Bool.self, forKey: .obdDiscoveryDone) ?? false
        obdClearInProgress = try box.decodeIfPresent(Bool.self, forKey: .obdClearInProgress) ?? false
        rpm = try box.decodeIfPresent(Int.self, forKey: .rpm) ?? (try compact.decodeIfPresent(Int.self, forKey: .rpm) ?? 0)
        speedKph = try box.decodeIfPresent(Int.self, forKey: .speedKph) ?? (try compact.decodeIfPresent(Int.self, forKey: .speed) ?? 0)
        coolantC = try box.decodeIfPresent(Int.self, forKey: .coolantC) ?? (try compact.decodeIfPresent(Int.self, forKey: .coolant) ?? 0)
        intakeAirC = try box.decodeIfPresent(Int.self, forKey: .intakeAirC) ?? 0
        engineLoadPercent = try box.decodeIfPresent(Int.self, forKey: .engineLoadPercent) ?? 0
        throttlePercent = try box.decodeIfPresent(Int.self, forKey: .throttlePercent) ?? 0
        fuelLevelPercent = try box.decodeIfPresent(Int.self, forKey: .fuelLevelPercent) ?? (try compact.decodeIfPresent(Int.self, forKey: .fuelLevel) ?? 0)
        fuelLevelValid = try box.decodeIfPresent(Bool.self, forKey: .fuelLevelValid) ?? ((try compact.decodeIfPresent(Int.self, forKey: .fuelValid) ?? 0) == 1)
        engineRuntimeSeconds = try box.decodeIfPresent(Int.self, forKey: .engineRuntimeSeconds) ?? 0
        controlVoltage = try box.decodeIfPresent(Double.self, forKey: .controlVoltage) ?? 0
        batteryVoltage = try box.decodeIfPresent(Double.self, forKey: .batteryVoltage) ?? (try compact.decodeIfPresent(Double.self, forKey: .batteryVoltage) ?? 0)
        canAwake = try box.decodeIfPresent(Bool.self, forKey: .canAwake) ?? ((try compact.decodeIfPresent(Int.self, forKey: .canAwake) ?? 0) == 1)
        ignitionState = try box.decodeIfPresent(String.self, forKey: .ignitionState) ?? (try compact.decodeIfPresent(String.self, forKey: .ignition) ?? "UNKNOWN")
        diagnosticCodes = try box.decodeIfPresent([String].self, forKey: .diagnosticCodes) ?? []
        lastEvent = try box.decodeIfPresent(String.self, forKey: .lastEvent) ?? (try compact.decodeIfPresent(String.self, forKey: .event) ?? "waiting")
        uptimeSeconds = try box.decodeIfPresent(UInt64.self, forKey: .uptimeSeconds) ?? (try compact.decodeIfPresent(UInt64.self, forKey: .uptime) ?? 0)
        remotePulseMs = try box.decodeIfPresent(Int.self, forKey: .remotePulseMs) ?? 450
        remoteWakeDelayMs = try box.decodeIfPresent(Int.self, forKey: .remoteWakeDelayMs) ?? 1000
        remotePowerOffDelayMs = try box.decodeIfPresent(Int.self, forKey: .remotePowerOffDelayMs) ?? 2000
        hudBrightness = try box.decodeIfPresent(Int.self, forKey: .hudBrightness) ?? 5
        otaAddress = try box.decodeIfPresent(String.self, forKey: .otaAddress) ?? ""
        wifiEnabled = try box.decodeIfPresent(Bool.self, forKey: .wifiEnabled) ?? false
        wifiConnected = try box.decodeIfPresent(Bool.self, forKey: .wifiConnected) ?? false
        wifiSSID = try box.decodeIfPresent(String.self, forKey: .wifiSSID) ?? ""
        wifiRSSI = try box.decodeIfPresent(Int.self, forKey: .wifiRSSI) ?? -120
        wifiIP = try box.decodeIfPresent(String.self, forKey: .wifiIP) ?? ""
        wifiStatus = try box.decodeIfPresent(String.self, forKey: .wifiStatus) ?? "off"
        cloudConnected = try box.decodeIfPresent(Bool.self, forKey: .cloudConnected) ?? false
        wifiDiscoveredNetworks = try box.decodeIfPresent(String.self, forKey: .wifiDiscoveredNetworks) ?? ""
        wifiDiscoveryReset = try box.decodeIfPresent(Bool.self, forKey: .wifiDiscoveryReset) ?? false
        wifiDiscoveryDone = try box.decodeIfPresent(Bool.self, forKey: .wifiDiscoveryDone) ?? false
        maintenanceMode = try box.decodeIfPresent(Bool.self, forKey: .maintenanceMode) ?? false
        powerSaveMode = try box.decodeIfPresent(Int.self, forKey: .powerSaveMode) ?? 0
        powerSaveIdleMinutes = try box.decodeIfPresent(Int.self, forKey: .powerSaveIdleMinutes) ?? 30
        powerSaveActive = try box.decodeIfPresent(Bool.self, forKey: .powerSaveActive) ?? false
    }
}
