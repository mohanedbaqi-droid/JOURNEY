#include <Arduino.h>
#include <esp_system.h>
#include <driver/temperature_sensor.h>
#include <math.h>
#include "EspThermalPolicy.h"
#include <ArduinoJson.h>
#include <string>
#include <BLEDevice.h>
#include <BLE2902.h>
#include <BLESecurity.h>
#include "sdkconfig.h"
#if defined(CONFIG_NIMBLE_ENABLED)
#include <host/ble_hs.h>
#endif
#include <Preferences.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <Network.h>
#include <PPP.h>
#include <NetworkClientSecure.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <Update.h>
#include <Wire.h>
#include <TM1637Display.h>
#include <Adafruit_PN532.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

#include "ObdBleService.h"
#include "config.h"

// Internal die temperature; never represents cabin or battery temperature.
temperature_sensor_handle_t espTempSensor = nullptr;
bool espTempHighRange = false;
bool configureEspTempSensor(bool high) {
  if (espTempSensor) {
    temperature_sensor_disable(espTempSensor);
    temperature_sensor_uninstall(espTempSensor);
    espTempSensor = nullptr;
  }
  temperature_sensor_config_t config = TEMPERATURE_SENSOR_CONFIG_DEFAULT(-10, 80);
  if (high) { config.range_min = 50; config.range_max = 125; }
  espTempHighRange = high;
  if (temperature_sensor_install(&config, &espTempSensor) != ESP_OK) return false;
  return temperature_sensor_enable(espTempSensor) == ESP_OK;
}
float readEspTemperature() {
  if (!espTempSensor && !configureEspTempSensor(false)) return NAN;
  float sample = NAN;
  if (temperature_sensor_get_celsius(espTempSensor, &sample) != ESP_OK) {
    // A range error may mean the chip crossed the current range boundary.
    if (!configureEspTempSensor(!espTempHighRange)) return NAN;
    if (temperature_sensor_get_celsius(espTempSensor, &sample) != ESP_OK) return NAN;
  }
  if ((!espTempHighRange && sample >= 75) || (espTempHighRange && sample < 65))
    configureEspTempSensor(!espTempHighRange);
  return sample;
}
float espTemperatureC = 0;
bool espTemperatureValid = false;
float espBatteryVoltage = 0, espBatteryPercent = 0;
bool espBatteryValid = false;
int espThermalLevel = 0;
int espTempWarningC = 50;
uint32_t espHealthAt = 0;
TwoWire batteryWire(1);
bool batteryBusReady = false;

bool readGaugeWord(uint8_t reg, uint16_t& value) {
  batteryWire.beginTransmission(0x36);
  batteryWire.write(reg);
  if (batteryWire.endTransmission(false) != 0) return false;
  if (batteryWire.requestFrom(uint8_t(0x36), uint8_t(2)) != 2) return false;
  value = (uint16_t(batteryWire.read()) << 8) | batteryWire.read();
  return true;
}

NetworkClientSecure tlsClient;
PubSubClient mqtt(tlsClient);
ObdBleService obd;
HardwareSerial modem(1);
WebServer otaServer(80);
TM1637Display hud(TM1637_CLK_PIN, TM1637_DIO_PIN);
Adafruit_PN532 nfc(PN532_IRQ_PIN, PN532_RESET_PIN, &Wire);
BLECharacteristic* bleCommandCharacteristic = nullptr;
BLECharacteristic* bleStateCharacteristic = nullptr;
Preferences preferences;
QueueHandle_t bleCommandQueue = nullptr;

struct BleCommandFrame {
  uint16_t length;
  char bytes[513];
};

struct PulseOutput {
  int pin;
  bool active;
  uint32_t offAt;
};

PulseOutput outputs[] = {
  {LOCK_PIN, false, 0}, {UNLOCK_PIN, false, 0}, {START_PIN, false, 0},
  {DOORS_PIN, false, 0}, {HORN_PIN, false, 0},
  {LIGHTS_PIN, false, 0}, {LEFT_SIGNAL_PIN, false, 0}, {RIGHT_SIGNAL_PIN, false, 0}
};

String commandTopic;
String stateTopic;
String eventTopic;
String lastCommandId;
// أول جهاز مسجل هو المدير؛ كل جهاز جديد يحتاج موافقته.
constexpr uint8_t MAX_AUTHORIZED_PHONES = 10;
struct OwnerPresence {
  String phoneId;
  bool nearby = false;
  uint32_t lastSeenAt = 0;
};
OwnerPresence ownerPhones[MAX_AUTHORIZED_PHONES];
String pendingOwnerPhone;
uint32_t keylessLockDelayMs = KEYLESS_DEFAULT_LOCK_DELAY_MS;
uint32_t lastAnyPhoneNearbyAt = 0;
bool keylessSessionOpen = false;
bool keylessEnabled = false;
bool keylessHadPresence = false;
// v12.54: a manual remote-power OFF must win while the owner remains nearby.
bool manualRemotePowerOffLatch = false;
// Prevent concurrent/re-entrant proximity RESYNC from scheduling duplicate unlocks.
bool keylessUnlockInProgress = false;
bool keylessDepartureLockIssued = false;
bool keylessDisconnectConfirmPending = false;
uint32_t keylessDisconnectConfirmAt = 0;
uint32_t lastKeylessAwayLogAt = 0;
constexpr uint32_t KEYLESS_DISCONNECT_CONFIRM_MS = 20000;
String lastEvent = "boot";
bool locked = true;
bool engineRunning = false;
bool doorsOpen = false;
bool hornActive = false;
bool headlightsOn = false;
bool leftSignalOn = false;
bool rightSignalOn = false;

bool gpsValid = false;
double latitude = 0;
double longitude = 0;
uint32_t gpsFixAt = 0;
uint32_t lastGnssQueryAt = 0;
uint32_t lastStateAt = 0;
uint32_t lastReconnectAt = 0;
String modemLine;
bool remotePowered = false;
volatile bool bleClientConnected = false;
volatile bool bleOwnerSyncPending = false;
int scheduledRemotePulsePin = -1;
uint32_t scheduledRemotePulseAt = 0;
uint32_t remotePowerOffAt = 0;
bool nfcReady = false;
bool nfcEnrollPending = false;
bool nfcLockedUntilDeparture = false;
uint32_t nfcEnrollAt = 0;
String nfcLastUid;
uint32_t nfcLastTapAt = 0;
uint32_t lastNfcPollAt = 0;
uint32_t lastHudAt = 0;
String serialInput;
uint32_t remotePulseMs = OUTPUT_PULSE_MS;
uint32_t remoteWakeDelayMs = REMOTE_POWER_WAKE_DELAY_MS;
uint32_t remotePowerOffDelayMs = REMOTE_POWER_OFF_DELAY_MS;
uint8_t hudBrightness = TM1637_BRIGHTNESS;
bool otaRestartPending = false;
bool maintenanceMode = false;
// 0=off, 1=manual, 2=automatic after the selected idle period.
uint8_t powerSaveMode = 0;
uint16_t powerSaveIdleMinutes = 30;
bool powerSaveActive = false;
uint32_t lastOwnerActivityAt = 0;

// v12.40: durable vehicle-event queue. Events are created by the ESP even when
// the phone/Internet is absent. The oldest unacknowledged event is replayed over
// BLE whenever an owner iPhone is connected, and removed only after event_ack.
constexpr uint8_t MAX_PENDING_VEHICLE_EVENTS = 12;
struct PendingVehicleEvent {
  String id;
  String type;
  String text;
  uint32_t createdUptime = 0;
};
PendingVehicleEvent pendingVehicleEvents[MAX_PENDING_VEHICLE_EVENTS];
uint8_t pendingVehicleEventCount = 0;
uint32_t vehicleEventSequence = 0;
uint32_t lastVehicleEventReplayAt = 0;
constexpr uint32_t VEHICLE_EVENT_REPLAY_MS = 1500;

void persistVehicleEventQueue() {
  JsonDocument q;
  JsonArray a = q.to<JsonArray>();
  for (uint8_t i = 0; i < pendingVehicleEventCount; ++i) {
    JsonObject e = a.add<JsonObject>();
    e["id"] = pendingVehicleEvents[i].id;
    e["type"] = pendingVehicleEvents[i].type;
    e["text"] = pendingVehicleEvents[i].text;
    e["up"] = pendingVehicleEvents[i].createdUptime;
  }
  String encoded;
  serializeJson(q, encoded);
  preferences.putString("eventQueue", encoded);
  preferences.putUInt("eventSeq", vehicleEventSequence);
}

void loadVehicleEventQueue() {
  vehicleEventSequence = preferences.getUInt("eventSeq", 0);
  const String encoded = preferences.getString("eventQueue", "[]");
  JsonDocument q;
  if (deserializeJson(q, encoded)) return;
  for (JsonObject e : q.as<JsonArray>()) {
    if (pendingVehicleEventCount >= MAX_PENDING_VEHICLE_EVENTS) break;
    auto& out = pendingVehicleEvents[pendingVehicleEventCount++];
    out.id = String((const char*)(e["id"] | ""));
    out.type = String((const char*)(e["type"] | ""));
    out.text = String((const char*)(e["text"] | ""));
    out.createdUptime = e["up"] | 0U;
  }
}

void enqueueVehicleEvent(const char* type, const char* text) {
  ++vehicleEventSequence;
  if (pendingVehicleEventCount >= MAX_PENDING_VEHICLE_EVENTS) {
    for (uint8_t i = 1; i < pendingVehicleEventCount; ++i) pendingVehicleEvents[i - 1] = pendingVehicleEvents[i];
    --pendingVehicleEventCount;
  }
  auto& e = pendingVehicleEvents[pendingVehicleEventCount++];
  e.id = String(DEVICE_ID) + "-" + String(vehicleEventSequence);
  e.type = type;
  e.text = text;
  e.createdUptime = millis() / 1000;
  persistVehicleEventQueue();
}

void acknowledgeVehicleEvent(const String& eventId) {
  for (uint8_t i = 0; i < pendingVehicleEventCount; ++i) {
    if (pendingVehicleEvents[i].id != eventId) continue;
    for (uint8_t j = i + 1; j < pendingVehicleEventCount; ++j) pendingVehicleEvents[j - 1] = pendingVehicleEvents[j];
    --pendingVehicleEventCount;
    persistVehicleEventQueue();
    return;
  }
}

// v12.39: the ESP owns vehicle monitoring. The phone is only a viewer.
// These values debounce meaningful transitions and publish them to MQTT when
// Internet is configured, allowing a server/APNs bridge to notify a closed app.
bool vehicleEventBaselineReady = false;
// v12.59 engine event debounce: RPM start must be sustained; stop must remain
// absent for several seconds and vehicle speed must be zero before notifying.
bool engineEventStableState = false;
bool engineEventCandidateState = false;
uint32_t engineEventCandidateSince = 0;
constexpr uint32_t ENGINE_START_CONFIRM_MS = 1200;
constexpr uint32_t ENGINE_STOP_CONFIRM_MS = 7000;
bool previousEngineRunning = false;
bool previousCanAwake = false;
bool highCoolantAlertLatched = false;
bool lowBatteryAlertLatched = false;
uint32_t lastVehicleEventAt = 0;
constexpr int16_t HIGH_COOLANT_ALERT_C = 105;
constexpr float LOW_BATTERY_ALERT_V = 11.7f;

// v12.60 general ESP Wi-Fi. It is OFF by default and is enabled only from
// the iPhone settings. Network scans are one-shot/on-demand so BLE keeps
// priority during normal vehicle use. Credentials are stored in NVS.
bool generalWifiEnabled = false;
String generalWifiSsid;
String generalWifiPassword;
String generalWifiStatus = "off";
String generalWifiDiscoveredNetworks;
bool generalWifiScanRequested = false;
bool generalWifiScanActive = false;
bool generalWifiDiscoveryDirty = false;
uint32_t generalWifiLastConnectAttemptAt = 0;

// v12.62: runtime SIM / cellular settings controlled from the iPhone.
bool cellularEnabled = false;
String cellularApn = "internet";
String cellularUsername;
String cellularPassword;
String cellularSimPin;
String cellularStatus = "disabled";
bool cellularRegistered = false;
bool cellularDataAttached = false;
String cellularNetwork = "غير متاح";
int cellularSignalDbm = -120;
uint32_t lastCellularPollAt = 0;
constexpr uint32_t CELLULAR_POLL_INTERVAL_MS = 15000;
constexpr uint32_t GENERAL_WIFI_RETRY_MS = 10000;

// v12.65: Internet carries normal control whenever MQTT is live; BLE is reserved for keyless/nearby presence.
// ESP cloud uplink priority remains cellular PPP first, then Wi-Fi STA.
bool hotspotEnabled = false;
String hotspotSsid = "JOURNEY-4G";
String hotspotPassword = "";
bool hotspotRunning = false;
enum class InternetRoute : uint8_t { NONE, CELLULAR, WIFI };
// Explicit prototypes are required by Arduino's .ino preprocessor because
// InternetRoute is a sketch-local enum used as a function parameter/return type.
String internetRouteName(InternetRoute route);
InternetRoute chooseInternetRoute();
void applyInternetPriority();
InternetRoute activeInternetRoute = InternetRoute::NONE;
// v12.65: user-configurable priority for normal vehicle commands/uplink.
// Keyless/proximity remains BLE-first regardless of this list.
String connectionPriorityCsv = "CELLULAR,WIFI,BLE";
// True while a Wi-Fi OBD adapter owns the single STA interface. General Wi-Fi
// settings stay saved and resume automatically when OBD returns to BLE.
bool obdWifiStaReserved = false;
enum class CommandSource : uint8_t { BLE, MQTT };

bool settingsReady() {
  return String(MQTT_HOST) != "CHANGE_ME" && String(MQTT_ROOT_CA).length() > 40;
}

