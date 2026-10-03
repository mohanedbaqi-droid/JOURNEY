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

    /// BLE commands must stay compact.  Encoding Swift optionals with the
    /// compiler-generated encoder writes every unused field as `null`, which
    /// turns a simple owner-registration command into a long GATT write.  The
    /// ESP accepts omitted optional fields, so omit them on the wire.
    private enum CodingKeys: String, CodingKey {
        case id, phoneID, action, schema, timestamp
        case keyless, presence, espSettings, firmwareURL, maintenanceMode
        case powerSave, obdAdapter, obdClearConfirmed, ownerTarget, wifiSettings
    }

    init(action: BenchAction, keyless: KeylessEntryConfig? = nil, presence: KeylessPresence? = nil, espSettings: ESPRuntimeSettings? = nil, firmwareURL: String? = nil, maintenanceMode: Bool? = nil, powerSave: PowerSaveSettings? = nil, obdAdapter: OBDAdapterSelection? = nil, obdClearConfirmed: Bool? = nil, ownerTarget: String? = nil, wifiSettings: ESPWiFiSettings? = nil) {
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
    }
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
            title = "إرسال أمر القفل"
            icon = "lock.fill"
        case .unlock:
            title = "إرسال أمر الفتح"
            icon = "lock.open.fill"
        case .start:
            title = "إرسال أمر التشغيل"
            icon = "power"
        case .remotePowerOn:
            title = "تشغيل طاقة الريموت"
            icon = "key.fill"
        case .remotePowerOff:
            title = "إطفاء طاقة الريموت"
            icon = "key"
        case .keylessUnlock:
            title = "فتح الدخول الذكي"
            icon = "key.radiowaves.forward"
        case .keylessLock:
            title = "قفل الدخول الذكي"
            icon = "key.radiowaves.forward"
        case .keylessPresence:
            title = "تحديث وجود الدخول الذكي"
            icon = "antenna.radiowaves.left.and.right"
        case .doors:
            title = "فحص الأبواب"
            icon = "door.left.hand.open"
        case .horn:
            title = "فحص الهورن"
            icon = "speaker.wave.3.fill"
        case .lights:
            title = "فحص الإضاءة"
            icon = "light.beacon.max.fill"
        case .leftSignal:
            title = "فحص إشارة يسار"
            icon = "arrow.turn.up.left"
        case .rightSignal:
            title = "فحص إشارة يمين"
            icon = "arrow.turn.up.right"
        case .ownerStatus:
            title = "مزامنة حالة المالك"
            icon = "person.crop.circle.badge.checkmark"
        case .ownerRegister:
            title = "تسجيل جهاز المالك"
            icon = "person.badge.key.fill"
        case .ownerRequest:
            title = "طلب ربط جهاز"
            icon = "person.badge.plus"
        case .ownerApprove:
            title = "موافقة جهاز مالك"
            icon = "person.badge.shield.checkmark"
        case .ownerReject:
            title = "رفض جهاز مالك"
            icon = "person.badge.minus"
        case .ownerRemove:
            title = "حذف جهاز مالك"
            icon = "person.badge.minus"
        case .ownerClear:
            title = "مسح أجهزة المالك"
            icon = "person.crop.circle.badge.xmark"
        case .keylessConfig:
            title = "تحديث إعدادات الدخول الذكي"
            icon = "key.radiowaves.forward"
        case .espSettings:
            title = "تحديث إعدادات ESP"
            icon = "slider.horizontal.3"
        case .otaURL:
            title = "تحديث ESP عبر 4G"
            icon = "arrow.down.doc"
        case .maintenanceMode:
            title = "تغيير وضع الصيانة"
            icon = "wrench.and.screwdriver.fill"
        case .powerSave:
            title = "تغيير توفير الطاقة"
            icon = "battery.75percent"
        case .nfcEnroll:
            title = "إضافة بطاقة NFC"
            icon = "wave.3.right.circle.fill"
        case .nfcForget:
            title = "حذف بطاقة NFC"
            icon = "trash.fill"
        case .obdSelect:
            title = "حفظ قطعة OBD"
            icon = "point.3.connected.trianglepath.dotted"
        case .obdSearch:
            title = "بحث عن قطعة OBD"
            icon = "magnifyingglass"
        case .obdForget:
            title = "نسيان قطعة OBD"
            icon = "xmark.circle"
        case .obdScanDTC:
            title = "فحص أخطاء OBD"
            icon = "stethoscope"
        case .obdClearDTC:
            title = "مسح أخطاء OBD"
            icon = "exclamationmark.triangle"
        case .eventAck:
            title = "تأكيد استلام حدث ESP"
            icon = "checkmark.circle.fill"
        case .wifiConfig:
            title = "تحديث Wi-Fi للـESP"
            icon = "wifi"
        case .wifiSearch:
            title = "بحث شبكات Wi-Fi"
            icon = "magnifyingglass"
        case .wifiForget:
            title = "نسيان شبكة Wi-Fi"
            icon = "wifi.slash"
        }
    }

    init(title: String, icon: String) {
        self.title = title
        self.icon = icon
    }
}
