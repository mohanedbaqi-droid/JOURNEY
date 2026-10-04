#include "ObdBleService.h"
#include "config.h"

ObdBleService* ObdBleService::instance_ = nullptr;

namespace {
const char* INIT_COMMANDS[] = {"ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"};
const char* PID_COMMANDS[] = {"010C", "010D", "0105", "010F", "0104", "0111", "012F", "011F", "0142"};
constexpr uint8_t PID_COUNT = sizeof(PID_COMMANDS) / sizeof(PID_COMMANDS[0]);
constexpr uint8_t INIT_COUNT = sizeof(INIT_COMMANDS) / sizeof(INIT_COMMANDS[0]);
const char* FFF0 = "0000fff0-0000-1000-8000-00805f9b34fb";
const char* FFF1 = "0000fff1-0000-1000-8000-00805f9b34fb";
const char* FFF2 = "0000fff2-0000-1000-8000-00805f9b34fb";
const char* NUS_SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const char* NUS_RX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
const char* NUS_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

// Confirmed on the user's 2017 Dodge Journey with the exact-ID analyzer.
constexpr uint16_t BCM_ID_DOORS = 0x202;
constexpr uint16_t BCM_ID_TURNS = 0x318;
constexpr uint16_t BCM_ID_HEADLIGHT = 0x304;
constexpr uint16_t BCM_ID_LOCK = 0x14C;

class ClientCallbacks final : public BLEClientCallbacks {
  void onDisconnect(BLEClient* client) override { ObdBleService::onDisconnect(client); }
};
class ScanCallbacks final : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice device) override { ObdBleService::onScan(device); }
};
ScanCallbacks scanCallbacks;
}

void ObdBleService::begin() {
  instance_ = this;
  storage_.begin("journey-obd", false);
  preferredName_ = storage_.getString("adapter", OBD_BLE_NAME);
  preferredAddress_ = storage_.getString("adapterAddr", OBD_BLE_ADDRESS);
  preferredTransport_ = storage_.getString("transport", "BLE");
  wifiPassword_ = storage_.getString("wifiPass", "");
  wifiHost_ = storage_.getString("wifiHost", "192.168.0.10");
  wifiPort_ = storage_.getUShort("wifiPort", 35000);
  preferredName_.trim();
  preferredAddress_.trim();
  // KONNWEI is the factory/default adapter. A user-selected adapter overrides it in NVS.
  if (preferredName_.isEmpty()) preferredName_ = OBD_BLE_NAME;
  if (preferredAddress_.isEmpty() && preferredName_.equalsIgnoreCase(OBD_BLE_NAME)) preferredAddress_ = OBD_BLE_ADDRESS;
  preferredAddress_.toUpperCase();
  preferredTransport_.toUpperCase();
  if (preferredTransport_ != "WIFI") preferredName_.toUpperCase();
  status_ = preferredName_.isEmpty() ? "waiting_for_adapter_selection" : "waiting_for_saved_adapter";
  rateWindowAt_ = millis();
  nextDtcCheckAt_ = UINT32_MAX; // DTC scan is manual; never poll codes every minute.
}

const ObdSnapshot& ObdBleService::snapshot() const { return data_; }
const char* ObdBleService::statusText() const { return status_.c_str(); }

bool ObdBleService::applyConfirmedBcmFrame(uint16_t canId, const uint8_t* bytes, uint8_t len) {
  if (!bytes) return false;
  if (canId == BCM_ID_DOORS && len > 5) {
    data_.doorsOpen = (bytes[5] & 0x01) != 0;
  } else if (canId == BCM_ID_TURNS && len > 0) {
    data_.leftSignalOn = (bytes[0] & 0x01) != 0;
    data_.rightSignalOn = (bytes[0] & 0x02) != 0;
  } else if (canId == BCM_ID_HEADLIGHT && len > 0) {
    if (bytes[0] == 0x22) data_.headlightsOn = true;
    else if (bytes[0] == 0x21) data_.headlightsOn = false;
    else return false; // untested encoded lighting state: keep last known value
  } else if (canId == BCM_ID_LOCK && len > 6) {
    data_.locked = (bytes[6] & 0x10) != 0;
  } else {
    return false;
  }
  data_.bcmStateValid = true;
  return true;
}

void ObdBleService::setPreferredAdapter(const String& name, const String& transport, const String& password, const String& host, uint16_t port) {
  preferredName_ = name;
  preferredName_.trim();
  preferredAddress_ = "";
  preferredTransport_ = transport;
  preferredTransport_.toUpperCase();
  if (preferredTransport_ != "WIFI") preferredTransport_ = "BLE";
  if (preferredTransport_ == "BLE") {
    // Discovery entries are now shown as NAME [AA:BB:CC:DD:EE:FF].
    // Saving the address lets unnamed adapters be selected and reconnected.
    const int open = preferredName_.lastIndexOf('[');
    const int close = preferredName_.lastIndexOf(']');
    if (open >= 0 && close > open) {
      String candidate = preferredName_.substring(open + 1, close);
      candidate.trim();
      candidate.toUpperCase();
      if (candidate.length() == 17 && candidate.indexOf(':') >= 0) preferredAddress_ = candidate;
    }
    preferredName_.toUpperCase();
  }
  wifiPassword_ = password;
  wifiHost_ = host.isEmpty() ? "192.168.0.10" : host;
  wifiPort_ = port == 0 ? 35000 : port;
  storage_.putString("adapter", preferredName_);
  storage_.putString("adapterAddr", preferredAddress_);
  storage_.putString("transport", preferredTransport_);
  storage_.putString("wifiPass", wifiPassword_);
  storage_.putString("wifiHost", wifiHost_);
  storage_.putUShort("wifiPort", wifiPort_);
  candidateAddress_ = "";
  candidateName_ = "";
  data_.adapterName = preferredName_;
  status_ = preferredName_.isEmpty() ? "adapter_selection_cleared" : "adapter_saved_scanning";
  nextActionAt_ = 0;
}

void ObdBleService::requestAdapterDiscovery(const String& transport) {
  // User-requested discovery must be independent from auto-connect.  The
  // dedicated scan below never connects to the first thing it sees and keeps
  // accumulating every advertiser before the list is sent to the iPhone.
  String mode = transport;
  mode.toUpperCase();
  if (mode == "WIFI") {
    bleDiscoveryRequested_ = false;
    wifiDiscoveryActive_ = false;
    wifiDiscoveryRequested_ = true;
    data_.discoveredWifiNetworks = "";
    status_ = "wifi_networks_searching";
    Serial0.println("[OBD WIFI] robust scan queued");
  } else {
    wifiDiscoveryActive_ = false;
    wifiDiscoveryRequested_ = false;
    bleDiscoveryRequested_ = true;
    discoveredBleCount_ = 0;
    data_.discoveredAdapters = "";
    status_ = "adapter_searching";
    Serial0.println("[OBD BLE] full discovery queued (21s, all advertisers)");
  }
  nextActionAt_ = 0;
}