void startLocalOta() {
  if (!ENABLE_LOCAL_OTA_AP) return;
  // v12.60: do not keep a SoftAP alive continuously. The HTTP OTA server
  // becomes reachable on the selected Wi-Fi network only while Wi-Fi is ON.
  otaServer.on("/", HTTP_GET, []() {
    otaServer.send(200, "text/plain", "JOURNEY ESP OTA: POST firmware .bin to /update");
  });
  otaServer.on("/update", HTTP_POST,
    []() {
      const bool ok = !Update.hasError();
      otaServer.send(ok ? 200 : 500, "text/plain", ok ? "OK; restarting" : "Update failed");
      if (ok) otaRestartPending = true;
    },
    []() {
      HTTPUpload& upload = otaServer.upload();
      if (upload.status == UPLOAD_FILE_START) {
        if (!Update.begin(UPDATE_SIZE_UNKNOWN)) Update.printError(Serial);
      } else if (upload.status == UPLOAD_FILE_WRITE) {
        if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) Update.printError(Serial);
      } else if (upload.status == UPLOAD_FILE_END) {
        if (!Update.end(true)) Update.printError(Serial);
      }
    }
  );
  otaServer.begin();
  Serial0.println("[OTA] HTTP server ready; enable ESP Wi-Fi from the app to use it");
}

void publishState();
void processCommandPayload(const uint8_t* bytes, size_t length, CommandSource source);
bool queueRemotePress(int pin, bool keepRemotePowered);
void setRemotePower(bool enabled);
void monitorVehicleEvents();
void publishVehicleEvent(const char* type, const char* arabicText);

bool waitForModemLine(const char* expected, uint32_t timeoutMs, String* matched = nullptr) {
  String line;
  const uint32_t started = millis();
  while (millis() - started < timeoutMs) {
    while (modem.available()) {
      const char c = static_cast<char>(modem.read());
      if (c == '\r') continue;
      if (c == '\n') {
        line.trim();
        if (line.startsWith(expected)) {
          if (matched) *matched = line;
          return true;
        }
        if (line.startsWith("ERROR")) return false;
        line = "";
      } else if (line.length() < 300) line += c;
    }
    delay(2);
  }
  return false;
}

bool modemOK(const String& command, uint32_t timeoutMs = 5000) {
  modem.println(command);
  return waitForModemLine("OK", timeoutMs);
}

bool modemQueryLine(const String& command, const char* prefix, String& line, uint32_t timeoutMs = 5000) {
  while (modem.available()) modem.read();
  modem.println(command);
  return waitForModemLine(prefix, timeoutMs, &line);
}

void refreshCellularStatus(bool attachData) {
  if (!cellularEnabled) {
    cellularRegistered = false;
    cellularDataAttached = false;
    cellularNetwork = "غير متاح";
    cellularSignalDbm = -120;
    cellularStatus = "disabled";
    return;
  }
  cellularRegistered = PPP.attached();
  cellularDataAttached = PPP.hasIP();
  cellularSignalDbm = PPP.RSSI();
  const String op = PPP.operatorName();
  cellularNetwork = cellularRegistered ? (op.isEmpty() ? "4G" : op) : "غير متاح";
  cellularStatus = cellularDataAttached ? "data_attached" : (cellularRegistered ? "registered" : "registration_failed");
}

void startCellularPpp() {
  if (!cellularEnabled || PPP.started()) return;
  modem.end();
  delay(50);
  PPP.setApn(cellularApn.c_str());
  if (!cellularSimPin.isEmpty()) PPP.setPin(cellularSimPin.c_str());
  PPP.setPins(MODEM_TX_PIN, MODEM_RX_PIN, -1, -1, ESP_MODEM_FLOW_CONTROL_NONE);
  Serial0.println("[CELL] starting PPP");
  if (!PPP.begin(PPP_MODEM_SIM7600, 1, MODEM_BAUD)) {
    cellularStatus = "data_failed";
    return;
  }
  if (PPP.attached()) {
    PPP.mode(ESP_MODEM_MODE_CMUX);
    PPP.waitStatusBits(ESP_NETIF_CONNECTED_BIT, 15000);
  }
  refreshCellularStatus(true);
}

void stopCellularPpp() {
  if (PPP.started()) PPP.end();
  cellularRegistered = false;
  cellularDataAttached = false;
  cellularStatus = cellularEnabled ? "disconnected" : "disabled";
}

void pollCellular() {
  if (!cellularEnabled) return;
  if (!PPP.started()) startCellularPpp();
  if (millis() - lastCellularPollAt < CELLULAR_POLL_INTERVAL_MS) return;
  lastCellularPollAt = millis();
  refreshCellularStatus(true);
  publishState();
}

void stopHotspot() {
  if (!hotspotRunning) return;
  WiFi.AP.enableNAPT(false);
  WiFi.AP.end();
  hotspotRunning = false;
}

void applyHotspot() {
  if (!hotspotEnabled || !PPP.hasIP()) {
    stopHotspot();
    return;
  }
  if (hotspotRunning) return;
  if (hotspotPassword.length() < 8) { Serial0.println("[HOTSPOT] password_required"); return; }
  IPAddress ap_ip(192, 168, 8, 1);
  IPAddress ap_mask(255, 255, 255, 0);
  IPAddress lease(192, 168, 8, 2);
  IPAddress dns(8, 8, 8, 8);
  WiFi.AP.begin();
  WiFi.AP.config(ap_ip, ap_ip, ap_mask, lease, dns);
  if (!WiFi.AP.create(hotspotSsid.c_str(), hotspotPassword.c_str(), 1, 0, 4)) return;
  if (!WiFi.AP.waitStatusBits(ESP_NETIF_STARTED_BIT, 1500)) return;
  hotspotRunning = WiFi.AP.enableNAPT(true);
  Serial0.printf("[HOTSPOT] %s\n", hotspotRunning ? "ON" : "FAILED");
}

int connectionPriorityRank(const String& route) {
  int rank = 99;
  int start = 0;
  int index = 0;
  while (start <= static_cast<int>(connectionPriorityCsv.length())) {
    int comma = connectionPriorityCsv.indexOf(',', start);
    String token = connectionPriorityCsv.substring(start, comma < 0 ? connectionPriorityCsv.length() : comma);
    token.trim();
    token.toUpperCase();
    if (token == route) return index;
    if (comma < 0) break;
    start = comma + 1;
    ++index;
  }
  return rank;
}

bool validConnectionPriority(const String& csv) {
  return csv.indexOf("BLE") >= 0 && csv.indexOf("CELLULAR") >= 0 && csv.indexOf("WIFI") >= 0;
}

String internetRouteName(InternetRoute route) {
  if (route == InternetRoute::CELLULAR) return "CELLULAR";
  if (route == InternetRoute::WIFI) return "WIFI";
  return "NONE";
}

InternetRoute chooseInternetRoute() {
  const bool cellUp = cellularEnabled && PPP.hasIP();
  const bool wifiUp = generalWifiEnabled && WiFi.status() == WL_CONNECTED;
  if (cellUp && wifiUp) {
    return connectionPriorityRank("CELLULAR") <= connectionPriorityRank("WIFI")
      ? InternetRoute::CELLULAR : InternetRoute::WIFI;
  }
  if (cellUp) return InternetRoute::CELLULAR;
  if (wifiUp) return InternetRoute::WIFI;
  return InternetRoute::NONE;
}

void applyInternetPriority() {
  const InternetRoute desired = chooseInternetRoute();
  if (desired != activeInternetRoute) {
    if (mqtt.connected()) mqtt.disconnect();
    activeInternetRoute = desired;
    if (desired == InternetRoute::CELLULAR) {
      Network.setDefaultInterface(PPP);
      Serial0.println("[NET] CELLULAR priority");
    } else if (desired == InternetRoute::WIFI) {
      Network.setDefaultInterface(WiFi.STA);
      Serial0.println("[NET] WIFI fallback");
    } else {
      Serial0.println("[NET] offline");
    }
  }
  applyHotspot();
}

bool updateFromInternet(const String& url) {
  // Use the ESP32 network stack, not the modem's AT HTTP mode.  That makes one
  // OTA path work over either the configured 4G/PPP link or the configured
  // Wi-Fi link, with no manual stop/start of PPP.
  if (!url.startsWith("https://") || url.indexOf('"') >= 0 || url.indexOf('\r') >= 0 || url.indexOf('\n') >= 0 ||
      chooseInternetRoute() == InternetRoute::NONE) return false;
  if (mqtt.connected()) mqtt.disconnect();
  lastEvent = "ota_internet_connecting";
  publishState();

  NetworkClientSecure downloadClient;
  // The update URL is entered only by the authenticated owner. HTTPS still
  // protects the transfer in transit; certificate pinning can be added once a
  // dedicated Journey firmware host is configured.
  downloadClient.setInsecure();
  HTTPClient http;
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  http.setTimeout(30000);
  if (!http.begin(downloadClient, url)) return false;
  const int code = http.GET();
  const int total = http.getSize();
  if (code != HTTP_CODE_OK || total <= 0 || total > 3145728 || !Update.begin(static_cast<size_t>(total))) {
    http.end();
    return false;
  }
  lastEvent = "ota_internet_downloading";
  publishState();
  const size_t written = Update.writeStream(*http.getStreamPtr());
  http.end();
  if (written != static_cast<size_t>(total) || !Update.end() || !Update.isFinished()) return false;
  lastEvent = "ota_internet_complete";
  publishState();
  otaRestartPending = true;
  return true;
}

void handlePhoneBleDisconnectedForKeyless();

class BleCommandCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const auto value = characteristic->getValue();
    Serial0.printf("[BLE v12.65] write received, bytes=%u\n", static_cast<unsigned>(value.length()));
    if (!bleCommandQueue || value.length() == 0 || value.length() > 512) {
      Serial0.println("[BLE v12.65] command rejected: empty, too large, or queue unavailable");
      return;
    }
    BleCommandFrame frame{};
    frame.length = static_cast<uint16_t>(value.length());
    memcpy(frame.bytes, value.c_str(), frame.length);
    frame.bytes[frame.length] = '\0';
    bool queued = xQueueSend(bleCommandQueue, &frame, 0) == pdTRUE;
    if (!queued) {
      // Never leave the BLE command path permanently wedged. Drop the oldest
      // stale frame and make room for the newest user command.
      BleCommandFrame stale{};
      (void)xQueueReceive(bleCommandQueue, &stale, 0);
      queued = xQueueSend(bleCommandQueue, &frame, 0) == pdTRUE;
      Serial0.printf("[BLE] queue pressure: dropped oldest bytes=%u, newest=%u\n",
                     static_cast<unsigned>(stale.length), static_cast<unsigned>(frame.length));
    }
    Serial0.printf("[BLE] command %s, bytes=%u\n", queued ? "queued" : "queue_error", static_cast<unsigned>(frame.length));
  }
};

class BleServerCallbacks final : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    bleClientConnected = true;
    bleOwnerSyncPending = true;
    Serial0.println("[BLE v12.65] iPhone connected — owner sync queued");
  }

  void onDisconnect(BLEServer*) override {
    bleClientConnected = false;
    Serial0.println("[BLE v12.65] iPhone disconnected — keyless departure timer armed");
    handlePhoneBleDisconnectedForKeyless();
    BLEDevice::startAdvertising();
  }
};

// The spare remote buttons are pulled high internally and are pressed by
// grounding their signal pad.  Keeping the ESP pin as INPUT while idle avoids
// an accidental press during boot and prevents the ESP from driving the
// remote's button line continuously.
void setRemoteButton(int pin, bool pressed) {
  if (pin < 0) return;
  if (pressed) {
    pinMode(pin, OUTPUT);
    digitalWrite(pin, LOW);
  } else {
    pinMode(pin, INPUT);
  }
}

int ownerIndex(const String& phoneId) {
  for (uint8_t i = 0; i < MAX_AUTHORIZED_PHONES; ++i) {
    if (!ownerPhones[i].phoneId.isEmpty() && ownerPhones[i].phoneId == phoneId) return i;
  }
  return -1;
}

bool registerOwner(const String& phoneId) {
  if (ownerIndex(phoneId) >= 0) return true;
  for (uint8_t i = 0; i < MAX_AUTHORIZED_PHONES; ++i) {
    if (ownerPhones[i].phoneId.isEmpty()) {
      ownerPhones[i].phoneId = phoneId;
      preferences.putString((String("owner") + i).c_str(), phoneId);
      // Confirm the flash write now.  A failed NVS write must not make the
      // phone look registered for one screen refresh and disappear on reboot.
      if (preferences.getString((String("owner") + i).c_str(), "") == phoneId) return true;
      ownerPhones[i] = OwnerPresence{};
      return false;
    }
  }
  return false;
}

bool isAdminPhone(const String& phoneId) {
  return !ownerPhones[0].phoneId.isEmpty() && ownerPhones[0].phoneId == phoneId;
}

bool removeGuestOwner(const String& phoneId) {
  // The administrator is intentionally never removed by a remote command.
  for (uint8_t i = 1; i < MAX_AUTHORIZED_PHONES; ++i) {
    if (ownerPhones[i].phoneId == phoneId) {
      ownerPhones[i] = OwnerPresence{};
      preferences.remove((String("owner") + i).c_str());
      return true;
    }
  }
  return false;
}

void clearGuestOwners() {
  for (uint8_t i = 1; i < MAX_AUTHORIZED_PHONES; ++i) {
    ownerPhones[i] = OwnerPresence{};
    preferences.remove((String("owner") + i).c_str());
  }
  pendingOwnerPhone = "";
}

void clearAllOwnersFromSerial() {
  for (uint8_t i = 0; i < MAX_AUTHORIZED_PHONES; ++i) {
    ownerPhones[i] = OwnerPresence{};
    preferences.remove((String("owner") + i).c_str());
  }
  pendingOwnerPhone = "";
  preferences.remove("pendingOwner");
  keylessSessionOpen = false;
  keylessHadPresence = false;
  keylessDisconnectConfirmPending = false;
  Serial0.println("[OWNER RESET] All owner devices cleared. owners=0");
  publishOwnerState();
}

uint8_t ownerCount() {
  uint8_t count = 0;
  for (const auto& owner : ownerPhones) if (!owner.phoneId.isEmpty()) ++count;
  return count;
}

