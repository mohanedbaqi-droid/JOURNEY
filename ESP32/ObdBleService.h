#pragma once

#include <Arduino.h>
#include <BLEDevice.h>
#include <Preferences.h>
#include <WiFi.h>

struct ObdSnapshot {
  bool connected = false;
  bool engineRunning = false;
  uint16_t rpm = 0;
  uint16_t speedKph = 0;
  int16_t coolantC = 0;
  int16_t intakeAirC = 0;
  uint8_t engineLoadPercent = 0;
  uint8_t throttlePercent = 0;
  uint8_t fuelLevelPercent = 0;
  bool fuelLevelValid = false;
  uint32_t engineRuntimeSeconds = 0;
  float batteryVoltage = 0;
  bool canAwake = false;
  String ignitionState = "UNKNOWN"; // OFF_OR_SLEEP / IGN_ON / ENGINE_RUNNING
  uint32_t responseRate = 0;
  uint64_t totalResponses = 0;
  uint8_t scanProgress = 0;
  uint16_t scannedPids = 0;
  uint16_t supportedPids = 0;
  bool standardScanComplete = false;
  String currentPid;
  String lastReply;
  String adapterName;
  String discoveredAdapters;
  String discoveredWifiNetworks;
  String diagnosticCodes;
  String vin;
  String pendingDiagnosticCodes;
  String permanentDiagnosticCodes;
  uint32_t diagnosticCheckedAt = 0;
  bool clearInProgress = false;
  // v12.66 confirmed BCM/body states from exact CAN IDs.
  bool bcmStateValid = false;
  bool doorsOpen = false;
  bool locked = true;
  bool headlightsOn = false;
  bool leftSignalOn = false;
  bool rightSignalOn = false;
};

// Generic BLE ELM327 client. It supports the common FFF0/FFF1/FFF2 and
// Nordic-UART services used by Vgate/iCar and most BLE OBD adapters.
class ObdBleService {
 public:
  void begin();
  void poll();
  const ObdSnapshot& snapshot() const;
  const char* statusText() const;
  // The phone chooses the adapter once.  Its advertised name is persisted in
  // ESP flash and the ESP connects to that adapter automatically after reboot.
  void setPreferredAdapter(const String& name, const String& transport = "BLE", const String& password = "", const String& host = "192.168.0.10", uint16_t port = 35000);
  void requestAdapterDiscovery(const String& transport = "BLE");
  void forgetPreferredAdapter();
  bool requestDiagnosticScan();
  bool requestClearTroubleCodes();
  // v12.57 diagnostic lab: raw ELM console + passive CAN monitor so future BCM/body tests do not require reflashing.
  bool requestElmConsole(const String& command);
  bool startCanMonitor();
  bool stopCanMonitor();
  // Decode a raw 11-bit Journey BCM frame into the confirmed body-state map.
  // Safe to call from an exact-filter CAN reader; unknown IDs/values are ignored.
  bool applyConfirmedBcmFrame(uint16_t canId, const uint8_t* bytes, uint8_t len);
  bool canMonitorActive() const { return canMonitorActive_; }
  // BLE callback entry points; public only because the Arduino BLE callbacks
  // are small separate helper classes.
  static void onScan(BLEAdvertisedDevice device);
  static void onDisconnect(BLEClient* client);
  static void onNotify(BLERemoteCharacteristic* characteristic, uint8_t* data, size_t length, bool notify);

 private:
  static ObdBleService* instance_;
  BLEClient* client_ = nullptr;
  BLERemoteCharacteristic* writeChar_ = nullptr;
  BLERemoteCharacteristic* notifyChar_ = nullptr;
  ObdSnapshot data_{};
  String status_ = "not_started";
  String candidateAddress_;
  String candidateName_;
  String preferredName_;
  String preferredAddress_;
  String preferredTransport_ = "BLE";
  String wifiPassword_;
  String wifiHost_ = "192.168.0.10";
  uint16_t wifiPort_ = 35000;
  WiFiClient wifiClient_;
  String reply_;
  String canLineBuffer_; // passive ATMA line assembler for confirmed BCM frames
  uint8_t setupStep_ = 0;
  uint8_t pidIndex_ = 0;
  uint8_t liveStep_ = 0;
  uint32_t lastRpmAt_ = 0;
  uint32_t lastSpeedAt_ = 0;
  uint32_t lastCoolantAt_ = 0;
  uint32_t lastVoltageAt_ = 0;
  uint32_t lastAtrvRequestAt_ = 0;
  uint32_t lastEcuReplyAt_ = 0;
  uint8_t activePid_ = 0;
  uint8_t scanMaskIndex_ = 0;
  uint16_t scanPid_ = 1;
  uint16_t activeStandardPid_ = 0;
  uint32_t supportedMasks_[6]{};
  enum class QueryMode : uint8_t { Init, Handshake, Vin, SupportMasks, StandardPids, Normal, CanSleep } mode_ = QueryMode::Init;
  uint32_t nextActionAt_ = 0;
  uint32_t rateWindowAt_ = 0;
  uint32_t rateWindowResponses_ = 0;
  uint32_t nextDtcCheckAt_ = 0;
  bool clearRequested_ = false;
  bool diagnosticScanRequested_ = false;
  bool sleepProbeToggle_ = false;
  bool wifiDiscoveryActive_ = false;
  bool wifiDiscoveryRequested_ = false;
  bool bleDiscoveryRequested_ = false;
  uint16_t discoveredBleCount_ = 0;
  bool commandPending_ = false;
  bool canMonitorActive_ = false;
  String pendingCommand_;
  uint8_t pendingPid_ = 0;
  uint8_t commandRetries_ = 0;
  uint32_t commandDeadlineAt_ = 0;
  bool elmValidated_ = false;
  bool ecuValidated_ = false;
  uint8_t dtcStage_ = 0;
  Preferences storage_;

  bool connectCandidate();
  bool connectWifiAdapter();
  bool findElmCharacteristics();
  void send(const char* text, uint8_t pid = 0);
  void consumeReply();
  void decodePid(const String& compact);
  String decodeTroubleCodesForMode(const String& compact, const char* marker);
  String decodeVin(const String& raw);
  void decodeSupportMask(const String& compact);
  bool isSupportedStandardPid(uint16_t pid) const;
  void sendNextStandardPid();
  bool matchesAdapter(BLEAdvertisedDevice& device) const;
};