void ObdBleService::forgetPreferredAdapter() {
  storage_.remove("adapter");
  storage_.remove("adapterAddr");
  storage_.remove("transport");
  storage_.remove("wifiPass");
  // "Forget" means forget the override and return to the built-in KONNWEI.
  preferredName_ = OBD_BLE_NAME;
  preferredAddress_ = OBD_BLE_ADDRESS;
  preferredTransport_ = "BLE";
  candidateAddress_ = "";
  candidateName_ = "";
  data_.adapterName = String(OBD_BLE_NAME) + " [" + OBD_BLE_ADDRESS + "]";
  status_ = "default_adapter_restored";
  nextActionAt_ = 0;
}

bool ObdBleService::connectWifiAdapter() {
  if (preferredName_.isEmpty()) return false;
  WiFi.mode(WIFI_STA);
  if (WiFi.status() != WL_CONNECTED) {
    WiFi.begin(preferredName_.c_str(), wifiPassword_.c_str());
    const uint32_t deadline = millis() + 10000;
    while (WiFi.status() != WL_CONNECTED && millis() < deadline) delay(50);
  }
  if (WiFi.status() != WL_CONNECTED) { status_ = "wifi_join_failed"; return false; }
  if (!wifiClient_.connect(wifiHost_.c_str(), wifiPort_)) { status_ = "wifi_obd_socket_failed"; return false; }
  data_.connected = true;
  data_.adapterName = preferredName_;
  status_ = "initializing_elm327";
  setupStep_ = pidIndex_ = scanMaskIndex_ = 0;
  scanPid_ = 1;
  activeStandardPid_ = 0;
  memset(supportedMasks_, 0, sizeof(supportedMasks_));
  data_.scanProgress = data_.scannedPids = data_.supportedPids = 0;
  data_.standardScanComplete = false;
  elmValidated_ = false;
  ecuValidated_ = false;
  dtcStage_ = 0;
  data_.vin = "";
  data_.diagnosticCodes = "";
  data_.pendingDiagnosticCodes = "";
  data_.permanentDiagnosticCodes = "";
  commandPending_ = false;
  commandRetries_ = 0;
  mode_ = QueryMode::Init;
  reply_ = "";
  nextActionAt_ = millis() + 250;
  return true;
}

bool ObdBleService::requestDiagnosticScan() {
  if (!data_.connected || mode_ == QueryMode::CanSleep || commandPending_) return false;
  diagnosticScanRequested_ = true;
  dtcStage_ = 0;
  status_ = "dtc_scan_requested";
  nextActionAt_ = 0;
  return true;
}

bool ObdBleService::requestClearTroubleCodes() {
  if (!data_.connected || data_.engineRunning || clearRequested_) return false;
  clearRequested_ = true;
  data_.clearInProgress = true;
  status_ = "clear_dtc_requested";
  nextActionAt_ = 0;
  return true;
}

bool ObdBleService::requestElmConsole(const String& input) {
  if (!data_.connected || !writeChar_ || canMonitorActive_ || commandPending_) return false;
  String cmd = input; cmd.trim(); cmd.toUpperCase();
  if (cmd.isEmpty() || cmd.length() > 32) return false;
  // Lab console is intentionally read-only-ish: reject reset/EEPROM and Mode 04 erase.
  if (cmd == "04" || cmd.startsWith("ATZ") || cmd.startsWith("ATD")) return false;
  Serial0.printf("[ELM LAB TX] %s\n", cmd.c_str());
  send(cmd.c_str(), 0xB0);
  return true;
}

bool ObdBleService::startCanMonitor() {
  if (!data_.connected || !writeChar_ || commandPending_ || canMonitorActive_) return false;
  // ATMA only listens to the CAN wires physically exposed to this ELM adapter.
  // It does not transmit vehicle-control frames.
  reply_ = "";
  canLineBuffer_ = "";
  // Exact analyzer proved the BCM traffic on ISO15765 11-bit/500k. Normal OBD
  // runs with ATH0/CAF defaults, so configure a passive raw monitor explicitly.
  // No vehicle-control CAN frames are transmitted.
  const char* monitorSetup[] = {"ATSP6\r", "ATH1\r", "ATCAF0\r"};
  for (const char* raw : monitorSetup) {
    writeChar_->writeValue(reinterpret_cast<uint8_t*>(const_cast<char*>(raw)), strlen(raw), writeChar_->canWrite());
    delay(180);
  }
  reply_ = "";
  String cmd = "ATMA\r";
  writeChar_->writeValue(reinterpret_cast<uint8_t*>(const_cast<char*>(cmd.c_str())), cmd.length(), writeChar_->canWrite());
  canMonitorActive_ = true;
  status_ = "can_monitor_active";
  Serial0.println("[BCM PROBE] passive CAN monitor STARTED. Open/close door, lights and indicators now; then type CAN_MONITOR_STOP");
  return true;
}

bool ObdBleService::stopCanMonitor() {
  if (!canMonitorActive_ || !writeChar_) return false;
  // Any character terminates ELM ATMA. Then re-run normal ELM init automatically.
  String stop = "\r";
  writeChar_->writeValue(reinterpret_cast<uint8_t*>(const_cast<char*>(stop.c_str())), stop.length(), writeChar_->canWrite());
  canMonitorActive_ = false;
  reply_ = "";
  commandPending_ = false;
  setupStep_ = 0;
  mode_ = QueryMode::Init;
  status_ = "can_monitor_stopped_reinitializing";
  nextActionAt_ = millis() + 350;
  Serial0.println("[BCM PROBE] passive CAN monitor STOPPED; normal OBD polling will resume automatically");
  return true;
}

bool ObdBleService::startAutoBcmSlice() {
  if (preferredTransport_ != "BLE" || !data_.connected || !writeChar_ ||
      commandPending_ || canMonitorActive_ || mode_ != QueryMode::Normal) return false;
  static const uint16_t ids[] = {0x318, 0x202, 0x318, 0x14C, 0x318, 0x304};
  const uint16_t id = ids[autoBcmSliceIndex_ % 6];
  autoBcmSliceIndex_ = (autoBcmSliceIndex_ + 1) % 6;
  char filter[16];
  snprintf(filter, sizeof(filter), "ATCF%03X\r", id);
  const char* setup[] = {"ATSP6\r", "ATH1\r", "ATCAF0\r", "ATCM7FF\r"};
  for (const char* cmd : setup) { writeChar_->writeValue((uint8_t*)cmd, strlen(cmd), false); delay(85); }
  writeChar_->writeValue((uint8_t*)filter, strlen(filter), false);
  delay(85);
  canLineBuffer_ = "";
  reply_ = "";
  const char* monitor = "ATMA\r";
  writeChar_->writeValue((uint8_t*)monitor, strlen(monitor), false);
  canMonitorActive_ = true;
  autoBcmSliceActive_ = true;
  autoBcmSliceStartedAt_ = millis();
  status_ = "bcm_engine_timeslice";
  return true;
}