void publishOwnerState() {
  if (!bleStateCharacteristic) return;
  // Compact owner/core packet: designed to fit comfortably in the iPhone BLE
  // notification payload even when ATT MTU is modest. Long JSON field names
  // previously made reconnect owner-sync notifications too large/unreliable.
  JsonDocument d;
  d["p"] = 1;
  d["on"] = 1;
  d["tc"] = ownerCount() > 0 ? 1 : 0;
  d["ac"] = ownerCount();
  d["oa"] = ownerPhones[0].phoneId;
  if (!pendingOwnerPhone.isEmpty()) d["po"] = pendingOwnerPhone;
  d["up"] = millis() / 1000;
  char payload[180];
  const size_t n = serializeJson(d, payload, sizeof(payload));
  if (n > 0 && n < sizeof(payload) - 1) {
    bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(payload), n);
    if (bleClientConnected) bleStateCharacteristic->notify();
    Serial0.printf("[OWNER SYNC] compact bytes=%u owners=%u uptime=%lu\n",
                   static_cast<unsigned>(n), static_cast<unsigned>(ownerCount()), millis() / 1000);
  } else {
    Serial0.printf("[OWNER SYNC] ERROR compact bytes=%u\n", static_cast<unsigned>(n));
  }
}

bool anyOwnerNearby() {
  const uint32_t now = millis();
  bool nearby = false;
  for (auto& owner : ownerPhones) {
    if (owner.nearby && now - owner.lastSeenAt > KEYLESS_PRESENCE_STALE_MS) owner.nearby = false;
    nearby = nearby || owner.nearby;
  }
  return nearby;
}

void handlePhoneBleDisconnectedForKeyless() {
  if (!keylessEnabled) return;
  bool hadNearby = false;
  for (auto& owner : ownerPhones) {
    hadNearby = hadNearby || owner.nearby;
    owner.nearby = false;
  }
  if (hadNearby || keylessSessionOpen || keylessHadPresence) {
    keylessHadPresence = true;
    // Keep the distance-lock state intact. BLE loss arms a SECOND independent
    // confirmation lock 20 s later; reconnecting nearby cancels only this stage.
    keylessDisconnectConfirmPending = true;
    keylessDisconnectConfirmAt = millis() + KEYLESS_DISCONNECT_CONFIRM_MS;
    lastEvent = "keyless_ble_disconnected";
    Serial0.printf("[KEYLESS] BLE lost; lock armed in %lu ms\n",
                   static_cast<unsigned long>(keylessLockDelayMs));
  }
}

// A card is only a second factor. It never enables the remote without a
// recently reported presence from an enrolled phone.
void pollNfc() {
  if (!nfcReady || millis() - lastNfcPollAt < 300) return;
  lastNfcPollAt = millis();
  uint8_t uid[7]{};
  uint8_t length = 0;
  if (!nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &length, 20) ||
      (length != 4 && length != 7)) return;
  String id;
  for (uint8_t i = 0; i < length; ++i) {
    if (uid[i] < 16) id += '0';
    id += String(uid[i], HEX);
  }
  id.toUpperCase();
  if (id == nfcLastUid && millis() - nfcLastTapAt < 2500) return;
  nfcLastUid = id;
  nfcLastTapAt = millis();
  if (nfcEnrollPending) {
    nfcEnrollPending = false;
    preferences.putString("nfcUid", id);
    lastEvent = "nfc_enrolled";
    publishState();
    return;
  }
  if (maintenanceMode) {
    lastEvent = "nfc_disabled_maintenance";
    publishState();
    return;
  }
  if (preferences.getString("nfcUid", "") != id || !anyOwnerNearby()) {
    lastEvent = "nfc_rejected";
    publishState();
    return;
  }
  const bool shouldLock = !locked;
  if (queueRemotePress(shouldLock ? LOCK_PIN : UNLOCK_PIN, !shouldLock)) {
    locked = shouldLock;
    keylessSessionOpen = !shouldLock;
    nfcLockedUntilDeparture = shouldLock;
    if (!shouldLock) lastAnyPhoneNearbyAt = millis();
    lastEvent = shouldLock ? "nfc_lock" : "nfc_unlock";
    publishState();
  }
}

void pollSerialSetup() {
  while (Serial0.available()) {
    const char c = static_cast<char>(Serial0.read());
    if (c == '\r') continue;
    if (c != '\n' && serialInput.length() < 80) { serialInput += c; continue; }
    serialInput.trim();
    if (serialInput == "NFC_ENROLL") {
      nfcEnrollPending = true;
      nfcEnrollAt = millis();
      Serial0.println("[NFC] Tap card within 30 seconds while owner phone is nearby");
    } else if (serialInput == "NFC_FORGET") {
      preferences.remove("nfcUid");
      Serial0.println("[NFC] Card removed");
    } else if (serialInput == "OWNER_RESET_ALL") {
      clearAllOwnersFromSerial();
    } else if (serialInput == "BCM_PROBE" || serialInput == "CAN_MONITOR_START") {
      if (!obd.startCanMonitor()) Serial0.println("[BCM PROBE] start failed: wait until KONNWEI shows connected and no OBD command is pending");
    } else if (serialInput == "CAN_MONITOR_STOP") {
      if (!obd.stopCanMonitor()) Serial0.println("[BCM PROBE] monitor was not active");
    } else if (serialInput.startsWith("ELM:")) {
      String raw = serialInput.substring(4); raw.trim();
      if (!obd.requestElmConsole(raw)) Serial0.println("[ELM LAB] command rejected/busy; wait for OBD connected. ATZ/ATD*/Mode04 are blocked here");
    } else if (serialInput == "BCM_HELP") {
      Serial0.println("[BCM PROBE] Commands: BCM_PROBE, CAN_MONITOR_STOP, ELM:ATI, ELM:ATDP, ELM:ATDPN, ELM:ATH1, ELM:ATH0");
      Serial0.println("[BCM PROBE] ATMA is passive and can only see buses physically wired inside the adapter. This test tells us whether body traffic reaches KONNWEI.");
    }
    serialInput = "";
  }
  if (nfcEnrollPending && millis() - nfcEnrollAt > 30000) nfcEnrollPending = false;
}

void updateHud() {
  if (powerSaveActive) {
    hud.clear();
    return;
  }
  if (millis() - lastHudAt < 500) return;
  lastHudAt = millis();
  const ObdSnapshot& c = obd.snapshot();
  if (!c.connected) {
    const uint8_t dashes[] = {0x40, 0x40, 0x40, 0x40};
    hud.setSegments(dashes);
    return;
  }
  // OBD standard PIDs: speed, coolant and RPM.
  const uint8_t page = (millis() / 3000) % 3;
  if (page == 0)
    hud.showNumberDec(c.speedKph, false);
  else if (page == 1)
    hud.showNumberDec(c.coolantC, false);
  else if (page == 2)
    hud.showNumberDec(c.rpm, false);
  else {
    const uint8_t dashes[] = {0x40, 0x40, 0x40, 0x40};
    hud.setSegments(dashes);
  }
}

void updateKeylessPresenceState() {
  if (maintenanceMode || !keylessEnabled) return;
  const uint32_t now = millis();
  if (anyOwnerNearby()) {
    keylessHadPresence = true;
    keylessDepartureLockIssued = false;
    keylessDisconnectConfirmPending = false;
    keylessDisconnectConfirmAt = 0;
    lastAnyPhoneNearbyAt = now;
    if (nfcLockedUntilDeparture) return;
    // Explicit owner command OFF is authoritative until a genuine departure.
    if (manualRemotePowerOffLatch) return;

    // If the phone is near, the keyless session must be physically consistent:
    // remote powered + car marked unlocked.  Re-send unlock after reconnect or
    // stale state instead of assuming the old session is still valid.
    const bool sessionOutOfSync = !keylessSessionOpen || locked || !remotePowered;
    if (sessionOutOfSync && !keylessUnlockInProgress) {
      Serial0.printf("[KEYLESS] RESYNC needed session=%d locked=%d remote=%d\n",
                     keylessSessionOpen, locked, remotePowered);
      // Reserve this approach session BEFORE power/pulse changes can trigger
      // another state pass from the BLE command task.
      keylessUnlockInProgress = true;
      keylessSessionOpen = true;
      if (queueRemotePress(UNLOCK_PIN, true)) {
        locked = false;
        lastEvent = "keyless_unlock";
        publishState();
      } else {
        keylessSessionOpen = false;
      }
      keylessUnlockInProgress = false;
    }
    return;
  }

  nfcLockedUntilDeparture = false;
  if (manualRemotePowerOffLatch) {
    manualRemotePowerOffLatch = false;
    Serial0.println("[KEYLESS] manual remote-power OFF latch cleared after departure");
  }
  keylessUnlockInProgress = false;
  if (!keylessHadPresence) return;
  const uint32_t awayFor = now - lastAnyPhoneNearbyAt;
  if (now - lastKeylessAwayLogAt >= 1000) {
    lastKeylessAwayLogAt = now;
    Serial0.printf("[KEYLESS] away=%lu/%lu ms session=%d locked=%d\n",
                   static_cast<unsigned long>(awayFor), static_cast<unsigned long>(keylessLockDelayMs),
                   keylessSessionOpen, locked);
  }
  if (awayFor >= keylessLockDelayMs && !keylessDepartureLockIssued) {
    // Stage 1: distance/presence departure lock.
    if (queueRemotePress(LOCK_PIN, false)) {
      keylessDepartureLockIssued = true;
      // One physical lock is enough. Do not send the disconnect-confirm pulse too.
      keylessDisconnectConfirmPending = false;
      keylessDisconnectConfirmAt = 0;
      locked = true;
      doorsOpen = false;
      keylessSessionOpen = false;
      lastEvent = "keyless_lock_departure";
      Serial0.println("[KEYLESS] DEPARTURE LOCK queued=1");
      publishState();
    }
  }

  // Stage 2: if BLE itself stayed disconnected, send one additional physical
  // LOCK press as an independent safety confirmation.
  if (keylessDisconnectConfirmPending && static_cast<int32_t>(now - keylessDisconnectConfirmAt) >= 0) {
    // v12.58: one departure must produce only one physical LOCK pulse.
    if (keylessDepartureLockIssued) {
      keylessDisconnectConfirmPending = false;
      Serial0.println("[KEYLESS] disconnect-confirm satisfied by departure lock");
    } else if (queueRemotePress(LOCK_PIN, false)) {
      keylessDisconnectConfirmPending = false;
      locked = true;
      doorsOpen = false;
      keylessSessionOpen = false;
      lastEvent = "keyless_lock_disconnect_confirm";
      Serial0.println("[KEYLESS] DISCONNECT CONFIRM LOCK queued=1");
      publishState();
    }
  }
}

void updatePowerSaving() {
  const bool shouldSave = powerSaveMode == 1 ||
    (powerSaveMode == 2 && !anyOwnerNearby() && millis() - lastOwnerActivityAt >= powerSaveIdleMinutes * 60000UL);
  if (shouldSave == powerSaveActive) return;
  powerSaveActive = shouldSave;
  if (powerSaveActive) {
    setRemotePower(false);
    hud.clear();
    lastEvent = "power_save_active";
  } else {
    hud.setBrightness(hudBrightness, true);
    lastEvent = "power_save_off";
  }
  publishState();
}

bool remoteOutputActive(int pin) {
  for (const auto &output : outputs) if (output.pin == pin) return output.active;
  return false;
}

void setRemotePower(bool enabled) {
  if (!ENABLE_OUTPUTS || REMOTE_POWER_PIN < 0) return;
  // BD140 is PNP: a LOW on its base enables remote power, while HIGH turns it
  // fully off.  Keep this polarity separate from the optocoupler button pins.
  const bool changed = remotePowered != enabled;
  digitalWrite(REMOTE_POWER_PIN, enabled ? LOW : HIGH);
  remotePowered = enabled;
  Serial0.printf("[REMOTE] GPIO%d (BD140) = %s\n", REMOTE_POWER_PIN, enabled ? "ON (LOW)" : "OFF (HIGH)");
  // v12.37: publish the REAL ESP output state at the exact power transition.
  // The iPhone no longer guesses this state from a button press.
  if (changed) {
    lastEvent = enabled ? "remote_power_actual_on" : "remote_power_actual_off";
    publishState();
  }
}

String remoteButtonEvent(int pin, bool active) {
  String name = "remote_button_";
  if (pin == LOCK_PIN) name += "lock";
  else if (pin == UNLOCK_PIN) name += "unlock";
  else if (pin == START_PIN) name += "start";
  else if (pin == HORN_PIN) name += "alarm";
  else name += "other";
  name += active ? "_on" : "_off";
  return name;
}

bool pulsePin(int pin, uint32_t durationMs) {
  if (!ENABLE_OUTPUTS || pin < 0) return false;
  for (auto &output : outputs) {
    if (output.pin != pin) continue;
    output.active = true;
    output.offAt = millis() + durationMs;
    setRemoteButton(pin, true);
    lastEvent = remoteButtonEvent(pin, true);
    publishState();
    return true;
  }
  return false;
}

bool queueRemotePress(int pin, bool keepRemotePowered) {
  if (!ENABLE_OUTPUTS || pin < 0 || scheduledRemotePulsePin >= 0) return false;
  const bool mustWake = !remotePowered;
  remotePowerOffAt = 0;
  // The optocoupler inputs must see a real, measurable HIGH after the spare
  // remote wakes.  Do this inline instead of relying on a later loop pass.
  // It is intentionally simple and reliable for the 1-second wake sequence.
  if (mustWake) {
    setRemotePower(true);
    delay(remoteWakeDelayMs);
  }
  if (!pulsePin(pin, remotePulseMs)) {
    return false;
  }
  if (pin == START_PIN) {
    // OEM remote start requires two separate presses.
    scheduledRemotePulsePin = START_PIN;
    scheduledRemotePulseAt = millis() + remotePulseMs + 450;
  }
  if (!keepRemotePowered) {
    remotePowerOffAt = millis() + remotePulseMs +
      (pin == START_PIN ? remotePulseMs + 450 : 0) + remotePowerOffDelayMs;
  }
  return true;
}

