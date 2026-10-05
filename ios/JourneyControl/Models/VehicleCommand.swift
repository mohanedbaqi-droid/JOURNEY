import Foundation

enum BenchAction: String, Codable, Hashable {
    case lock
    case unlock
    case start = "remote_start"
    case remotePowerOn = "remote_power_on"
    case remotePowerOff = "remote_power_off"
    /// These are emitted only by the iPhone proximity monitor.  They let the
    /// ESP distinguish automatic entry from a manual tap on the Unlock tile.
    case keylessUnlock = "keyless_unlock"
    case keylessLock = "keyless_lock"
    case keylessPresence = "keyless_presence"
    case doors
    case horn
    case lights
    case leftSignal = "left_signal"
    case rightSignal = "right_signal"
    /// Small BLE-only enrolment message. It avoids sending the whole smart
    /// entry settings payload just to register the owner's phone.
    case ownerStatus = "owner_status"
    case ownerRegister = "owner_register"
    case ownerRequest = "owner_request"
    case ownerApprove = "owner_approve"
    case ownerReject = "owner_reject"
    case ownerRemove = "owner_remove"
    case ownerClear = "owner_clear"
    case keylessConfig = "keyless_config"
    case espSettings = "esp_settings"
    case otaURL = "ota_url"
    case maintenanceMode = "maintenance_mode"
    case powerSave = "power_save"
    case nfcEnroll = "nfc_enroll"
    case nfcForget = "nfc_forget"
    case obdSelect = "obd_select"
    case obdSearch = "obd_search"
    case obdForget = "obd_forget"
    case obdScanDTC = "obd_scan_dtc"
    case obdClearDTC = "obd_clear_dtc"
    case eventAck = "event_ack"
    case wifiConfig = "wifi_config"
    case wifiSearch = "wifi_search"
    case wifiForget = "wifi_forget"
    case cellularConfig = "cellular_config"
    case cellularTest = "cellular_test"
    case cellularForget = "cellular_forget"
    case connectionPriority = "connection_priority"
}

struct KeylessEntryConfig: Codable, Equatable {
    var enabled: Bool
    var unlockDistanceMeters: Double
    var lockDistanceMeters: Double
    var unlockHoldSeconds: Int
    var lockDelaySeconds: Int
    /// Keeps power applied to the spare factory remote while the authenticated
    /// phone is present, then removes it only after the lock sequence finishes.
    var keepRemotePoweredWhilePresent: Bool
    var remoteWakeDelaySeconds: Int
    var remotePowerOffDelaySeconds: Int
}

struct VehicleCommand: Codable {
    let id: String
    let phoneID: String
    let action: BenchAction
    let schema: Int
    let timestamp: Int64
    let keyless: KeylessEntryConfig?
    let presence: KeylessPresence?
    let espSettings: ESPRuntimeSettings?
    let firmwareURL: String?
    let maintenanceMode: Bool?
    let powerSave: PowerSaveSettings?
    let obdAdapter: OBDAdapterSelection?
    let obdClearConfirmed: Bool?
    let ownerTarget: String?
    let wifiSettings: ESPWiFiSettings?
    let cellularSettings: ESPCellularSettings?
    let connectionPriority: ESPConnectionPriority?

    /// BLE commands must stay compact.  Encoding Swift optionals with the
    /// compiler-generated encoder writes every unused field as `null`, which
    /// turns a simple owner-registration command into a long GATT write.  The
    /// ESP accepts omitted optional fields, so omit them on the wire.
    private enum CodingKeys: String, CodingKey {
        case id, phoneID, action, schema, timestamp
        case keyless, presence, espSettings, firmwareURL, maintenanceMode
        case powerSave, obdAdapter, obdClearConfirmed, ownerTarget, wifiSettings, cellularSettings, connectionPriority
    }