void ObdBleService::stopAutoBcmSlice() {
  if (!autoBcmSliceActive_ || !writeChar_) return;
  // Stop ATMA first, then fully restore ELM's normal PID mode.  The previous
  // code left ATCF/ATCM active, which filtered out ECU replies and produced
  // RPM=0 / PID="—" after the first BCM slice.
  const char* stop = "\r";
  writeChar_->writeValue((uint8_t*)stop, 1, false);
  delay(90);

  const char* restore[] = {
    "ATCF000\r",   // neutral filter value
    "ATCM000\r",   // mask 000 disables the exact-ID filter
    "ATH0\r",
    "ATCAF1\r",
    "ATSP6\r"
  };
  for (const char* cmd : restore) {
    writeChar_->writeValue((uint8_t*)cmd, strlen(cmd), false);
    delay(90);
  }

  canMonitorActive_ = false;
  autoBcmSliceActive_ = false;
  canLineBuffer_ = "";
  reply_ = "";
  commandPending_ = false;
  activePid_ = 0;
  data_.currentPid = "";
  status_ = "obd_live";
  // Give KONNWEI time to leave monitor mode before the first 01xx request.
  nextActionAt_ = millis() + 220;
  // Keep engine telemetry dominant; BCM still gets regular short snapshots.
  nextAutoBcmSliceAt_ = millis() + 1800;
}

bool ObdBleService::matchesAdapter(BLEAdvertisedDevice& device) const {
  String address = device.getAddress().toString().c_str();
  address.toUpperCase();
  if (!preferredAddress_.isEmpty()) return address == preferredAddress_;
  if (!device.haveName()) return false;
  String name = device.getName().c_str();
  name.toUpperCase();
  if (!preferredName_.isEmpty()) return name == preferredName_;
  return name.indexOf("OBD") >= 0 || name.indexOf("ELM") >= 0 || name.indexOf("VGATE") >= 0 ||
         name.indexOf("ICAR") >= 0 || name.indexOf("VLINK") >= 0 || name.indexOf("V-LINK") >= 0 ||
         name.indexOf("KONNWEI") >= 0 || name.indexOf("OBDLINK") >= 0 || name.indexOf("VPECKER") >= 0;
}

void ObdBleService::onScan(BLEAdvertisedDevice device) {
  if (!instance_) return;
  String address = device.getAddress().toString().c_str();
  address.toUpperCase();
  String name = device.haveName() ? String(device.getName().c_str()) : String();
  name.trim();
  const String display = name.isEmpty() ? String("بدون اسم") : name;
  const String item = display + " [" + address + "]";

  // Show EVERY BLE advertiser, including devices without a local name.
  // The address makes duplicate names selectable and lets unnamed OBD adapters
  // be saved/reconnected later. Keep a generous safety cap for crowded areas.
  String& devices = instance_->data_.discoveredAdapters;
  const String addressToken = "[" + address + "]";
  const bool alreadyListed = devices.indexOf(addressToken) >= 0;
  const bool isPreferred = !instance_->preferredAddress_.isEmpty() && address == instance_->preferredAddress_;
  if (!alreadyListed && devices.length() + item.length() + 3 <= 2000) {
    ++instance_->discoveredBleCount_;
    Serial0.printf("[OBD BLE] #%u %s\n", static_cast<unsigned>(instance_->discoveredBleCount_), item.c_str());
    if (isPreferred) {
      devices = devices.isEmpty() ? item : item + " | " + devices;
    } else {
      if (!devices.isEmpty()) devices += " | ";
      devices += item;
    }
  }

  if (instance_->candidateAddress_.length() || !instance_->matchesAdapter(device)) return;
  instance_->candidateAddress_ = address;
  instance_->candidateName_ = item;
}

void ObdBleService::onDisconnect(BLEClient*) {
  if (!instance_) return;
  instance_->data_.connected = false;
  instance_->writeChar_ = nullptr;
  instance_->notifyChar_ = nullptr;
  instance_->commandPending_ = false;
  instance_->elmValidated_ = false;
  instance_->status_ = "disconnected_reconnecting";
  instance_->nextActionAt_ = millis() + OBD_RECONNECT_DELAY_MS;
}

void ObdBleService::onNotify(BLERemoteCharacteristic*, uint8_t* bytes, size_t length, bool) {
  if (!instance_) return;
  if (instance_->canMonitorActive_) {
    // ATMA notifications may split a CAN line across BLE packets. Reassemble
    // complete lines, then decode only the four IDs confirmed on this Journey.
    for (size_t i = 0; i < length; ++i) {
      const char ch = static_cast<char>(bytes[i]);
      if (ch == '\r' || ch == '\n' || ch == '>') {
        String line = instance_->canLineBuffer_;
        instance_->canLineBuffer_ = "";
        line.trim();
        if (line.isEmpty()) continue;
        Serial0.printf("[CAN RAW] %s\n", line.c_str());

        // Normalize separators while preserving hexadecimal tokens.
        line.replace(":", " ");
        line.replace(",", " ");
        while (line.indexOf("  ") >= 0) line.replace("  ", " ");
        int pos = 0;
        String tok[12];
        uint8_t count = 0;
        while (pos < static_cast<int>(line.length()) && count < 12) {
          while (pos < static_cast<int>(line.length()) && line[pos] == ' ') ++pos;
          if (pos >= static_cast<int>(line.length())) break;
          int end = line.indexOf(' ', pos);
          if (end < 0) end = line.length();
          tok[count++] = line.substring(pos, end);
          pos = end + 1;
        }
        if (count < 2) continue;
        char* idEnd = nullptr;
        const unsigned long parsedId = strtoul(tok[0].c_str(), &idEnd, 16);
        if (!idEnd || *idEnd != '\0' || parsedId > 0x7FF) continue;

        uint8_t dataBytes[8]{};
        uint8_t dataLen = 0;
        uint8_t firstData = 1;
        // ELM ATH1 commonly emits "ID DLC D0..D7"; tolerate both with/without DLC.
        if (count >= 3 && tok[1].length() <= 2) {
          char* dlcEnd = nullptr;
          const unsigned long dlc = strtoul(tok[1].c_str(), &dlcEnd, 16);
          if (dlcEnd && *dlcEnd == '\0' && dlc <= 8 && count >= dlc + 2) firstData = 2;
        }
        for (uint8_t t = firstData; t < count && dataLen < 8; ++t) {
          if (tok[t].length() == 0 || tok[t].length() > 2) break;
          char* byteEnd = nullptr;
          const unsigned long value = strtoul(tok[t].c_str(), &byteEnd, 16);
          if (!byteEnd || *byteEnd != '\0' || value > 0xFF) break;
          dataBytes[dataLen++] = static_cast<uint8_t>(value);
        }
        if (dataLen && instance_->applyConfirmedBcmFrame(static_cast<uint16_t>(parsedId), dataBytes, dataLen)) {
          Serial0.printf("[BCM] decoded %03lX len=%u doors=%d lock=%d light=%d L=%d R=%d\n",
                         parsedId, dataLen, instance_->data_.doorsOpen, instance_->data_.locked,
                         instance_->data_.headlightsOn, instance_->data_.leftSignalOn,
                         instance_->data_.rightSignalOn);
        }
      } else if (instance_->canLineBuffer_.length() < 160) {
        instance_->canLineBuffer_ += ch;
      }
    }
    return;
  }
  for (size_t i = 0; i < length && instance_->reply_.length() < 600; ++i) instance_->reply_ += static_cast<char>(bytes[i]);
}