void updateRemoteSequence() {
  const uint32_t now = millis();
  if (scheduledRemotePulsePin >= 0 && static_cast<int32_t>(now - scheduledRemotePulseAt) >= 0) {
    const int pin = scheduledRemotePulsePin;
    scheduledRemotePulsePin = -1;
    if (!pulsePin(pin, remotePulseMs)) lastEvent = "remote_pulse_failed";
  }
  if (remotePowerOffAt && static_cast<int32_t>(now - remotePowerOffAt) >= 0) {
    remotePowerOffAt = 0;
    setRemotePower(false);
  }
}

void updateOutputs() {
  const uint32_t now = millis();
  for (auto &output : outputs) {
    if (output.active && static_cast<int32_t>(now - output.offAt) >= 0) {
      setRemoteButton(output.pin, false);
      output.active = false;
      lastEvent = remoteButtonEvent(output.pin, false);
      publishState();
      if (output.pin == HORN_PIN) hornActive = false;
      if (output.pin == LEFT_SIGNAL_PIN) leftSignalOn = false;
      if (output.pin == RIGHT_SIGNAL_PIN) rightSignalOn = false;
    }
  }
}

void advertiseBle() {
  BLEDevice::init(DEVICE_ID);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new BleServerCallbacks());
  BLEService* service = server->createService(BLE_SERVICE_UUID);
  bleCommandCharacteristic = service->createCharacteristic(
    BLE_COMMAND_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  // iOS connects and receives notifications, but it does not reliably begin
  // SMP pairing from this app before its first GATT write.  An encrypted-only
  // attribute therefore rejects every command before onWrite() is reached.
  // Keep transport access open and enforce authorization in
  // processCommandPayload(): only the registered owner phone can control the
  // vehicle or OBD after initial enrolment.
  bleCommandCharacteristic->setAccessPermissions(ESP_GATT_PERM_WRITE);
  bleStateCharacteristic = service->createCharacteristic(
    BLE_STATE_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  bleStateCharacteristic->setAccessPermissions(ESP_GATT_PERM_READ);
  bleCommandCharacteristic->setCallbacks(new BleCommandCallbacks());
  bleStateCharacteristic->addDescriptor(new BLE2902());
  service->start();
#if defined(CONFIG_NIMBLE_ENABLED)
  // Configure NimBLE directly: BLESecurity's static state is not link-complete in ESP32 Arduino 3.3.0.
  ble_hs_cfg.sm_io_cap = BLE_HS_IO_NO_INPUT_OUTPUT;
  ble_hs_cfg.sm_bonding = 1;
  ble_hs_cfg.sm_mitm = 0;
  ble_hs_cfg.sm_sc = 1;
  ble_hs_cfg.sm_our_key_dist |= BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
  ble_hs_cfg.sm_their_key_dist |= BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
#else
  BLESecurity* security = new BLESecurity();
  // ESP-IDF GAP values: SC + bond (0x09), no input/output (0x03).
  security->setAuthenticationMode(0x09);
  security->setCapability(0x03);
#endif
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void addDiagnosticCodes(JsonDocument& doc, const String& codes) {
  JsonArray values = doc["diagnosticCodes"].to<JsonArray>();
  int start = 0;
  while (start < static_cast<int>(codes.length())) {
    const int comma = codes.indexOf(',', start);
    String code = codes.substring(start, comma < 0 ? codes.length() : comma);
    code.trim();
    if (!code.isEmpty()) values.add(code);
    if (comma < 0) break;
    start = comma + 1;
  }
}

void publishVehicleEvent(const char* type, const char* arabicText) {
  const ObdSnapshot& c = obd.snapshot();
  lastEvent = type;
  lastVehicleEventAt = millis();
  enqueueVehicleEvent(type, arabicText);
  // BLE receives the same authoritative transition immediately when nearby.
  publishState();
  // Internet path: server subscribes to journey/<DEVICE_ID>/events and turns
  // this event into an APNs push. MQTT is intentionally non-retained so an old
  // ENGINE_STARTED event is never delivered as if it just happened.
  if (mqtt.connected() && !eventTopic.isEmpty()) {
    JsonDocument e;
    e["deviceId"] = DEVICE_ID;
    e["event"] = type;
    e["text"] = arabicText;
    e["rpm"] = c.rpm;
    e["speedKph"] = c.speedKph;
    e["coolantC"] = c.coolantC;
    e["batteryVoltage"] = c.batteryVoltage;
    e["canAwake"] = c.canAwake;
    e["engineRunning"] = c.engineRunning;
    e["uptimeSeconds"] = millis() / 1000;
    char payload[384];
    const size_t n = serializeJson(e, payload, sizeof(payload));
    if (n > 0 && n < sizeof(payload) - 1) mqtt.publish(eventTopic.c_str(), reinterpret_cast<const uint8_t*>(payload), n, false);
  }
}

void monitorVehicleEvents() {
  const ObdSnapshot& c = obd.snapshot();
  if (obd.recoveringBcm() || !c.rpmValid) {
    engineEventCandidateSince = millis();
    return;
  }
  if (!vehicleEventBaselineReady) {
    previousEngineRunning = c.engineRunning;
    engineEventStableState = c.engineRunning || c.rpm > 0;
    engineEventCandidateState = engineEventStableState;
    engineEventCandidateSince = millis();
    previousCanAwake = c.canAwake;
    vehicleEventBaselineReady = true;
    return;
  }

  // v12.59: debounce engine transitions. A transient missed RPM/OBD reply must
  // never produce start/stop/start while the car is being driven.
  const uint32_t now = millis();
  const bool rawEngine = c.engineRunning || c.rpm > 0;
  if (rawEngine != engineEventCandidateState) {
    engineEventCandidateState = rawEngine;
    engineEventCandidateSince = now;
  }

  const uint32_t requiredStableMs = engineEventCandidateState
    ? ENGINE_START_CONFIRM_MS : ENGINE_STOP_CONFIRM_MS;
  const bool candidateStableLongEnough = now - engineEventCandidateSince >= requiredStableMs;
  const bool stopAllowed = engineEventCandidateState || c.speedKph == 0;

  if (engineEventCandidateState != engineEventStableState &&
      candidateStableLongEnough && stopAllowed) {
    engineEventStableState = engineEventCandidateState;
    previousEngineRunning = engineEventStableState;
    publishVehicleEvent(engineEventStableState ? "engine_started_obd" : "engine_stopped_obd",
                        engineEventStableState ? "تم تشغيل السيارة" : "تم إطفاء السيارة");
  }
  if (c.canAwake != previousCanAwake) {
    previousCanAwake = c.canAwake;
    // CAN transitions are useful state, but engine start/stop remains the user-facing event.
    lastEvent = c.canAwake ? "can_awake" : "can_sleep";
  }

  if (c.canAwake && c.coolantC >= HIGH_COOLANT_ALERT_C) {
    if (!highCoolantAlertLatched) {
      highCoolantAlertLatched = true;
      publishVehicleEvent("coolant_high", "تحذير: حرارة المحرك مرتفعة");
    }
  } else if (c.coolantC > 0 && c.coolantC <= HIGH_COOLANT_ALERT_C - 5) {
    highCoolantAlertLatched = false;
  }

  if (c.batteryVoltage > 5.0f && c.batteryVoltage < LOW_BATTERY_ALERT_V) {
    if (!lowBatteryAlertLatched) {
      lowBatteryAlertLatched = true;
      publishVehicleEvent("battery_low", "تحذير: فولت بطارية السيارة منخفض");
    }
  } else if (c.batteryVoltage >= LOW_BATTERY_ALERT_V + 0.3f) {
    lowBatteryAlertLatched = false;
  }
}

void pollEspHealth() {
  if (espHealthAt != 0 && millis() - espHealthAt < 2000) return;
  espHealthAt = millis();
  float sample = readEspTemperature();
  espTemperatureValid = isfinite(sample) && sample >= -40 && sample <= 125;
  if (espTemperatureValid) {
    espTemperatureC = sample;
    // Operational warning thresholds, not a claim about hardware safe limits.
    int next = espThermalNextLevel(sample, espThermalLevel, espTempWarningC);
    if (next > espThermalLevel) publishVehicleEvent(
      next == 2 ? "esp_temperature_critical" : "esp_temperature_high",
      next == 2 ? "تحذير: حرارة شريحة ESP مرتفعة جداً — افحص التهوية والتغذية" : "تنبيه: حرارة شريحة ESP مرتفعة — افحص التهوية");
    espThermalLevel = next;
  }
  espBatteryValid = false;
  if (ESP_BATTERY_GAUGE_ENABLED && batteryBusReady) {
    uint16_t voltage, soc;
    if (readGaugeWord(0x02, voltage) && readGaugeWord(0x04, soc)) {
      float v = voltage * 0.000078125f;
      float percent = soc / 256.0f;
      if (v >= 2.5f && v <= 4.5f && percent >= 0 && percent <= 100.5f) {
        espBatteryVoltage = v; espBatteryPercent = min(percent, 100.0f); espBatteryValid = true;
      }
    }
  }
}

void addEspHealth(JsonDocument& doc) {
  doc["firmwareVersion"] = "12.78";
  bool fresh = espHealthAt != 0 && millis() - espHealthAt <= 10000;
  doc["espTemperatureValid"] = espTemperatureValid && fresh;
  if (espTemperatureValid && fresh) doc["espTemperatureC"] = roundf(espTemperatureC * 10) / 10;
  doc["espTempWarningC"] = espTempWarningC;
  doc["espThermalLevel"] = espTemperatureValid && fresh ? espThermalLevel : -1;
  doc["espBatteryValid"] = espBatteryValid && fresh;
  if (espBatteryValid && fresh) {
    doc["espBatteryVoltage"] = espBatteryVoltage;
    doc["espBatteryPercent"] = espBatteryPercent;
  }
  doc["espResetReason"] = int(esp_reset_reason());
}

void publishState() {
  const ObdSnapshot& c = obd.snapshot();
  JsonDocument doc;
  addEspHealth(doc);
  doc["online"] = true;
  doc["benchMode"] = false;
  // v12.66: body UI now uses confirmed BCM readings whenever available.
  // Manual/keyless state remains the fallback until the BCM reader has a valid frame.
  const bool liveLocked = c.doorsValid ? c.locked : locked;
  const bool liveDoorsOpen = c.doorsValid ? c.doorsOpen : doorsOpen;
  const bool liveHeadlightsOn = c.lightsValid ? c.headlightsOn : headlightsOn;
  const bool liveLeftSignalOn = c.turnsValid ? c.leftSignalOn : leftSignalOn;
  const bool liveRightSignalOn = c.turnsValid ? c.rightSignalOn : rightSignalOn;
  doc["simulatedLocked"] = liveLocked;
  doc["simulatedEngineRunning"] = c.connected && c.rpmValid && c.engineRunning;
  doc["simulatedDoorsOpen"] = liveDoorsOpen;
  doc["hornActive"] = hornActive;
  doc["headlightsOn"] = liveHeadlightsOn;
  doc["leftSignalOn"] = liveLeftSignalOn;
  doc["rightSignalOn"] = liveRightSignalOn;
  doc["bcmStateValid"] = c.bcmStateValid;
  doc["gpsValid"] = gpsValid && millis() - gpsFixAt < GPS_FIX_MAX_AGE_MS;
  doc["latitude"] = latitude;
  doc["longitude"] = longitude;
  doc["obdConnected"] = c.connected;
  doc["obdStatus"] = obd.statusText();
  doc["obdResponseRate"] = c.responseRate;
  doc["obdTotalResponses"] = c.totalResponses;
  doc["obdScanProgress"] = c.scanProgress;
  doc["obdScannedPids"] = c.scannedPids;
  doc["obdSupportedPids"] = c.supportedPids;
  doc["obdStandardScanComplete"] = c.standardScanComplete;
  doc["obdCurrentPid"] = c.currentPid;
  doc["obdLastReply"] = c.lastReply;
  doc["obdAdapterName"] = c.adapterName;
  doc["obdVin"] = c.vin;
  doc["obdPendingDiagnosticCodes"] = c.pendingDiagnosticCodes;
  doc["obdPermanentDiagnosticCodes"] = c.permanentDiagnosticCodes;
  doc["obdDiscoveredAdapters"] = c.discoveredAdapters;
  doc["obdDiscoveredWifiNetworks"] = c.discoveredWifiNetworks;
  doc["obdClearInProgress"] = c.clearInProgress;
  addDiagnosticCodes(doc, c.diagnosticCodes);
  doc["readDiagnostics"] = c.readDiagnostics;
  doc["speedValid"] = c.speedValid;
  doc["rpmValid"] = c.rpmValid;
  doc["coolantValid"] = c.coolantValid;
  doc["doorOpenMask"] = c.doorOpenMask;
  doc["doorKnownMask"] = c.doorKnownMask;
  doc["parkingLightsOn"] = c.parkingLightsOn;
  doc["parkingLightsValid"] = c.lightsValid;
  doc["doorsValid"] = c.doorsValid;
  doc["lightsValid"] = c.lightsValid;
  doc["turnsValid"] = c.turnsValid;
  doc["rpm"] = c.rpm;
  doc["speedKph"] = c.speedKph;
  doc["coolantC"] = c.coolantC;
  doc["intakeAirC"] = c.intakeAirC;
  doc["engineLoadPercent"] = c.engineLoadPercent;
  doc["throttlePercent"] = c.throttlePercent;
  doc["fuelLevelPercent"] = c.fuelLevelPercent;
  doc["batteryVoltage"] = c.batteryVoltage;
  doc["canAwake"] = c.canAwake;
  doc["ignitionState"] = c.ignitionState;
  doc["remotePowered"] = remotePowered;
  doc["remotePulseMs"] = remotePulseMs;
  doc["remoteWakeDelayMs"] = remoteWakeDelayMs;
  doc["remotePowerOffDelayMs"] = remotePowerOffDelayMs;
  doc["hudBrightness"] = hudBrightness;
  doc["otaAddress"] = (WiFi.status() == WL_CONNECTED) ? (String("http://") + WiFi.localIP().toString()) : "";
  doc["wifiEnabled"] = generalWifiEnabled;
  doc["wifiConnected"] = WiFi.status() == WL_CONNECTED;
  doc["wifiSSID"] = (WiFi.status() == WL_CONNECTED) ? WiFi.SSID() : generalWifiSsid;
  doc["wifiRSSI"] = (WiFi.status() == WL_CONNECTED) ? WiFi.RSSI() : -120;
  doc["wifiIP"] = (WiFi.status() == WL_CONNECTED) ? WiFi.localIP().toString() : "";
  doc["wifiStatus"] = generalWifiStatus;
  doc["cloudConnected"] = mqtt.connected();
  doc["maintenanceMode"] = maintenanceMode;
  doc["powerSaveMode"] = powerSaveMode;
  doc["powerSaveIdleMinutes"] = powerSaveIdleMinutes;
  doc["powerSaveActive"] = powerSaveActive;
  doc["cellularEnabled"] = cellularEnabled;
  doc["cellularRegistered"] = cellularRegistered;
  doc["cellularDataAttached"] = cellularDataAttached;
  doc["cellularAPN"] = cellularApn;
  doc["cellularStatus"] = cellularStatus;
  doc["cellularNetwork"] = cellularNetwork;
  doc["cellularSignalDBm"] = cellularSignalDbm;
  doc["hotspotEnabled"] = hotspotEnabled;
  doc["hotspotRunning"] = hotspotRunning;
  doc["hotspotSSID"] = hotspotSsid;
  doc["internetRoute"] = activeInternetRoute == InternetRoute::CELLULAR ? "CELLULAR" : (activeInternetRoute == InternetRoute::WIFI ? "WIFI" : "NONE");
  doc["connectionPriority"] = connectionPriorityCsv;
  doc["trustedPhoneConfigured"] = ownerCount() > 0;
  doc["authorizedPhoneCount"] = ownerCount();
  doc["ownerAdminPhone"] = ownerPhones[0].phoneId;
  doc["pendingOwnerPhone"] = pendingOwnerPhone;
  doc["lastEvent"] = lastEvent;
  doc["uptimeSeconds"] = millis() / 1000;

  char payload[4096];
  const size_t written = serializeJson(doc, payload, sizeof(payload));
  if (bleStateCharacteristic) {
    // Owner/admin + uptime always goes first in a compact BLE-safe packet.
    publishOwnerState();
    JsonDocument healthDoc;
    healthDoc["partialState"] = true;
    healthDoc["espHealthPacket"] = true;
    addEspHealth(healthDoc);
    char healthPayload[512];
    size_t healthBytes = serializeJson(healthDoc, healthPayload, sizeof(healthPayload));
    if (healthBytes > 0 && healthBytes < sizeof(healthPayload) - 1) {
      delay(15);
      bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(healthPayload), healthBytes);
      bleStateCharacteristic->notify();
    }
    delay(15); // v12.54: pace notifications so iOS does not lose the following telemetry packet.
    // Send operational core state separately. This packet contains the fields
    // needed by the iPhone for owner registration and keyless state and is kept
    // comfortably below the 512-byte application buffer.
    JsonDocument coreDoc;
    coreDoc["partialState"] = true;
    coreDoc["coreStatePacket"] = true;
    coreDoc["online"] = true;
    coreDoc["remotePowered"] = remotePowered;
    coreDoc["simulatedLocked"] = liveLocked;
    coreDoc["simulatedDoorsOpen"] = liveDoorsOpen;
    coreDoc["headlightsOn"] = liveHeadlightsOn;
    coreDoc["leftSignalOn"] = liveLeftSignalOn;
    coreDoc["rightSignalOn"] = liveRightSignalOn;
    coreDoc["bcmStateValid"] = c.bcmStateValid;
    coreDoc["simulatedEngineRunning"] = c.connected && c.rpmValid && c.engineRunning;
    coreDoc["lastEvent"] = lastEvent;
    coreDoc["keylessSessionOpen"] = keylessSessionOpen;
    coreDoc["ownerNearby"] = anyOwnerNearby();
    coreDoc["maintenanceMode"] = maintenanceMode;
    coreDoc["cloudConnected"] = mqtt.connected();
    // v12.56: explicit real-time feedback bits; iOS no longer reconstructs button state from sticky lastEvent.
    coreDoc["feedbackLock"] = remoteOutputActive(LOCK_PIN);
    coreDoc["feedbackUnlock"] = remoteOutputActive(UNLOCK_PIN);
    coreDoc["feedbackStart"] = remoteOutputActive(START_PIN);
    coreDoc["feedbackAlarm"] = remoteOutputActive(HORN_PIN);

    char corePayload[512];
    const size_t coreWritten = serializeJson(coreDoc, corePayload, sizeof(corePayload));
    if (coreWritten > 0 && coreWritten < sizeof(corePayload) - 1) {
      bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(corePayload), coreWritten);
      bleStateCharacteristic->notify();
      delay(15);
      Serial0.printf("[BLE] core state bytes=%u owners=%u event=%s\n",
                     static_cast<unsigned>(coreWritten), static_cast<unsigned>(ownerCount()), lastEvent.c_str());
    } else {
      Serial0.printf("[BLE] ERROR core state too large bytes=%u\n", static_cast<unsigned>(coreWritten));
    }

    // Replay the oldest pending event over BLE until the iPhone acknowledges it.
    // This makes nearby notifications independent of Internet availability and
    // also delivers events that happened while the phone was temporarily away.
    if (pendingVehicleEventCount > 0 && millis() - lastVehicleEventReplayAt >= VEHICLE_EVENT_REPLAY_MS) {
      lastVehicleEventReplayAt = millis();
      const auto& pe = pendingVehicleEvents[0];
      JsonDocument eventDoc;
      eventDoc["partialState"] = true;
      eventDoc["vehicleEventPacket"] = true;
      eventDoc["vehicleEventId"] = pe.id;
      eventDoc["vehicleEventType"] = pe.type;
      eventDoc["vehicleEventText"] = pe.text;
      eventDoc["vehicleEventUptime"] = pe.createdUptime;
      char eventPayload[320];
      const size_t eventWritten = serializeJson(eventDoc, eventPayload, sizeof(eventPayload));
      if (eventWritten > 0 && eventWritten < sizeof(eventPayload) - 1) {
        bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(eventPayload), eventWritten);
        bleStateCharacteristic->notify();
        delay(15);
      }
    }

    // v12.60: general ESP Wi-Fi state is independent from OBD Wi-Fi.
    JsonDocument wifiDoc;
    wifiDoc["partialState"] = true;
    wifiDoc["wifiStatePacket"] = true;
    wifiDoc["wifiEnabled"] = generalWifiEnabled;
    wifiDoc["wifiConnected"] = WiFi.status() == WL_CONNECTED;
    wifiDoc["wifiSSID"] = (WiFi.status() == WL_CONNECTED) ? WiFi.SSID() : generalWifiSsid;
    wifiDoc["wifiRSSI"] = (WiFi.status() == WL_CONNECTED) ? WiFi.RSSI() : -120;
    wifiDoc["wifiIP"] = (WiFi.status() == WL_CONNECTED) ? WiFi.localIP().toString() : "";
    wifiDoc["wifiStatus"] = generalWifiStatus;
    wifiDoc["otaAddress"] = (WiFi.status() == WL_CONNECTED) ? (String("http://") + WiFi.localIP().toString()) : "";
    char wifiPayload[360];
    const size_t wifiWritten = serializeJson(wifiDoc, wifiPayload, sizeof(wifiPayload));
    if (wifiWritten > 0 && wifiWritten < sizeof(wifiPayload) - 1) {
      bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(wifiPayload), wifiWritten);
      bleStateCharacteristic->notify();
      delay(12);
    }

    JsonDocument cellularDoc;
    cellularDoc["partialState"] = true;
    cellularDoc["cellularStatePacket"] = true;
    cellularDoc["cellularEnabled"] = cellularEnabled;
    cellularDoc["cellularRegistered"] = cellularRegistered;
    cellularDoc["cellularDataAttached"] = cellularDataAttached;
    cellularDoc["cellularAPN"] = cellularApn;
    cellularDoc["cellularStatus"] = cellularStatus;
    cellularDoc["cellularNetwork"] = cellularNetwork;
    cellularDoc["cellularSignalDBm"] = cellularSignalDbm;
    cellularDoc["hotspotEnabled"] = hotspotEnabled;
    cellularDoc["hotspotRunning"] = hotspotRunning;
    cellularDoc["hotspotSSID"] = hotspotSsid;
    cellularDoc["internetRoute"] = activeInternetRoute == InternetRoute::CELLULAR ? "CELLULAR" : (activeInternetRoute == InternetRoute::WIFI ? "WIFI" : "NONE");
    cellularDoc["connectionPriority"] = connectionPriorityCsv;
    char cellularPayload[360];
    const size_t cellularWritten = serializeJson(cellularDoc, cellularPayload, sizeof(cellularPayload));
    if (cellularWritten > 0 && cellularWritten < sizeof(cellularPayload) - 1) {
      bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(cellularPayload), cellularWritten);
      bleStateCharacteristic->notify();
      delay(12);
    }

    // Independent body packet: no combined BCM gate and no 512-byte core growth.
    JsonDocument bodyDoc;
    bodyDoc["bp"]=1;
    bodyDoc["dm"]=c.doorOpenMask; bodyDoc["dk"]=c.doorKnownMask;
    bodyDoc["pl"]=c.parkingLightsOn; bodyDoc["pv"]=c.lightsValid;
    bodyDoc["dv"]=c.doorsValid; bodyDoc["lv"]=c.lightsValid; bodyDoc["iv"]=c.turnsValid;
    bodyDoc["do"]=c.doorsOpen?1:0; bodyDoc["lk"]=c.locked?1:0;
    bodyDoc["lo"]=c.headlightsOn; bodyDoc["il"]=c.leftSignalOn; bodyDoc["ir"]=c.rightSignalOn;
    bodyDoc["dg"]=c.readDiagnostics;
    char bodyPayload[384];
    const size_t bodyWritten=serializeJson(bodyDoc,bodyPayload,sizeof(bodyPayload));
    if(bodyWritten && bodyWritten<sizeof(bodyPayload)-1) {
      bleStateCharacteristic->setValue((uint8_t*)bodyPayload,bodyWritten);
      bleStateCharacteristic->notify(); delay(12);
    }
    Serial0.printf("[JOURNEY READ] rpm=%u valid=%d door=%d/%d lamp=%d/%d L=%d R=%d turnValid=%d %s\n",
      c.rpm,c.rpmValid,c.doorsOpen,c.doorsValid,c.headlightsOn,c.lightsValid,c.leftSignalOn,c.rightSignalOn,c.turnsValid,c.readDiagnostics.c_str());

    // Send OBD telemetry as a second partial packet. The app can merge it, but
    // a large OBD/discovery payload can no longer block the keyless/owner state.
    JsonDocument teleDoc;
    // v12.55 compact OBD packet. Short keys keep the notification well below
    // the practical iPhone BLE payload instead of overflowing the old 384-byte JSON.
    teleDoc["ot"] = 1;
    teleDoc["oc"] = c.connected ? 1 : 0;
    teleDoc["os"] = obd.statusText();
    teleDoc["rr"] = c.responseRate;
    teleDoc["tr"] = c.totalResponses;
    teleDoc["sp"] = c.scannedPids;
    teleDoc["su"] = c.supportedPids;
    teleDoc["pg"] = c.scanProgress;
    teleDoc["sc"] = c.standardScanComplete ? 1 : 0;
    teleDoc["cp"] = c.currentPid;
    teleDoc["an"] = c.adapterName;
    teleDoc["r"] = c.rpm;
    teleDoc["v"] = c.speedKph;
    teleDoc["sv"] = c.speedValid;
    teleDoc["rv"] = c.rpmValid;
    teleDoc["tv"] = c.coolantValid;
    teleDoc["t"] = c.coolantC;
    teleDoc["fl"] = c.fuelLevelPercent;
    teleDoc["fv"] = c.fuelLevelValid ? 1 : 0;
    teleDoc["bv"] = c.batteryVoltage;
    teleDoc["ca"] = c.canAwake ? 1 : 0;
    teleDoc["ig"] = c.ignitionState;
    char telePayload[320];
    const size_t teleWritten = serializeJson(teleDoc, telePayload, sizeof(telePayload));
    if (teleWritten > 0 && teleWritten < sizeof(telePayload) - 1) {
      bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(telePayload), teleWritten);
      bleStateCharacteristic->notify();
      Serial0.printf("[BLE OBD] telemetry bytes=%u connected=%d rpm=%u speed=%u coolant=%d V=%.2f progress=%u\n",
                     static_cast<unsigned>(teleWritten), c.connected, c.rpm, c.speedKph, c.coolantC, c.batteryVoltage, c.scanProgress);
      delay(15);
    } else {
      Serial0.printf("[BLE OBD] ERROR telemetry too large bytes=%u\n", static_cast<unsigned>(teleWritten));
    }

    // Discovery is sent in small chunks so ALL nearby BLE advertisers can reach
    // the phone without overflowing one notification. Entries are split only
    // at " | " boundaries, so UTF-8 names and MAC addresses stay intact.
    auto sendDiscoveryChunks = [&](const String& list, const char* kind) {
      if (list.isEmpty()) return;
      String remaining = list;
      bool firstChunk = true;
      uint16_t chunkNo = 0;
      while (!remaining.isEmpty() && chunkNo < 40) {
        int cut = min(170, static_cast<int>(remaining.length()));
        if (cut < static_cast<int>(remaining.length())) {
          const int boundary = remaining.lastIndexOf(" | ", cut);
          if (boundary > 0) cut = boundary;
        }
        String chunk = remaining.substring(0, cut);
        remaining.remove(0, cut);
        if (remaining.startsWith(" | ")) remaining.remove(0, 3);

        JsonDocument discoveryDoc;
        discoveryDoc["partialState"] = true;
        discoveryDoc["obdDiscoveryKind"] = kind;
        discoveryDoc["obdDiscoveryReset"] = firstChunk;
        discoveryDoc["obdDiscoveryDone"] = remaining.isEmpty();
        discoveryDoc["obdStatus"] = obd.statusText();
        discoveryDoc["obdAdapterName"] = c.adapterName;
        if (String(kind) == "BLE") discoveryDoc["obdDiscoveredAdapters"] = chunk;
        else discoveryDoc["obdDiscoveredWifiNetworks"] = chunk;

        char discoveryPayload[448];
        const size_t discoveryWritten = serializeJson(discoveryDoc, discoveryPayload, sizeof(discoveryPayload));
        if (discoveryWritten > 0 && discoveryWritten < sizeof(discoveryPayload) - 1) {
          bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(discoveryPayload), discoveryWritten);
          bleStateCharacteristic->notify();
          Serial0.printf("[BLE] discovery %s chunk=%u bytes=%u done=%d\n",
                         kind, static_cast<unsigned>(chunkNo + 1),
                         static_cast<unsigned>(discoveryWritten), remaining.isEmpty());
          delay(12);
        } else {
          Serial0.printf("[BLE] discovery %s chunk skipped, bytes=%u\n",
                         kind, static_cast<unsigned>(discoveryWritten));
          break;
        }
        firstChunk = false;
        ++chunkNo;
      }
    };
    sendDiscoveryChunks(c.discoveredAdapters, "BLE");
    sendDiscoveryChunks(c.discoveredWifiNetworks, "WIFI");

    if (generalWifiDiscoveryDirty) {
      String remaining = generalWifiDiscoveredNetworks;
      bool firstChunk = true;
      uint16_t chunkNo = 0;
      if (remaining.isEmpty()) {
        JsonDocument emptyDoc;
        emptyDoc["partialState"] = true;
        emptyDoc["wifiStatePacket"] = true;
        emptyDoc["wifiDiscoveryReset"] = true;
        emptyDoc["wifiDiscoveryDone"] = true;
        emptyDoc["wifiDiscoveredNetworks"] = "";
        emptyDoc["wifiStatus"] = generalWifiStatus;
        char emptyPayload[280];
        const size_t n = serializeJson(emptyDoc, emptyPayload, sizeof(emptyPayload));
        if (n > 0 && n < sizeof(emptyPayload)-1) {
          bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(emptyPayload), n);
          bleStateCharacteristic->notify();
        }
      }
      while (!remaining.isEmpty() && chunkNo < 40) {
        int cut = min(170, static_cast<int>(remaining.length()));
        if (cut < static_cast<int>(remaining.length())) {
          const int boundary = remaining.lastIndexOf(" | ", cut);
          if (boundary > 0) cut = boundary;
        }
        String chunk = remaining.substring(0, cut);
        remaining.remove(0, cut);
        if (remaining.startsWith(" | ")) remaining.remove(0, 3);
        JsonDocument wifiDiscoveryDoc;
        wifiDiscoveryDoc["partialState"] = true;
        wifiDiscoveryDoc["wifiStatePacket"] = true;
        wifiDiscoveryDoc["wifiDiscoveryReset"] = firstChunk;
        wifiDiscoveryDoc["wifiDiscoveryDone"] = remaining.isEmpty();
        wifiDiscoveryDoc["wifiDiscoveredNetworks"] = chunk;
        wifiDiscoveryDoc["wifiStatus"] = generalWifiStatus;
        char wifiDiscoveryPayload[420];
        const size_t n = serializeJson(wifiDiscoveryDoc, wifiDiscoveryPayload, sizeof(wifiDiscoveryPayload));
        if (n == 0 || n >= sizeof(wifiDiscoveryPayload)-1) break;
        bleStateCharacteristic->setValue(reinterpret_cast<uint8_t*>(wifiDiscoveryPayload), n);
        bleStateCharacteristic->notify();
        delay(12);
        firstChunk = false;
        ++chunkNo;
      }
      generalWifiDiscoveryDirty = false;
    }
  }
  if (mqtt.connected()) {
    mqtt.publish(stateTopic.c_str(), reinterpret_cast<const uint8_t*>(payload), written, true);
  }
}