    init(action: BenchAction, keyless: KeylessEntryConfig? = nil, presence: KeylessPresence? = nil, espSettings: ESPRuntimeSettings? = nil, firmwareURL: String? = nil, maintenanceMode: Bool? = nil, powerSave: PowerSaveSettings? = nil, obdAdapter: OBDAdapterSelection? = nil, obdClearConfirmed: Bool? = nil, ownerTarget: String? = nil, wifiSettings: ESPWiFiSettings? = nil, cellularSettings: ESPCellularSettings? = nil, connectionPriority: ESPConnectionPriority? = nil) {
        self.id = UUID().uuidString
        self.phoneID = AppConfig.phoneID
        self.action = action
        self.schema = 1
        self.timestamp = Int64(Date().timeIntervalSince1970)
        self.keyless = keyless
        self.presence = presence
        self.espSettings = espSettings
        self.firmwareURL = firmwareURL
        self.maintenanceMode = maintenanceMode
        self.powerSave = powerSave
        self.obdAdapter = obdAdapter
        self.obdClearConfirmed = obdClearConfirmed
        self.ownerTarget = ownerTarget
        self.wifiSettings = wifiSettings
        self.cellularSettings = cellularSettings
        self.connectionPriority = connectionPriority
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(phoneID, forKey: .phoneID)
        try container.encode(action, forKey: .action)
        try container.encode(schema, forKey: .schema)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(keyless, forKey: .keyless)
        try container.encodeIfPresent(presence, forKey: .presence)
        try container.encodeIfPresent(espSettings, forKey: .espSettings)
        try container.encodeIfPresent(firmwareURL, forKey: .firmwareURL)
        try container.encodeIfPresent(maintenanceMode, forKey: .maintenanceMode)
        try container.encodeIfPresent(powerSave, forKey: .powerSave)
        try container.encodeIfPresent(obdAdapter, forKey: .obdAdapter)
        try container.encodeIfPresent(obdClearConfirmed, forKey: .obdClearConfirmed)
        try container.encodeIfPresent(ownerTarget, forKey: .ownerTarget)
        try container.encodeIfPresent(wifiSettings, forKey: .wifiSettings)
        try container.encodeIfPresent(cellularSettings, forKey: .cellularSettings)
        try container.encodeIfPresent(connectionPriority, forKey: .connectionPriority)
    }
}

struct ESPConnectionPriority: Codable, Equatable {
    var order: [String]
}

struct ESPCellularSettings: Codable, Equatable {
    var enabled: Bool
    var apn: String
    var username: String
    var password: String
    var simPin: String
    var hotspotEnabled: Bool
    var hotspotSSID: String
    var hotspotPassword: String
}

struct ESPWiFiSettings: Codable, Equatable {
    var enabled: Bool
    var ssid: String
    var password: String
}

struct KeylessPresence: Codable, Equatable {
    let nearby: Bool
    let rssi: Int
}

struct ESPRuntimeSettings: Codable, Equatable {
    var remotePulseMs: Int
    var remoteWakeDelayMs: Int
    var remotePowerOffDelayMs: Int
    var hudBrightness: Int
}

struct PowerSaveSettings: Codable, Equatable {
    var mode: Int
    var idleMinutes: Int
}

struct OBDAdapterSelection: Codable, Equatable {
    let name: String
    let transport: String
    let password: String
    let host: String
    let port: Int

    init(name: String, transport: String = "BLE", password: String = "", host: String = "192.168.0.10", port: Int = 35000) {
        self.name = name
        self.transport = transport
        self.password = password
        self.host = host
        self.port = port
    }
}