bool ObdBleService::findElmCharacteristics() {
  struct Pair { const char* service; const char* first; const char* second; };
  const Pair pairs[] = {{FFF0, FFF1, FFF2}, {NUS_SERVICE, NUS_RX, NUS_TX}};
  for (const Pair& pair : pairs) {
    BLERemoteService* service = client_->getService(BLEUUID(pair.service));
    if (!service) continue;
    BLERemoteCharacteristic* first = service->getCharacteristic(BLEUUID(pair.first));
    BLERemoteCharacteristic* second = service->getCharacteristic(BLEUUID(pair.second));
    if (!first || !second) continue;
    BLERemoteCharacteristic* chars[] = {first, second};
    for (auto* item : chars) {
      if (item->canWrite() || item->canWriteNoResponse()) writeChar_ = item;
      if (item->canNotify() || item->canIndicate()) notifyChar_ = item;
    }
    if (writeChar_ && notifyChar_) {
      notifyChar_->registerForNotify(onNotify);
      return true;
    }
    writeChar_ = nullptr;
    notifyChar_ = nullptr;
  }
  return false;
}

bool ObdBleService::connectCandidate() {
  if (candidateAddress_.isEmpty()) return false;
  if (!client_) {
    client_ = BLEDevice::createClient();
    client_->setClientCallbacks(new ClientCallbacks());
  }
  status_ = "connecting";
  // Saved MAC is authoritative, but BLE adapters do not all use the same
  // address type.  A direct connect that assumes PUBLIC can therefore fail
  // forever even though KONNWEI is powered. Try both normal BLE address types
  // without starting a general discovery scan (which can disturb phone BLE).
  const BLEAddress target(candidateAddress_.c_str());
  Serial0.printf("[OBD BLE] direct connect %s type=PUBLIC\n", candidateAddress_.c_str());
  bool connected = client_->connect(target, BLE_ADDR_PUBLIC);
  if (!connected) {
    Serial0.printf("[OBD BLE] retry %s type=RANDOM\n", candidateAddress_.c_str());
    connected = client_->connect(target, BLE_ADDR_RANDOM);
  }
  if (!connected) {
    status_ = "connect_failed";
    Serial0.printf("[OBD BLE] connect failed %s (PUBLIC+RANDOM)\n", candidateAddress_.c_str());
    return false;
  }
  Serial0.printf("[OBD BLE] link connected %s\n", candidateAddress_.c_str());
  if (!findElmCharacteristics()) {
    client_->disconnect();
    status_ = "unsupported_gatt";
    return false;
  }
  data_.connected = true;
  data_.adapterName = candidateName_;
  status_ = "initializing_elm327";
  setupStep_ = 0;
  pidIndex_ = 0;
  liveStep_ = 0;
  lastRpmAt_ = lastSpeedAt_ = lastCoolantAt_ = lastVoltageAt_ = lastEcuReplyAt_ = 0;
  scanMaskIndex_ = 0;
  scanPid_ = 1;
  activeStandardPid_ = 0;
  memset(supportedMasks_, 0, sizeof(supportedMasks_));
  data_.scanProgress = 0;
  data_.scannedPids = 0;
  data_.supportedPids = 0;
  data_.standardScanComplete = false;
  elmValidated_ = false;
  ecuValidated_ = false;
  dtcStage_ = 0;
  data_.vin = "";
  data_.diagnosticCodes = "";
  data_.pendingDiagnosticCodes = "";
  data_.permanentDiagnosticCodes = "";
  commandPending_ = false;
  commandRetries_ = 0;
  mode_ = QueryMode::Init;
  reply_ = "";
  nextActionAt_ = millis() + 250;
  return true;
}

void ObdBleService::send(const char* text, uint8_t pid) {
  String command = String(text) + "\r";
  reply_ = "";
  activePid_ = pid;
  if (preferredTransport_ == "WIFI") {
    if (!wifiClient_.connected()) { data_.connected = false; return; }
    wifiClient_.print(command);
  } else {
    if (!writeChar_) return;
    const bool response = writeChar_->canWrite();
    writeChar_->writeValue(reinterpret_cast<uint8_t*>(const_cast<char*>(command.c_str())), command.length(), response);
  }
  pendingCommand_ = text;
  pendingPid_ = pid;
  commandPending_ = true;
  commandRetries_ = 0;
  commandDeadlineAt_ = millis() + 1800;
  nextActionAt_ = millis() + OBD_COMMAND_GAP_MS;
}