bool validCoordinate(const char* value, char hemisphere, bool isLatitude, double &result) {
  if (!value || !*value) return false;
  const double raw = atof(value);
  const int degrees = static_cast<int>(raw / 100.0);
  const double minutes = raw - degrees * 100.0;
  result = degrees + minutes / 60.0;
  if (hemisphere == 'S' || hemisphere == 'W') result = -result;
  return minutes >= 0 && minutes < 60 && fabs(result) <= (isLatitude ? 90.0 : 180.0);
}

void parseGpsLine(const String &line) {
  if (!line.startsWith("+CGPSINFO:")) return;
  String payload = line.substring(10);
  payload.trim();
  char buffer[220];
  payload.toCharArray(buffer, sizeof(buffer));
  char *fields[9]{};
  size_t count = 0;
  char *save = nullptr;
  for (char *token = strtok_r(buffer, ",", &save); token && count < 9; token = strtok_r(nullptr, ",", &save)) {
    fields[count++] = token;
  }
  double lat = 0, lon = 0;
  if (count >= 4 && strlen(fields[1]) == 1 && strlen(fields[3]) == 1 &&
      validCoordinate(fields[0], fields[1][0], true, lat) &&
      validCoordinate(fields[2], fields[3][0], false, lon)) {
    latitude = lat;
    longitude = lon;
    gpsValid = true;
    gpsFixAt = millis();
  }
}