struct BenchEvent: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let icon: String
    let timestamp = Date()

    init(action: BenchAction) {
        switch action {
        case .lock:
            title = JL("إرسال أمر القفل", "Send lock command")
            icon = "lock.fill"
        case .unlock:
            title = JL("إرسال أمر الفتح", "Send unlock command")
            icon = "lock.open.fill"
        case .start:
            title = JL("إرسال أمر التشغيل", "Send start command")
            icon = "power"
        case .remotePowerOn:
            title = JL("تشغيل طاقة الريموت", "Turn remote power on")
            icon = "key.fill"
        case .remotePowerOff:
            title = JL("إطفاء طاقة الريموت", "Turn remote power off")
            icon = "key"
        case .keylessUnlock:
            title = JL("فتح الدخول الذكي", "Smart entry unlock")
            icon = "key.radiowaves.forward"
        case .keylessLock:
            title = JL("قفل الدخول الذكي", "Smart entry lock")
            icon = "key.radiowaves.forward"
        case .keylessPresence:
            title = JL("تحديث وجود الدخول الذكي", "Update smart entry presence")
            icon = "antenna.radiowaves.left.and.right"
        case .doors:
            title = JL("فحص الأبواب", "Test doors")
            icon = "door.left.hand.open"
        case .horn:
            title = JL("فحص الهورن", "Test horn")
            icon = "speaker.wave.3.fill"
        case .lights:
            title = JL("فحص الإضاءة", "Test lights")
            icon = "light.beacon.max.fill"
        case .leftSignal:
            title = JL("فحص إشارة يسار", "Test left turn signal")
            icon = "arrow.turn.up.left"
        case .rightSignal:
            title = JL("فحص إشارة يمين", "Test right turn signal")
            icon = "arrow.turn.up.right"
        case .ownerStatus:
            title = JL("مزامنة حالة المالك", "Sync owner status")
            icon = "person.crop.circle.badge.checkmark"
        case .ownerRegister:
            title = JL("تسجيل جهاز المالك", "Register owner device")
            icon = "person.badge.key.fill"
        case .ownerRequest:
            title = JL("طلب ربط جهاز", "Request device pairing")
            icon = "person.badge.plus"
        case .ownerApprove:
            title = JL("موافقة جهاز مالك", "Approve owner device")
            icon = "person.badge.shield.checkmark"
        case .ownerReject:
            title = JL("رفض جهاز مالك", "Reject owner device")
            icon = "person.badge.minus"
        case .ownerRemove:
            title = JL("حذف جهاز مالك", "Remove owner device")
            icon = "person.badge.minus"
        case .ownerClear:
            title = JL("مسح أجهزة المالك", "Clear owner devices")
            icon = "person.crop.circle.badge.xmark"
        case .keylessConfig:
            title = JL("تحديث إعدادات الدخول الذكي", "Update smart entry settings")
            icon = "key.radiowaves.forward"
        case .espSettings:
            title = JL("تحديث إعدادات ESP", "Update ESP settings")
            icon = "slider.horizontal.3"
        case .otaURL:
            title = JL("تحديث ESP عبر 4G", "Update ESP via 4G")
            icon = "arrow.down.doc"
        case .maintenanceMode:
            title = JL("تغيير وضع الصيانة", "Change maintenance mode")
            icon = "wrench.and.screwdriver.fill"
        case .powerSave:
            title = JL("تغيير توفير الطاقة", "Change power saving")
            icon = "battery.75percent"
        case .nfcEnroll:
            title = JL("إضافة بطاقة NFC", "Add NFC card")
            icon = "wave.3.right.circle.fill"
        case .nfcForget:
            title = JL("حذف بطاقة NFC", "Delete NFC card")
            icon = "trash.fill"
        case .obdSelect:
            title = JL("حفظ قطعة OBD", "Save OBD adapter")
            icon = "point.3.connected.trianglepath.dotted"
        case .obdSearch:
            title = JL("بحث عن قطعة OBD", "Search OBD adapter")
            icon = "magnifyingglass"
        case .obdForget:
            title = JL("نسيان قطعة OBD", "Forget OBD adapter")
            icon = "xmark.circle"
        case .obdScanDTC:
            title = JL("فحص أخطاء OBD", "Scan OBD trouble codes")
            icon = "stethoscope"
        case .obdClearDTC:
            title = JL("مسح أخطاء OBD", "Clear OBD trouble codes")
            icon = "exclamationmark.triangle"
        case .eventAck:
            title = JL("تأكيد استلام حدث ESP", "Confirm ESP event received")
            icon = "checkmark.circle.fill"
        case .wifiConfig:
            title = JL("تحديث Wi-Fi للـESP", "Update ESP Wi-Fi")
            icon = "wifi"
        case .wifiSearch:
            title = JL("بحث شبكات Wi-Fi", "Search Wi-Fi networks")
            icon = "magnifyingglass"
        case .wifiForget:
            title = JL("نسيان شبكة Wi-Fi", "Forget Wi-Fi network")
            icon = "wifi.slash"
        case .cellularConfig:
            title = JL("تحديث إعدادات الشريحة", "Update cellular settings")
            icon = "simcard.fill"
        case .cellularTest:
            title = JL("فحص اتصال الشريحة", "Check cellular connection")
            icon = "antenna.radiowaves.left.and.right"
        case .cellularForget:
            title = JL("مسح إعدادات الشريحة", "Clear cellular settings")
            icon = "simcard"
        case .connectionPriority:
            title = JL("تحديث أولوية الاتصال", "Update connection priority")
            icon = "arrow.up.arrow.down"
        }
    }

    init(title: String, icon: String) {
        self.title = title
        self.icon = icon
    }
}