void ObdBleService::decodePid(const String& compact) {
  int at = -1;
  auto byteAt = [&](int offset) -> int {
    if (at < 0 || at + offset + 2 > static_cast<int>(compact.length())) return -1;
    return strtol(compact.substring(at + offset, at + offset + 2).c_str(), nullptr, 16);
  };
  switch (activePid_) {
    case 1: // 010C RPM
      at = compact.indexOf("410C"); if (at >= 0) { int a = byteAt(4), b = byteAt(6); if (a >= 0 && b >= 0) data_.rpm = (a * 256 + b) / 4; lastRpmAt_ = lastEcuReplyAt_ = millis(); } break;
    case 2: at = compact.indexOf("410D"); if (at >= 0) { int v = byteAt(4); if (v >= 0) data_.speedKph = v; lastSpeedAt_ = lastEcuReplyAt_ = millis(); } break;
    case 3: at = compact.indexOf("4105"); if (at >= 0) { int v = byteAt(4); if (v >= 0) data_.coolantC = v - 40; lastCoolantAt_ = lastEcuReplyAt_ = millis(); } break;
    case 4: at = compact.indexOf("410F"); if (at >= 0) { int v = byteAt(4); if (v >= 0) data_.intakeAirC = v - 40; } break;
    case 5: at = compact.indexOf("4104"); if (at >= 0) { int v = byteAt(4); if (v >= 0) data_.engineLoadPercent = (v * 100) / 255; } break;
    case 6: at = compact.indexOf("4111"); if (at >= 0) { int v = byteAt(4); if (v >= 0) data_.throttlePercent = (v * 100) / 255; } break;
    case 7: at = compact.indexOf("412F"); if (at >= 0) { int v = byteAt(4); if (v >= 0) { data_.fuelLevelPercent = (v * 100) / 255; data_.fuelLevelValid = true; } } break;
    case 8: at = compact.indexOf("411F"); if (at >= 0) { int a = byteAt(4), b = byteAt(6); if (a >= 0 && b >= 0) data_.engineRuntimeSeconds = a * 256 + b; } break;
    case 9: at = compact.indexOf("4142"); if (at >= 0) { int a = byteAt(4), b = byteAt(6); if (a >= 0 && b >= 0) data_.batteryVoltage = (a * 256 + b) / 1000.0f; lastVoltageAt_ = lastEcuReplyAt_ = millis(); } break;
  }
  data_.engineRunning = data_.rpm > 0;
  if (data_.engineRunning) {
    data_.canAwake = true;
    data_.ignitionState = "ENGINE_RUNNING";
  } else if (data_.canAwake) {
    data_.ignitionState = "IGN_ON";
  }
}

String ObdBleService::decodeTroubleCodesForMode(const String& compact, const char* marker) {
  const int start = compact.indexOf(marker);
  String result;
  if (start < 0) return result;
  int at = start + strlen(marker);
  // KONNWEI can prefix Mode 0A with a one-byte DTC count, e.g. 4A 01 04 56.
  if (String(marker) == "4A" && at + 2 <= static_cast<int>(compact.length())) {
    const int remainingBytes = (compact.length() - at) / 2;
    const int count = strtol(compact.substring(at, at + 2).c_str(), nullptr, 16);
    if (count > 0 && remainingBytes == 1 + count * 2) at += 2;
  }
  for (; at + 3 < static_cast<int>(compact.length()); at += 4) {
    const int first = strtol(compact.substring(at, at + 2).c_str(), nullptr, 16);
    const int second = strtol(compact.substring(at + 2, at + 4).c_str(), nullptr, 16);
    if (first == 0 && second == 0) break;
    const char family[] = {'P', 'C', 'B', 'U'};
    char code[6];
    snprintf(code, sizeof(code), "%c%01X%01X%01X%01X", family[(first >> 6) & 0x03],
             (first >> 4) & 0x03, first & 0x0F, (second >> 4) & 0x0F, second & 0x0F);
    if (!result.isEmpty()) result += ",";
    result += code;
  }
  data_.diagnosticCheckedAt = millis() / 1000;
  return result;
}

String ObdBleService::decodeVin(const String& raw) {
  String normalized = raw;
  normalized.replace("\n", "\r");
  String payloadHex;
  int pos = 0;
  while (pos < static_cast<int>(normalized.length())) {
    int e = normalized.indexOf('\r', pos);
    if (e < 0) e = normalized.length();
    String line = normalized.substring(pos, e);
    line.trim();
    pos = e + 1;
    const int colon = line.indexOf(':');
    if (colon < 0) continue; // skips ISO-TP length line such as 014
    line = line.substring(colon + 1);
    for (size_t i = 0; i < line.length(); ++i)
      if (isxdigit(static_cast<unsigned char>(line[i]))) payloadHex += static_cast<char>(toupper(line[i]));
  }
  int h = payloadHex.indexOf("490201");
  int skip = 6;
  if (h < 0) { h = payloadHex.indexOf("4902"); skip = 4; }
  if (h < 0) return "";
  String vin;
  for (int i = h + skip; i + 1 < static_cast<int>(payloadHex.length()) && vin.length() < 17; i += 2) {
    const int value = strtol(payloadHex.substring(i, i + 2).c_str(), nullptr, 16);
    if (value >= 0x20 && value <= 0x7E) vin += static_cast<char>(value);
  }
  return vin;
}

void ObdBleService::decodeSupportMask(const String& compact) {
  if (activePid_ < 0xF0 || activePid_ >= 0xF6) return;
  const uint8_t index = activePid_ - 0xF0;
  const uint8_t base = index * 0x20;
  char prefix[5];
  snprintf(prefix, sizeof(prefix), "41%02X", base);
  const int at = compact.indexOf(prefix);
  if (at < 0 || at + 12 > static_cast<int>(compact.length())) return;
  const uint32_t mask = (static_cast<uint32_t>(strtoul(compact.substring(at + 4, at + 12).c_str(), nullptr, 16)));
  supportedMasks_[index] = mask;
  for (uint8_t bit = 0; bit < 32; ++bit) {
    if (mask & (1UL << (31 - bit))) ++data_.supportedPids;
  }
}

bool ObdBleService::isSupportedStandardPid(uint16_t pid) const {
  if (pid == 0 || pid > 0xC0) return false;
  const uint8_t index = (pid - 1) / 0x20;
  const uint8_t position = (pid - 1) % 0x20;
  return (supportedMasks_[index] & (1UL << (31 - position))) != 0;
}

void ObdBleService::sendNextStandardPid() {
  while (scanPid_ <= 0xC0 && !isSupportedStandardPid(scanPid_)) ++scanPid_;
  if (scanPid_ > 0xC0) {
    if (!elmValidated_ || !ecuValidated_ || data_.totalResponses == 0 || data_.supportedPids == 0) {
      data_.standardScanComplete = false;
      data_.scanProgress = 0;
      status_ = "waiting_for_can";
      data_.currentPid = "";
      mode_ = QueryMode::CanSleep;
      nextActionAt_ = millis() + 1500;
      return;
    }
    data_.standardScanComplete = true;
    data_.scanProgress = 100;
    data_.currentPid = "";
    status_ = "obd_live";
    mode_ = QueryMode::Normal;
    // v12.54: the long initial PID scan must not manufacture an engine-stop
    // transition before the first live RPM heartbeat. Preserve the validated
    // RPM briefly and force the live loop to start immediately.
    if (data_.rpm > 0) lastRpmAt_ = millis();
    liveStep_ = 0;
    nextActionAt_ = millis();
    dtcStage_ = 3;
    nextDtcCheckAt_ = UINT32_MAX;
    return;
  }
  char command[5];
  snprintf(command, sizeof(command), "01%02X", scanPid_);
  data_.currentPid = command;
  activeStandardPid_ = scanPid_;
  activePid_ = 0x80;
  send(command, activePid_);
  ++scanPid_;
}