void pollGnss() {
  if (!ENABLE_GNSS) return;
  if (cellularEnabled && PPP.started()) {
    if (millis() - lastGnssQueryAt >= GNSS_QUERY_INTERVAL_MS) {
      lastGnssQueryAt = millis();
      const String response = PPP.cmd("AT+CGPSINFO", 5000);
      if (!response.isEmpty()) {
        const int pos = response.indexOf("+CGPSINFO:");
        if (pos >= 0) parseGpsLine(response.substring(pos));
      }
    }
    if (gpsValid && millis() - gpsFixAt >= GPS_FIX_MAX_AGE_MS) gpsValid = false;
    return;
  }
  while (modem.available()) {
    const char c = static_cast<char>(modem.read());
    if (c == '\r') continue;
    if (c == '\n') {
      if (modemLine.length()) parseGpsLine(modemLine);
      modemLine = "";
    } else if (modemLine.length() < 219) {
      modemLine += c;
    }
  }
  if (millis() - lastGnssQueryAt >= GNSS_QUERY_INTERVAL_MS) {
    lastGnssQueryAt = millis();
    modem.println("AT+CGPSINFO");
  }
  if (gpsValid && millis() - gpsFixAt >= GPS_FIX_MAX_AGE_MS) gpsValid = false;
}