void ObdBleService::consumeReply() {
  if (reply_.isEmpty() || reply_.indexOf('>') < 0) return;
  // ATRV is handled from the raw ELM text because its reply is ASCII such as "12.4V".
  // This works even while the vehicle CAN/ECU is asleep because the voltage is
  // measured at the OBD adapter supply, not requested from the ECU.
  if (pendingPid_ == 0xA0) {
    String volts = reply_;
    volts.replace(">", "");
    volts.replace("V", "");
    volts.replace("v", "");
    volts.trim();
    const float parsed = volts.toFloat();
    if (parsed >= 5.0f && parsed <= 20.0f) { data_.batteryVoltage = parsed; lastVoltageAt_ = millis(); }
  }
  String compact;
  for (size_t i = 0; i < reply_.length(); ++i) if (isxdigit(reply_[i])) compact += static_cast<char>(toupper(reply_[i]));
  data_.lastReply = reply_;
  if (pendingPid_ == 0xB0) {
    String lab = reply_; lab.replace("\r", " "); lab.replace("\n", " "); lab.trim();
    Serial0.printf("[ELM LAB RX] %s\n", lab.c_str());
  }
  commandPending_ = false;
  commandRetries_ = 0;
  ++data_.totalResponses;
  ++rateWindowResponses_;
  if (pendingPid_ == 0xB0) {
    data_.currentPid = "";
    status_ = "elm_lab_reply";
    reply_ = "";
    nextActionAt_ = millis() + 250;
    return;
  }
  if (mode_ == QueryMode::CanSleep) {
    if (pendingPid_ == 0xE0 && compact.indexOf("4100") >= 0) {
      // CAN woke up. Keep the BLE session; restart only the ECU/OBD discovery.
      ecuValidated_ = true;
      data_.canAwake = true;
      data_.ignitionState = data_.rpm > 0 ? "ENGINE_RUNNING" : "IGN_ON";
      memset(supportedMasks_, 0, sizeof(supportedMasks_));
      data_.supportedPids = data_.scannedPids = data_.scanProgress = 0;
      data_.standardScanComplete = false;
      activePid_ = 0xF0;
      decodeSupportMask(compact);
      mode_ = QueryMode::Vin;
      status_ = "can_awake_reading_vin";
      nextActionAt_ = millis() + OBD_COMMAND_GAP_MS;
    } else {
      data_.canAwake = false;
      data_.engineRunning = false;
      data_.ignitionState = "OFF_OR_SLEEP";
      status_ = "waiting_for_can";
      nextActionAt_ = millis() + 3000;
    }
    data_.currentPid = "";
    reply_ = "";
    return;
  }
  if (mode_ == QueryMode::Init) elmValidated_ = true;
  if (mode_ == QueryMode::Handshake) {
    if (compact.indexOf("4100") < 0) {
      status_ = "waiting_for_can";
      data_.currentPid = "";
      mode_ = QueryMode::CanSleep;
      nextActionAt_ = millis() + 1500;
    } else {
      ecuValidated_ = true;
      data_.canAwake = true;
      data_.ignitionState = data_.rpm > 0 ? "ENGINE_RUNNING" : "IGN_ON";
      activePid_ = 0xF0;
      decodeSupportMask(compact);
      mode_ = QueryMode::Vin;
      status_ = "reading_vin";
      nextActionAt_ = millis() + OBD_COMMAND_GAP_MS;
    }
  } else if (mode_ == QueryMode::Vin) {
    data_.vin = decodeVin(reply_);
    bool vinValid = data_.vin.length() == 17;
    for (size_t i = 0; i < data_.vin.length() && vinValid; ++i) vinValid = isalnum(static_cast<unsigned char>(data_.vin[i]));
    Serial0.printf("[OBD VIN] %s\n", vinValid ? data_.vin.c_str() : "decode_failed");
    if (!vinValid) {
      data_.vin = ""; data_.currentPid = ""; status_ = "vin_invalid_no_advance";
      data_.connected = false;
      if (client_ && client_->isConnected()) client_->disconnect();
      nextActionAt_ = millis() + OBD_RECONNECT_DELAY_MS;
    } else {
      mode_ = QueryMode::SupportMasks;
      scanMaskIndex_ = 1; // 0100 was already proven during ECU handshake.
      status_ = "scanning_supported_pids";
      nextActionAt_ = millis() + OBD_COMMAND_GAP_MS;
    }
  } else if (mode_ == QueryMode::SupportMasks) {
    decodeSupportMask(compact);
  } else if (mode_ == QueryMode::StandardPids) {
    ++data_.scannedPids;
    if (data_.supportedPids > 0) data_.scanProgress = min(99U, (data_.scannedPids * 100U) / data_.supportedPids);
    // Keep the dashboard values alive if their standard PID occurs in the scan.
    const uint8_t saved = activePid_;
    if (activeStandardPid_ == 0x0C) activePid_ = 1;
    else if (activeStandardPid_ == 0x0D) activePid_ = 2;
    else if (activeStandardPid_ == 0x05) activePid_ = 3;
    else if (activeStandardPid_ == 0x0F) activePid_ = 4;
    else if (activeStandardPid_ == 0x04) activePid_ = 5;
    else if (activeStandardPid_ == 0x11) activePid_ = 6;
    else if (activeStandardPid_ == 0x2F) activePid_ = 7;
    else if (activeStandardPid_ == 0x1F) activePid_ = 8;
    else if (activeStandardPid_ == 0x42) activePid_ = 9;
    if (activePid_ != saved) decodePid(compact);
    activePid_ = saved;
    Serial0.printf("[OBD SCAN] %s => %s\n", data_.currentPid.c_str(), reply_.c_str());
  } else if (mode_ == QueryMode::Normal) {
    if (activePid_ == 0x70) {
      if (compact.indexOf("43") < 0) { status_ = "dtc_stored_invalid_reply"; data_.currentPid = ""; return; }
      data_.diagnosticCodes = decodeTroubleCodesForMode(compact, "43");
      dtcStage_ = 1;
      status_ = "reading_dtc_pending";
      nextDtcCheckAt_ = 0;
    } else if (activePid_ == 0x72) {
      if (compact.indexOf("47") < 0) { status_ = "dtc_pending_invalid_reply"; data_.currentPid = ""; return; }
      data_.pendingDiagnosticCodes = decodeTroubleCodesForMode(compact, "47");
      dtcStage_ = 2;
      status_ = "reading_dtc_permanent";
      nextDtcCheckAt_ = 0;
    } else if (activePid_ == 0x73) {
      if (compact.indexOf("4A") < 0) { status_ = "dtc_permanent_invalid_reply"; data_.currentPid = ""; return; }
      data_.permanentDiagnosticCodes = decodeTroubleCodesForMode(compact, "4A");
      dtcStage_ = 3;
      data_.currentPid = "";
      status_ = "dtc_scan_complete";
      nextDtcCheckAt_ = UINT32_MAX;
    }
    else if (activePid_ == 0x71) {
      data_.clearInProgress = false;
      if (compact.indexOf("44") >= 0) {
        data_.diagnosticCodes = "";
        status_ = "dtc_cleared_verify";
        nextDtcCheckAt_ = millis() + 1500;
      } else {
        status_ = "dtc_clear_failed";
      }
    } else decodePid(compact);
  }
  data_.currentPid = "";
  reply_ = "";
}