void processCommandPayload(const uint8_t* bytes, size_t length, CommandSource source) {
  if (length == 0 || length > 512) return;
  JsonDocument doc;
  if (deserializeJson(doc, bytes, length) || (doc["schema"] | 0) != 1) return;

  const String id = doc["id"] | "";
  const String phoneId = doc["phoneID"] | "";
  const String action = doc["action"] | "";
  const String ownerTarget = doc["ownerTarget"] | "";
  Serial0.printf("[CMD] src=%s action=%s, bytes=%u\n", source == CommandSource::MQTT ? "NET" : "BLE", action.c_str(), static_cast<unsigned>(length));
  if (id.isEmpty() || phoneId.isEmpty() || (id == lastCommandId && action != "keyless_presence")) return;

  // v12.65: normal commands follow the saved priority. Keyless/proximity
  // always stays BLE-first so RSSI timing remains responsive.
  const bool cloudLive = (activeInternetRoute != InternetRoute::NONE) && mqtt.connected();
  const bool keylessBleAction =
      action == "keyless_presence" || action == "keyless_unlock" ||
      action == "keyless_lock" || action == "keyless_config" ||
      action == "owner_status" || action == "owner_register" ||
      action == "owner_request";
  // Manual remote-power is a safety/control command.  Never discard a valid
  // BLE press merely because an Internet route is currently ranked higher.
  // The iPhone already sends one route according to priority; accepting BLE
  // here also keeps the local control usable during stale cloud-route state.
  const bool directRemotePowerAction =
      action == "remote_power_on" || action == "remote_power_off";
  if (source == CommandSource::BLE && cloudLive && !keylessBleAction && !directRemotePowerAction) {
    const int bleRank = connectionPriorityRank("BLE");
    const int cloudRank = connectionPriorityRank(internetRouteName(activeInternetRoute));
    if (cloudRank < bleRank) {
      Serial0.printf("[CMD] BLE skipped by priority while cloud is live: %s\n", action.c_str());
      return;
    }
  }

  if (action == "owner_status") {
    lastCommandId = id;
    Serial0.printf("[OWNER SYNC] request from phone owner=%s count=%u\n",
                   ownerIndex(phoneId) >= 0 ? "YES" : "NO", static_cast<unsigned>(ownerCount()));
    publishOwnerState();
    return;
  }

  if (action == "event_ack") {
    if (ownerIndex(phoneId) < 0 || ownerTarget.isEmpty()) return;
    lastCommandId = id;
    acknowledgeVehicleEvent(ownerTarget);
    // Immediately publish again so the next queued event can be delivered.
    publishState();
    return;
  }

  int pin = -1;
  bool keepRemotePowered = false;
  if (action == "remote_power_on" || action == "remote_power_off") {
    // Manual commands arriving over the authenticated phone BLE session only
    // require that phone to be a registered owner.  Keyless proximity is a
    // separate automation signal and must never reject a manual owner command.
    if (ownerIndex(phoneId) < 0) {
      lastEvent = "rejected_unknown_phone";
      publishState();
      return;
    }
    scheduledRemotePulsePin = -1;
    remotePowerOffAt = 0;
    manualRemotePowerOffLatch = (action == "remote_power_off");
    if (action == "remote_power_on") manualRemotePowerOffLatch = false;
    setRemotePower(action == "remote_power_on");
    lastCommandId = id;
    lastEvent = action;
    publishState();
    return;
  }
  if (action == "owner_request") {
    if (ownerIndex(phoneId) >= 0) {
      lastEvent = "owner_already_registered";
    } else {
      pendingOwnerPhone = phoneId;
      lastEvent = "owner_approval_needed";
    }
    lastCommandId = id;
    publishState();
    return;
  }
  if (action == "owner_approve" || action == "owner_reject" || action == "owner_remove" || action == "owner_clear") {
    if (!isAdminPhone(phoneId)) {
      lastEvent = "rejected_not_admin";
    } else if (action == "owner_approve") {
      if (!ownerTarget.isEmpty() && ownerTarget == pendingOwnerPhone && registerOwner(ownerTarget)) {
        pendingOwnerPhone = "";
        lastEvent = "owner_approved";
      } else lastEvent = "owner_approve_failed";
    } else if (action == "owner_reject") {
      if (ownerTarget == pendingOwnerPhone) pendingOwnerPhone = "";
      lastEvent = "owner_request_rejected";
    } else if (action == "owner_remove") {
      lastEvent = removeGuestOwner(ownerTarget) ? "owner_removed" : "owner_remove_failed";
    } else {
      clearGuestOwners();
      lastEvent = "guest_owners_cleared";
    }
    lastCommandId = id;
    publishState();
    return;
  }
  if (action == "owner_register" || action == "keyless_config") {
    // Bootstrap is allowed only when there is no administrator.  Later phones
    // must first request access, then wait for an administrator approval.
    if (action == "owner_register" && !ownerPhones[0].phoneId.isEmpty() && ownerIndex(phoneId) < 0) {
      pendingOwnerPhone = phoneId;
      lastEvent = "owner_approval_needed";
      lastCommandId = id;
      publishState();
      return;
    }
    // The very first phone is always written into slot 0, so it is guaranteed
    // to become the administrator even if a previous incomplete setup left a
    // stale empty slot elsewhere in flash.
    bool enrolled = false;
    if (action == "owner_register" && ownerPhones[0].phoneId.isEmpty()) {
      ownerPhones[0].phoneId = phoneId;
      preferences.putString("owner0", phoneId);
      enrolled = preferences.getString("owner0", "") == phoneId;
      if (!enrolled) ownerPhones[0] = OwnerPresence{};
    } else {
      enrolled = registerOwner(phoneId);
    }
    if (!enrolled) {
      lastEvent = "rejected_owner_limit";
      publishState();
      return;
    }
    if (action == "owner_register") {
      lastCommandId = id;
      lastEvent = "owner_registered";
      publishState();
      return;
    }
    keylessEnabled = doc["keyless"]["enabled"] | false;
    preferences.putBool("keylessEnabled", keylessEnabled);
    const uint32_t delaySeconds = doc["keyless"]["lockDelaySeconds"] | 20;
    keylessLockDelayMs = constrain(delaySeconds, 5U, 120U) * 1000UL;
    preferences.putUInt("keylessLockMs", keylessLockDelayMs);
    if (!keylessEnabled) {
      keylessHadPresence = false;
      keylessDepartureLockIssued = false;
      keylessSessionOpen = false;
    }
    lastCommandId = id;
    lastEvent = "keyless_config_received";
    publishState();
    return;
  }
  if (ownerIndex(phoneId) < 0) {
    lastEvent = "rejected_unknown_phone";
    publishState();
    return;
  }
  lastOwnerActivityAt = millis();
  if (action == "obd_select") {
    String name = doc["obdAdapter"]["name"] | "";
    String transport = doc["obdAdapter"]["transport"] | "BLE";
    String password = doc["obdAdapter"]["password"] | "";
    String host = doc["obdAdapter"]["host"] | "192.168.0.10";
    uint16_t port = doc["obdAdapter"]["port"] | 35000;
    transport.toUpperCase();
    name.trim();
    if (transport != "BLE" && transport != "WIFI") {
      lastEvent = "obd_transport_invalid";
    } else if (name.isEmpty()) {
      lastEvent = "obd_adapter_name_required";
    } else {
      obdWifiStaReserved = (transport == "WIFI");
      if (obdWifiStaReserved) {
        // Preserve router credentials/settings, but give the only STA to OBD.
        mqtt.disconnect();
        WiFi.disconnect(false, false);
        generalWifiStatus = "paused_for_obd_wifi";
        Serial0.println("[OBD WIFI] STA reserved; general Wi-Fi paused (settings preserved)");
      } else if (generalWifiEnabled && !generalWifiSsid.isEmpty()) {
        // Returning to BLE releases STA and restores normal Internet Wi-Fi.
        generalWifiLastConnectAttemptAt = 0;
        generalWifiStatus = "disconnected";
      }
      obd.setPreferredAdapter(name, transport, password, host, port);
      lastEvent = obdWifiStaReserved ? "obd_wifi_saved_general_wifi_paused" : "obd_adapter_saved";
    }
    lastCommandId = id;
    publishState();
    return;
  }
  if (action == "obd_search") {
    String transport = doc["obdAdapter"]["transport"] | "BLE";
    obd.requestAdapterDiscovery(transport);
    lastCommandId = id;
    lastEvent = "obd_adapter_search_requested";
    publishState();
    return;
  }
  if (action == "obd_forget") {
    obd.forgetPreferredAdapter();
    obdWifiStaReserved = false;
    if (generalWifiEnabled && !generalWifiSsid.isEmpty()) {
      generalWifiLastConnectAttemptAt = 0;
      generalWifiStatus = "disconnected";
    }
    lastCommandId = id;
    lastEvent = "obd_adapter_forgotten";
    publishState();
    return;
  }
  if (action == "obd_scan_dtc") {
    lastCommandId = id;
    if (obd.requestDiagnosticScan()) lastEvent = "dtc_scan_started";
    else lastEvent = "dtc_scan_unavailable";
    publishState();
    return;
  }
  if (action == "obd_clear_dtc") {
    // This is intentionally separate from AI analysis: the owner must make a
    // fresh explicit confirmation and the engine must be stopped.
    const bool confirmed = doc["obdClearConfirmed"] | false;
    lastCommandId = id;
    if (!confirmed) lastEvent = "dtc_clear_confirmation_required";
    else if (obd.snapshot().engineRunning) lastEvent = "dtc_clear_rejected_engine_running";
    else if (obd.requestClearTroubleCodes()) lastEvent = "dtc_clear_sent";
    else lastEvent = "dtc_clear_unavailable";
    publishState();
    return;
  }
  if (action == "maintenance_mode") {
    maintenanceMode = doc["maintenanceMode"] | false;
    preferences.putBool("maintenance", maintenanceMode);
    if (maintenanceMode) {
      keylessSessionOpen = false;
      nfcLockedUntilDeparture = false;
      setRemotePower(false);
    }
    lastCommandId = id;
    lastEvent = maintenanceMode ? "maintenance_enabled" : "maintenance_disabled";
    publishState();
    return;
  }
  if (action == "power_save") {
    powerSaveMode = constrain(doc["powerSave"]["mode"] | 0, 0, 2);
    powerSaveIdleMinutes = constrain(doc["powerSave"]["idleMinutes"] | 30, 1, 720);
    preferences.putUChar("powerMode", powerSaveMode);
    preferences.putUShort("powerIdle", powerSaveIdleMinutes);
    lastCommandId = id;
    lastEvent = "power_save_saved";
    updatePowerSaving();
    publishState();
    return;
  }
  if (action == "nfc_enroll") {
    nfcEnrollPending = nfcReady;
    nfcEnrollAt = millis();
    lastCommandId = id;
    lastEvent = nfcReady ? "nfc_waiting_for_card" : "nfc_reader_unavailable";
    publishState();
    return;
  }
  if (action == "nfc_forget") {
    preferences.remove("nfcUid");
    nfcLastUid = "";
    lastCommandId = id;
    lastEvent = "nfc_card_removed";
    publishState();
    return;
  }
  if (action == "cellular_config") {
    const bool enabled = doc["cellularSettings"]["enabled"] | false;
    String apn = doc["cellularSettings"]["apn"] | "internet";
    String username = doc["cellularSettings"]["username"] | "";
    String password = doc["cellularSettings"]["password"] | "";
    String simPin = doc["cellularSettings"]["simPin"] | "";
    const bool requestedHotspot = doc["cellularSettings"]["hotspotEnabled"] | false;
    String requestedHotspotSsid = doc["cellularSettings"]["hotspotSSID"] | "JOURNEY-4G";
    String requestedHotspotPassword = doc["cellularSettings"]["hotspotPassword"] | "Journey2017";
    apn.trim(); username.trim(); simPin.trim(); requestedHotspotSsid.trim();
    if (apn.isEmpty()) apn = "internet";
    cellularEnabled = enabled;
    cellularApn = apn;
    cellularUsername = username;
    cellularPassword = password;
    cellularSimPin = simPin;
    hotspotEnabled = requestedHotspot;
    if (!requestedHotspotSsid.isEmpty()) hotspotSsid = requestedHotspotSsid;
    if (requestedHotspotPassword.length() >= 8) hotspotPassword = requestedHotspotPassword;
    preferences.putBool("cellEnabled", cellularEnabled);
    preferences.putString("cellApn", cellularApn);
    preferences.putString("cellUser", cellularUsername);
    preferences.putString("cellPass", cellularPassword);
    preferences.putString("cellPin", cellularSimPin);
    preferences.putBool("hotspotEnabled", hotspotEnabled);
    preferences.putString("hotspotSsid", hotspotSsid);
    preferences.putString("hotspotPass", hotspotPassword);
    if (PPP.started()) PPP.end();
    if (cellularEnabled) startCellularPpp();
    else { stopHotspot(); stopCellularPpp(); }
    applyInternetPriority();
    lastCommandId = id;
    lastEvent = cellularEnabled ? "cellular_config_saved" : "cellular_disabled";
    publishState();
    return;
  }
  if (action == "cellular_test") {
    refreshCellularStatus(true);
    lastCommandId = id;
    lastEvent = "cellular_test_complete";
    publishState();
    return;
  }
  if (action == "cellular_forget") {
    cellularEnabled = false;
    cellularApn = "internet";
    cellularUsername = "";
    cellularPassword = "";
    cellularSimPin = "";
    hotspotEnabled = false;
    stopHotspot();
    stopCellularPpp();
    preferences.putBool("cellEnabled", false);
    preferences.remove("cellApn");
    preferences.remove("cellUser");
    preferences.remove("cellPass");
    preferences.remove("cellPin");
    preferences.remove("hotspotEnabled");
    preferences.remove("hotspotSsid");
    preferences.remove("hotspotPass");
    refreshCellularStatus(false);
    lastCommandId = id;
    lastEvent = "cellular_settings_cleared";
    publishState();
    return;
  }
  if (action == "connection_priority") {
    JsonArray order = doc["connectionPriority"]["order"].as<JsonArray>();
    if (order.size() != 3) {
      lastEvent = "connection_priority_invalid";
      publishState();
      return;
    }
    String csv;
    for (JsonVariant item : order) {
      String route = item.as<String>();
      route.trim();
      route.toUpperCase();
      if (!csv.isEmpty()) csv += ',';
      csv += route;
    }
    if (!validConnectionPriority(csv)) {
      lastEvent = "connection_priority_invalid";
      publishState();
      return;
    }
    connectionPriorityCsv = csv;
    preferences.putString("connPriority", connectionPriorityCsv);
    applyInternetPriority();
    lastCommandId = id;
    lastEvent = "connection_priority_saved";
    Serial0.printf("[NET] priority=%s\n", connectionPriorityCsv.c_str());
    publishState();
    return;
  }
  if (action == "wifi_config") {
    const bool enabled = doc["wifiSettings"]["enabled"] | false;
    String ssid = doc["wifiSettings"]["ssid"] | "";
    String password = doc["wifiSettings"]["password"] | "";
    ssid.trim();
    // OBD Wi-Fi and normal Internet Wi-Fi cannot use different SSIDs at
    // the same time because ESP32 exposes a single STA interface.
    if (enabled && String(obd.statusText()).startsWith("wifi_")) {
      lastCommandId = id;
      lastEvent = "general_wifi_conflicts_with_obd_wifi";
      Serial0.println("[WIFI] rejected: OBD Wi-Fi owns STA; select BLE OBD or forget OBD Wi-Fi first");
      publishState();
      return;
    }
    generalWifiEnabled = enabled;
    if (!ssid.isEmpty()) {
      generalWifiSsid = ssid;
      generalWifiPassword = password;
      preferences.putString("wifiSsid", generalWifiSsid);
      preferences.putString("wifiPassGen", generalWifiPassword);
    }
    preferences.putBool("wifiEnabled", generalWifiEnabled);
    if (!generalWifiEnabled) {
      WiFi.disconnect(true, false);
      WiFi.mode(WIFI_OFF);
      generalWifiStatus = "off";
    } else if (generalWifiSsid.isEmpty()) {
      generalWifiStatus = "network_required";
    } else {
      WiFi.mode(WIFI_STA);
      WiFi.begin(generalWifiSsid.c_str(), generalWifiPassword.c_str());
      generalWifiLastConnectAttemptAt = millis();
      generalWifiStatus = "connecting";
    }
    lastCommandId = id;
    lastEvent = "wifi_config_saved";
    publishState();
    return;
  }
  if (action == "wifi_search") {
    generalWifiScanRequested = true;
    generalWifiStatus = "searching";
    lastCommandId = id;
    lastEvent = "wifi_search_requested";
    publishState();
    return;
  }
  if (action == "wifi_forget") {
    generalWifiEnabled = false;
    generalWifiSsid = "";
    generalWifiPassword = "";
    preferences.putBool("wifiEnabled", false);
    preferences.remove("wifiSsid");
    preferences.remove("wifiPassGen");
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_OFF);
    generalWifiStatus = "forgotten";
    lastCommandId = id;
    lastEvent = "wifi_forgotten";
    publishState();
    return;
  }
  if (action == "esp_settings") {
    const uint32_t pulse = constrain(doc["espSettings"]["remotePulseMs"] | static_cast<int>(remotePulseMs), 100, 2000);
    const uint32_t wake = constrain(doc["espSettings"]["remoteWakeDelayMs"] | static_cast<int>(remoteWakeDelayMs), 100, 5000);
    const uint32_t off = constrain(doc["espSettings"]["remotePowerOffDelayMs"] | static_cast<int>(remotePowerOffDelayMs), 200, 10000);
    const uint8_t brightness = constrain(doc["espSettings"]["hudBrightness"] | static_cast<int>(hudBrightness), 0, 7);
    const int warning = constrain(doc["espSettings"]["espTempWarningC"] | espTempWarningC, 35, 75);
    if (warning != espTempWarningC) {
      espTempWarningC = warning;
      preferences.putUChar("tempWarnC", warning);
      espHealthAt = 0; // Re-evaluate the live temperature on the next loop.
    }
    remotePulseMs = pulse;
    remoteWakeDelayMs = wake;
    remotePowerOffDelayMs = off;
    hudBrightness = brightness;
    preferences.putUInt("pulseMs", remotePulseMs);
    preferences.putUInt("wakeMs", remoteWakeDelayMs);
    preferences.putUInt("offMs", remotePowerOffDelayMs);
    preferences.putUChar("hudBright", hudBrightness);
    hud.setBrightness(hudBrightness, true);
    lastCommandId = id;
    lastEvent = "esp_settings_saved";
    publishState();
    return;
  }
  if (action == "ota_url") {
    const String url = doc["firmwareURL"] | "";
    lastCommandId = id;
    lastEvent = updateFromInternet(url) ? "ota_internet_complete" : "ota_internet_failed";
    publishState();
    return;
  }
  if (action == "keyless_presence") {
    const int index = ownerIndex(phoneId);
    const bool reportedNearby = doc["presence"]["nearby"] | false;
    Serial0.printf("[KEYLESS RX] owner=%s index=%d nearby=%d session=%d locked=%d remote=%d maintenance=%d\n",
                   index >= 0 ? "YES" : "NO", index, reportedNearby,
                   keylessSessionOpen, locked, remotePowered, maintenanceMode);
    if (index >= 0) {
      const bool wasNearby = ownerPhones[index].nearby;
      ownerPhones[index].nearby = reportedNearby;
      ownerPhones[index].lastSeenAt = millis();
      lastCommandId = id;
      if (wasNearby != reportedNearby) {
        lastEvent = reportedNearby ? "keyless_presence_near" : "keyless_presence_far";
        publishVehicleEvent(lastEvent.c_str(), reportedNearby ? "اقترب الهاتف من السيارة" : "ابتعد الهاتف عن السيارة");
      }
      updateKeylessPresenceState();
      Serial0.printf("[KEYLESS RX] after update: nearbyAny=%d session=%d locked=%d remote=%d edge=%d\n",
                     anyOwnerNearby(), keylessSessionOpen, locked, remotePowered, wasNearby != reportedNearby);
      // Heartbeats update presence/timestamp only; periodic state publishing handles UI.
    } else {
      lastEvent = "rejected_unknown_phone";
      Serial0.println("[KEYLESS RX] rejected: phone is not an authorised owner");
      publishState();
    }
    return;
  }
  // Manual Unlock powers the spare remote only for its press, then switches
  // it off.  Only the automatic proximity path keeps it powered until the
  // matching keyless lock command arrives.
  if (action == "lock" || action == "keyless_lock") pin = LOCK_PIN;
  else if (action == "unlock") pin = UNLOCK_PIN;
  else if (action == "keyless_unlock") { pin = UNLOCK_PIN; keepRemotePowered = true; }
  else if (action == "horn") pin = ALARM_PIN;
  else if (action == "remote_start") {
    const ObdSnapshot& snapshot = obd.snapshot();
    if (!ALLOW_REMOTE_START || !snapshot.connected || snapshot.speedKph > 0) {
      lastEvent = "start_rejected_safety";
      publishState();
      return;
    }
    pin = START_PIN;
    keepRemotePowered = false;
  }
  else {
    // Lights, signals and doors are not available through standard OBD PIDs.
    lastEvent = String("not_available_via_obd:") + action;
    publishState();
    return;
  }

  if (!queueRemotePress(pin, keepRemotePowered)) {
    lastEvent = String("output_not_configured:") + action;
    publishState();
    return;
  }
  if (action == "lock" || action == "keyless_lock") {
    locked = true;
    doorsOpen = false;
    // A manual LOCK while the owner is still nearby must win over proximity
    // automation.  Otherwise the next keyless_presence packet immediately
    // sees locked=1 and re-opens the car.  Hold auto-unlock until the phone
    // has genuinely left the near zone once; updateKeylessPresenceState()
    // clears this latch when no owner is nearby, so a later approach can
    // start a fresh keyless session normally.
    if (action == "lock") {
      nfcLockedUntilDeparture = true;
      keylessSessionOpen = false;
      Serial0.println("[KEYLESS] manual lock latch: auto-unlock blocked until departure");
    }
  }
  else if (action == "unlock" || action == "keyless_unlock") {
    locked = false;
    nfcLockedUntilDeparture = false;
  }
  else if (action == "remote_start") { /* OBD RPM is the only source of engineRunning. */ }
  else if (action == "horn") hornActive = true;
  lastCommandId = id;
  lastEvent = action;
  publishState();
}