void ObdBleService::poll() {
  const uint32_t now = millis();
  if (canMonitorActive_) {
    if (autoBcmSliceActive_ && now - autoBcmSliceStartedAt_ >= 260) stopAutoBcmSlice();
    return;
  }

  // v12.59: do not turn a single transient OBD gap into a fake engine-stop.
  // Hold RPM/engine state longer than the normal PID cadence; the event layer
  // applies an additional stop debounce before notifying the phone.
  if (lastRpmAt_ && now - lastRpmAt_ > 6500 && mode_ == QueryMode::Normal) {
    data_.rpm = 0;
    data_.engineRunning = false;
  }
  if (lastSpeedAt_ && now - lastSpeedAt_ > 3500) data_.speedKph = 0;
  if (lastEcuReplyAt_ && now - lastEcuReplyAt_ > 7000 && mode_ == QueryMode::Normal) {
    data_.rpm = 0;
    data_.speedKph = 0;
    data_.engineRunning = false;
    data_.canAwake = false;
    data_.ignitionState = "OFF_OR_SLEEP";
  }

  // A synchronous Wi-Fi scan is used here deliberately.  The previous async
  // path could stay in WIFI_SCAN_RUNNING while AP+STA/OTA was active and the
  // phone would receive no final list.  This scan is user initiated, includes
  // hidden networks, retries once on a transient failure, then returns a final
  // result before normal OBD polling resumes.
  if (wifiDiscoveryRequested_) {
    wifiDiscoveryRequested_ = false;
    data_.discoveredWifiNetworks = "";
    WiFi.mode(ENABLE_LOCAL_OTA_AP ? WIFI_AP_STA : WIFI_STA);
    WiFi.scanDelete();
    delay(120);
    int found = WiFi.scanNetworks(false, true);
    if (found < 0) {
      Serial0.printf("[OBD WIFI] first scan rc=%d, retrying\n", found);
      WiFi.scanDelete();
      delay(250);
      found = WiFi.scanNetworks(false, true);
    }
    if (found >= 0) {
      for (int i = 0; i < found; ++i) {
        String ssid = WiFi.SSID(i);
        if (ssid.isEmpty()) ssid = String("بدون اسم Wi-Fi [") + WiFi.BSSIDstr(i) + "]";
        if (!data_.discoveredWifiNetworks.isEmpty()) data_.discoveredWifiNetworks += " | ";
        if (data_.discoveredWifiNetworks.length() + ssid.length() + 3 <= 1800) data_.discoveredWifiNetworks += ssid;
      }
      status_ = data_.discoveredWifiNetworks.isEmpty() ? "wifi_networks_not_found" : "wifi_networks_found";
      Serial0.printf("[OBD WIFI] scan complete found=%d listedBytes=%u\n", found,
                     static_cast<unsigned>(data_.discoveredWifiNetworks.length()));
    } else {
      status_ = "wifi_scan_failed";
      Serial0.printf("[OBD WIFI] scan failed rc=%d\n", found);
    }
    WiFi.scanDelete();
    nextActionAt_ = millis() + 500;
    return;
  }

  // Dedicated BLE discovery.  Three passes (passive/passive/active) are more
  // reliable while this same ESP32 is also maintaining the iPhone GATT server.
  // We deduplicate by MAC in onScan(), include unnamed advertisers, and do NOT
  // auto-connect during this user-requested discovery.
  if (bleDiscoveryRequested_) {
    bleDiscoveryRequested_ = false;
    discoveredBleCount_ = 0;
    data_.discoveredAdapters = "";
    BLEScan* scan = BLEDevice::getScan();
    scan->setAdvertisedDeviceCallbacks(&scanCallbacks);
    for (int pass = 0; pass < 3; ++pass) {
      scan->setActiveScan(pass == 2);
      const uint8_t seconds = 7;
      Serial0.printf("[OBD BLE] discovery pass %d/3 active=%d\n", pass + 1, pass == 2);
      scan->start(seconds, false);
      scan->clearResults();
      delay(120);
    }
    status_ = discoveredBleCount_ ? "adapter_search_complete" : "adapter_not_found";
    Serial0.printf("[OBD BLE] discovery complete count=%u bytes=%u\n",
                   static_cast<unsigned>(discoveredBleCount_),
                   static_cast<unsigned>(data_.discoveredAdapters.length()));
    nextActionAt_ = millis() + 750;
    return;
  }

  // Backward compatibility: finish an already-running async Wi-Fi scan left by
  // an older saved state, although v12.28 no longer starts scans this way.
  if (wifiDiscoveryActive_) {
    const int found = WiFi.scanComplete();
    if (found == WIFI_SCAN_RUNNING) return;
    wifiDiscoveryActive_ = false;
    WiFi.scanDelete();
  }
  if (now - rateWindowAt_ >= 1000) {
    data_.responseRate = rateWindowResponses_;
    rateWindowResponses_ = 0;
    rateWindowAt_ = now;
  }
  if (!data_.connected) {
    if (preferredName_.isEmpty()) { status_ = "waiting_for_adapter_selection"; return; }
    if (now < nextActionAt_) return;
    if (preferredTransport_ == "WIFI") {
      if (!connectWifiAdapter()) nextActionAt_ = now + OBD_RECONNECT_DELAY_MS;
      return;
    }
    // Normal operation never performs a general BLE scan. Connect directly to
    // the saved MAC. General discovery runs only after an explicit UI request.
    if (preferredAddress_.isEmpty()) {
      status_ = "adapter_address_required";
      nextActionAt_ = now + OBD_RESCAN_DELAY_MS;
      return;
    }
    candidateAddress_ = preferredAddress_;
    candidateName_ = preferredName_ + " [" + preferredAddress_ + "]";
    status_ = "connecting_saved_adapter";
    if (!connectCandidate()) nextActionAt_ = now + OBD_RECONNECT_DELAY_MS;
    return;
  }
  if (preferredTransport_ == "WIFI") {
    while (wifiClient_.available() && reply_.length() < 600) reply_ += static_cast<char>(wifiClient_.read());
    if (!wifiClient_.connected()) { data_.connected = false; status_ = "wifi_disconnected_reconnecting"; nextActionAt_ = now + OBD_RECONNECT_DELAY_MS; return; }
  }
  consumeReply();
  if (commandPending_) {
    if (now < commandDeadlineAt_) return;
    if (commandRetries_ < 2) {
      ++commandRetries_;
      String command = pendingCommand_ + "\r";
      reply_ = "";
      if (preferredTransport_ == "WIFI") {
        if (wifiClient_.connected()) wifiClient_.print(command);
      } else if (writeChar_) {
        writeChar_->writeValue(reinterpret_cast<uint8_t*>(const_cast<char*>(command.c_str())), command.length(), writeChar_->canWrite());
      }
      commandDeadlineAt_ = now + 1800;
      status_ = "obd_waiting_reply";
      return;
    }
    commandPending_ = false;
    data_.currentPid = "";
    // If ELM itself answered initialization earlier, an ECU/PID timeout normally
    // means the vehicle CAN went to sleep. Do NOT tear down BLE to KONNWEI.
    if (preferredTransport_ == "BLE" && elmValidated_ && client_ && client_->isConnected()) {
      data_.rpm = 0;
      data_.speedKph = 0;
      data_.engineRunning = false;
      data_.canAwake = false;
      data_.ignitionState = "OFF_OR_SLEEP";
      status_ = "waiting_for_can";
      mode_ = QueryMode::CanSleep;
      sleepProbeToggle_ = false;
      nextActionAt_ = now + 1200;
      return;
    }
    // Only reconnect when communication with the adapter itself is actually lost.
    status_ = "obd_adapter_no_response_reconnecting";
    data_.connected = false;
    if (preferredTransport_ == "WIFI") wifiClient_.stop();
    else if (client_ && client_->isConnected()) client_->disconnect();
    nextActionAt_ = now + OBD_RECONNECT_DELAY_MS;
    return;
  }
  if (now < nextActionAt_) return;
  if (mode_ == QueryMode::CanSleep) {
    // Keep KONNWEI/ELM awake without dropping BLE. Alternate an adapter-local
    // voltage read (ATRV) with a lightweight 0100 probe for CAN wake-up.
    if (!sleepProbeToggle_) {
      status_ = "waiting_for_can";
      lastAtrvRequestAt_ = now;
      send("ATRV", 0xA0);
    } else {
      data_.currentPid = "0100";
      status_ = "probing_can";
      send("0100", 0xE0);
    }
    sleepProbeToggle_ = !sleepProbeToggle_;
    return;
  }
  if (mode_ == QueryMode::Init) {
    if (setupStep_ >= INIT_COUNT) {
      mode_ = QueryMode::Handshake;
      status_ = "connecting_ecu";
      nextActionAt_ = now + OBD_COMMAND_GAP_MS;
      return;
    }
    send(INIT_COMMANDS[setupStep_++], 0);
    return;
  }
  if (mode_ == QueryMode::Handshake) {
    data_.currentPid = "0100";
    send("0100", 0xE0);
    return;
  }
  if (mode_ == QueryMode::Vin) {
    data_.currentPid = "0902";
    send("0902", 0xE1);
    return;
  }
  if (mode_ == QueryMode::SupportMasks) {
    if (scanMaskIndex_ >= 6) {
      mode_ = QueryMode::StandardPids;
      status_ = "reading_standard_pids";
      return;
    }
    // Only ask the next 0x20 range when the previous bitmap says another range exists.
    while (scanMaskIndex_ < 6 && (supportedMasks_[scanMaskIndex_ - 1] & 0x00000001UL) == 0) scanMaskIndex_ = 6;
    if (scanMaskIndex_ >= 6) {
      mode_ = QueryMode::StandardPids;
      status_ = "reading_standard_pids";
      return;
    }
    const uint8_t base = scanMaskIndex_ * 0x20;
    char command[5];
    snprintf(command, sizeof(command), "01%02X", base);
    data_.currentPid = command;
    activePid_ = 0xF0 + scanMaskIndex_;
    ++scanMaskIndex_;
    send(command, activePid_);
    return;
  }
  if (mode_ == QueryMode::StandardPids) {
    sendNextStandardPid();
    return;
  }
  if (clearRequested_) {
    clearRequested_ = false;
    send("04", 0x71);
    return;
  }
  if (diagnosticScanRequested_) {
    diagnosticScanRequested_ = false;
    dtcStage_ = 0;
    status_ = "reading_dtc_stored";
    send("03", 0x70);
    return;
  }
  if (dtcStage_ > 0 && dtcStage_ < 3 && now >= nextDtcCheckAt_) {
    if (dtcStage_ == 0 || dtcStage_ >= 3) {
      dtcStage_ = 0;
      status_ = "reading_dtc_stored";
      send("03", 0x70);
    } else if (dtcStage_ == 1) {
      status_ = "reading_dtc_pending";
      send("07", 0x72);
    } else {
      status_ = "reading_dtc_permanent";
      send("0A", 0x73);
    }
    return;
  }
  // v12.67: short BCM window between normal engine PID requests.
  if (preferredTransport_ == "BLE" && now >= nextAutoBcmSliceAt_) {
    if (startAutoBcmSlice()) return;
    nextAutoBcmSliceAt_ = now + 500;
  }

  // v12.59: adapter-local battery voltage is sampled every 4 seconds even when
  // CAN is awake. ATRV reads KONNWEI supply voltage and does not depend on an
  // ECU PID, so the app keeps a genuinely live battery value across CAN sleep.
  if (now - lastAtrvRequestAt_ >= 4000) {
    lastAtrvRequestAt_ = now;
    data_.currentPid = "ATRV";
    send("ATRV", 0xA0);
    return;
  }

  // High-priority live loop: RPM and speed are sampled repeatedly so the UI
  // follows throttle/vehicle movement like a scan tool. Coolant stays
  // interleaved; PID 0142 remains as a secondary control-module voltage source.
  static const char* LIVE_CMDS[] = {"010C","010D","010C","010D","0105","010C","010D","0142"};
  static const uint8_t LIVE_IDS[] = {1,2,1,2,3,1,2,9};
  constexpr uint8_t LIVE_COUNT = sizeof(LIVE_IDS) / sizeof(LIVE_IDS[0]);
  const uint8_t step = liveStep_ % LIVE_COUNT;
  data_.currentPid = LIVE_CMDS[step];
  send(LIVE_CMDS[step], LIVE_IDS[step]);
  liveStep_ = (liveStep_ + 1) % LIVE_COUNT;
}