void handleCommand(char* topic, byte* bytes, unsigned int length) {
  if (String(topic) != commandTopic) return;
  processCommandPayload(bytes, length, CommandSource::MQTT);
}

void connectWifi() {
  if (obdWifiStaReserved) { generalWifiStatus = "paused_for_obd_wifi"; return; }
  if (!generalWifiEnabled || generalWifiSsid.isEmpty()) return;
  if (WiFi.status() == WL_CONNECTED) return;
  if (millis() - generalWifiLastConnectAttemptAt < GENERAL_WIFI_RETRY_MS) return;
  generalWifiLastConnectAttemptAt = millis();
  WiFi.mode(hotspotEnabled ? WIFI_AP_STA : WIFI_STA);
  WiFi.begin(generalWifiSsid.c_str(), generalWifiPassword.c_str());
  generalWifiStatus = "connecting";
  Serial0.printf("[WIFI] connecting ssid=%s\n", generalWifiSsid.c_str());
}

void pollGeneralWifi() {
  if (obdWifiStaReserved) {
    if (generalWifiScanRequested || generalWifiScanActive) {
      generalWifiScanRequested = false;
      generalWifiScanActive = false;
      WiFi.scanDelete();
      generalWifiDiscoveryDirty = true;
    }
    generalWifiStatus = "paused_for_obd_wifi";
    return;
  }
  if (generalWifiScanRequested && !generalWifiScanActive) {
    generalWifiScanRequested = false;
    WiFi.mode(hotspotEnabled ? WIFI_AP_STA : WIFI_STA);
    WiFi.scanDelete();
    const int rc = WiFi.scanNetworks(true, true);
    if (rc == WIFI_SCAN_FAILED) {
      generalWifiStatus = "scan_failed";
      generalWifiDiscoveryDirty = true;
    } else {
      generalWifiScanActive = true;
      generalWifiStatus = "searching";
      Serial0.println("[WIFI] one-shot scan started");
    }
  }

  if (generalWifiScanActive) {
    const int found = WiFi.scanComplete();
    if (found >= 0) {
      generalWifiScanActive = false;
      generalWifiDiscoveredNetworks = "";
      for (int i = 0; i < found; ++i) {
        String ssid = WiFi.SSID(i);
        if (ssid.isEmpty()) continue;
        bool exists = false;
        int from = 0;
        while (from < generalWifiDiscoveredNetworks.length()) {
          int next = generalWifiDiscoveredNetworks.indexOf(" | ", from);
          String item = next < 0 ? generalWifiDiscoveredNetworks.substring(from) : generalWifiDiscoveredNetworks.substring(from, next);
          if (item == ssid) { exists = true; break; }
          if (next < 0) break;
          from = next + 3;
        }
        if (exists) continue;
        if (!generalWifiDiscoveredNetworks.isEmpty()) generalWifiDiscoveredNetworks += " | ";
        if (generalWifiDiscoveredNetworks.length() + ssid.length() < 1800) generalWifiDiscoveredNetworks += ssid;
      }
      WiFi.scanDelete();
      generalWifiStatus = generalWifiDiscoveredNetworks.isEmpty() ? "networks_not_found" : "networks_found";
      generalWifiDiscoveryDirty = true;
      Serial0.printf("[WIFI] scan complete found=%d listed=%u\n", found, static_cast<unsigned>(generalWifiDiscoveredNetworks.length()));
      if (!generalWifiEnabled && !hotspotRunning && !hotspotEnabled) {
        WiFi.disconnect(true, false);
        WiFi.mode(WIFI_OFF);
      }
      publishState();
    } else if (found == WIFI_SCAN_FAILED) {
      generalWifiScanActive = false;
      generalWifiStatus = "scan_failed";
      generalWifiDiscoveryDirty = true;
      if (!generalWifiEnabled && !hotspotRunning && !hotspotEnabled) WiFi.mode(WIFI_OFF);
      publishState();
    }
  }

  if (!generalWifiEnabled) return;
  if (WiFi.status() == WL_CONNECTED) {
    if (generalWifiStatus != "connected") {
      generalWifiStatus = "connected";
      Serial0.printf("[WIFI] connected ssid=%s ip=%s rssi=%d\n", WiFi.SSID().c_str(), WiFi.localIP().toString().c_str(), WiFi.RSSI());
      publishState();
    }
  } else {
    if (generalWifiStatus == "connected") generalWifiStatus = "disconnected";
    connectWifi();
  }
}

void ensureMqtt() {
  if (!settingsReady() || activeInternetRoute == InternetRoute::NONE || mqtt.connected()) return;
  if (millis() - lastReconnectAt < 5000) return;
  lastReconnectAt = millis();
  const String clientId = String(DEVICE_ID) + "-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  if (mqtt.connect(clientId.c_str(), MQTT_USERNAME, MQTT_PASSWORD)) {
    mqtt.subscribe(commandTopic.c_str(), 1);
    lastEvent = "mqtt_connected";
    publishState();
  }
}

// v12.47: Drain iPhone BLE commands in a dedicated task. OBD discovery/polling can
// block the Arduino loop for seconds; vehicle controls must not wait behind it.
void bleCommandTask(void*) {
  BleCommandFrame frame{};
  for (;;) {
    if (bleCommandQueue && xQueueReceive(bleCommandQueue, &frame, pdMS_TO_TICKS(50)) == pdTRUE) {
      processCommandPayload(reinterpret_cast<const uint8_t*>(frame.bytes), frame.length, CommandSource::BLE);
    }
  }
}

void setup() {
  if (ESP_BATTERY_GAUGE_ENABLED) {
    batteryBusReady = batteryWire.begin(ESP_BATTERY_SDA_PIN, ESP_BATTERY_SCL_PIN, 100000);
    batteryWire.setTimeOut(20);
  }
  Serial0.begin(115200);
  delay(2000);
  Network.begin();
  Serial0.println("\n[JOURNEY] ESP32-S3 starting — firmware v12.78 ESP HEALTH");
  preferences.begin("journey", false);
  loadVehicleEventQueue();
  espTempWarningC = constrain(int(preferences.getUChar("tempWarnC", 50)), 35, 75);
  remotePulseMs = preferences.getUInt("pulseMs", OUTPUT_PULSE_MS);
  remoteWakeDelayMs = preferences.getUInt("wakeMs", REMOTE_POWER_WAKE_DELAY_MS);
  remotePowerOffDelayMs = preferences.getUInt("offMs", REMOTE_POWER_OFF_DELAY_MS);
  hudBrightness = preferences.getUChar("hudBright", TM1637_BRIGHTNESS);
  maintenanceMode = preferences.getBool("maintenance", false);
  powerSaveMode = preferences.getUChar("powerMode", 0);
  powerSaveIdleMinutes = preferences.getUShort("powerIdle", 30);
  keylessEnabled = preferences.getBool("keylessEnabled", false);
  generalWifiEnabled = preferences.getBool("wifiEnabled", false);
  generalWifiSsid = preferences.getString("wifiSsid", "");
  generalWifiPassword = preferences.getString("wifiPassGen", "");
  cellularEnabled = preferences.getBool("cellEnabled", false);
  cellularApn = preferences.getString("cellApn", CELLULAR_APN);
  cellularUsername = preferences.getString("cellUser", "");
  cellularPassword = preferences.getString("cellPass", "");
  cellularSimPin = preferences.getString("cellPin", "");
  hotspotEnabled = preferences.getBool("hotspotEnabled", false);
  hotspotSsid = preferences.getString("hotspotSsid", "JOURNEY-4G");
  hotspotPassword = preferences.getString("hotspotPass", "");
  connectionPriorityCsv = preferences.getString("connPriority", "CELLULAR,WIFI,BLE");
  if (!validConnectionPriority(connectionPriorityCsv)) connectionPriorityCsv = "CELLULAR,WIFI,BLE";
  cellularStatus = cellularEnabled ? "checking" : "disabled";
  generalWifiStatus = generalWifiEnabled ? "disconnected" : "off";
  if (!generalWifiEnabled && !hotspotRunning && !hotspotEnabled) WiFi.mode(WIFI_OFF);
  keylessLockDelayMs = preferences.getUInt("keylessLockMs", KEYLESS_DEFAULT_LOCK_DELAY_MS);
  lastOwnerActivityAt = millis();
  if (CLEAR_TRUSTED_PHONE_ON_BOOT) {
    preferences.remove("trustedPhone");
    for (uint8_t i = 0; i < MAX_AUTHORIZED_PHONES; ++i) preferences.remove((String("owner") + i).c_str());
  }
  for (uint8_t i = 0; i < MAX_AUTHORIZED_PHONES; ++i) {
    ownerPhones[i].phoneId = preferences.getString((String("owner") + i).c_str(), "");
  }
  // One-time migration from firmware that stored a single owner.
  if (ownerPhones[0].phoneId.isEmpty()) {
    ownerPhones[0].phoneId = preferences.getString("trustedPhone", "");
    if (!ownerPhones[0].phoneId.isEmpty()) preferences.putString("owner0", ownerPhones[0].phoneId);
  }
  Serial0.printf("[OWNER BOOT] owners=%u admin=%s\n", static_cast<unsigned>(ownerCount()),
                 ownerPhones[0].phoneId.isEmpty() ? "NONE" : "SAVED");
  delay(500);
  commandTopic = String("journey/") + DEVICE_ID + "/cmd";
  stateTopic = String("journey/") + DEVICE_ID + "/state";
  eventTopic = String("journey/") + DEVICE_ID + "/events";

  for (auto &output : outputs) {
    // High-impedance is the safe idle state for direct negative remote buttons.
    if (output.pin >= 0) setRemoteButton(output.pin, false);
  }
  if (REMOTE_POWER_PIN >= 0) {
    pinMode(REMOTE_POWER_PIN, OUTPUT);
    // BD140 must be HIGH immediately at boot so the spare remote stays off.
    setRemotePower(false);
  }
  hud.setBrightness(hudBrightness, true);
  const uint8_t dashes[] = {0x40, 0x40, 0x40, 0x40};
  hud.setSegments(dashes);
  if (ENABLE_PN532) {
    Wire.begin(PN532_SDA_PIN, PN532_SCL_PIN);
    nfc.begin();
    nfcReady = nfc.getFirmwareVersion() != 0;
    if (nfcReady) {
      nfc.SAMConfig();
      Serial0.println("[NFC] PN532 ready");
    } else Serial0.println("[NFC] PN532 absent; card control disabled");
  }
  bleCommandQueue = xQueueCreate(24, sizeof(BleCommandFrame));
  if (bleCommandQueue) {
    xTaskCreatePinnedToCore(bleCommandTask, "bleCmd", 8192, nullptr, 3, nullptr, 1);
  }
  advertiseBle();
  startLocalOta();
  obd.begin();

  Network.onEvent([](arduino_event_id_t event) {
    if (event == ARDUINO_EVENT_PPP_GOT_IP) {
      cellularDataAttached = true;
      cellularStatus = "data_attached";
      applyInternetPriority();
      applyHotspot();
    } else if (event == ARDUINO_EVENT_PPP_LOST_IP || event == ARDUINO_EVENT_PPP_DISCONNECTED || event == ARDUINO_EVENT_PPP_STOP) {
      cellularDataAttached = false;
      stopHotspot();
      applyInternetPriority();
    }
  });
  if (cellularEnabled) {
    startCellularPpp();
    if (ENABLE_GNSS && PPP.started()) PPP.cmd("AT+CGNSSPWR=1", 5000);
  } else if (ENABLE_GNSS) {
    modem.begin(MODEM_BAUD, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);
    delay(250);
    modem.println("AT+CGNSSPWR=1");
  }

  if (settingsReady()) {
    tlsClient.setCACert(MQTT_ROOT_CA);
    mqtt.setServer(MQTT_HOST, MQTT_PORT);
    mqtt.setCallback(handleCommand);
    mqtt.setBufferSize(4608);
  }
  if (generalWifiEnabled) connectWifi();
}

void loop() {
  pollEspHealth();
  pollGeneralWifi();
  pollCellular();
  applyInternetPriority();
  if (settingsReady() && activeInternetRoute != InternetRoute::NONE) {
    ensureMqtt();
    mqtt.loop();
  }
  // Process iPhone commands before OBD polling. BLE OBD discovery can block
  // for up to 20 seconds, so command-first ordering is required for Wi-Fi
  // discovery, keyless presence and owner sync to respond immediately.
  // BLE commands are drained by bleCommandTask and therefore cannot be delayed
  // by a slow OBD scan/connect attempt.
  obd.poll();
  monitorVehicleEvents();
  otaServer.handleClient();
  pollGnss();
  pollSerialSetup();
  pollNfc();
  updateHud();
  updateKeylessPresenceState();
  updatePowerSaving();
  updateOutputs();
  updateRemoteSequence();
  if (otaRestartPending) {
    delay(800);
    ESP.restart();
  }
  if (bleOwnerSyncPending) {
    bleOwnerSyncPending = false;
    publishOwnerState();
  }
  if (millis() - lastStateAt >= STATE_INTERVAL_MS) {
    lastStateAt = millis();
    publishState();
  }
  delay(10);
}
