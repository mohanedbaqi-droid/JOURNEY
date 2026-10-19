#pragma once
// JOURNEY MQTT OTA stream receiver v1. Include from the main ESP sketch.
// Call handle(topic,payload,length) BEFORE the normal command JSON dispatcher.
// Publish acknowledgments on journey/<deviceID>/ota/ack via the callback.
// IMPORTANT: increase PubSubClient buffer to >= 1536 bytes and validate MQTT
// broker ACLs before enabling this on a production vehicle.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Update.h>
#include <mbedtls/base64.h>
#include <mbedtls/sha256.h>

class JourneyStreamOTA {
public:
  using PublishAck = bool (*)(const String &topic, const String &payload);
  JourneyStreamOTA(const String &deviceID, PublishAck publish, bool (*authorized)(const String &phoneID))
    : deviceID_(deviceID), publish_(publish), authorized_(authorized) {}
  bool handle(const String &topic, const uint8_t *payload, size_t length) {
    if (topic != "journey/" + deviceID_ + "/command") return false;
    JsonDocument doc;
    if (deserializeJson(doc, payload, length)) return false;
    const String action = doc["action"] | "";
    if (action != "ota_stream_begin" && action != "ota_stream_chunk" && action != "ota_stream_abort") return false;
    const String id = doc["id"] | "";
    const String phoneID = doc["phoneID"] | "";
    if (!authorized_ || !authorized_(phoneID) || id.length() != 36) { ack(id, "error", "unauthorized"); return true; }
    if (action == "ota_stream_abort") { if (active_ && id == id_) { stop(); ack(id, "error", "cancelled"); } return true; }
    if (action == "ota_stream_begin") {
      const size_t size = doc["size"] | 0;
      const String digest = doc["sha256"] | "";
      const int chunk = doc["chunkSize"] | 0;
      if (active_ || size < 262144 || size > 3145728 || digest.length() != 64 || chunk != 384) {
        ack(id, "error", "invalid_begin"); return true;
      }
      if (!Update.begin(size, U_FLASH)) { ack(id, "error", "update_begin_failed"); return true; }
      mbedtls_sha256_init(&hash_);
      mbedtls_sha256_starts(&hash_, 0);
      hashReady_ = true;
      id_ = id; expectedHash_ = digest; expectedSize_ = size; offset_ = 0; active_ = true;
      lastChunkAt_ = millis();
      ack(id_, "ready", nullptr); return true;
    }
    if (!active_ || id != id_) { ack(id, "error", "unknown_session"); return true; }
    if (millis() - lastChunkAt_ > 180000UL) { fail("timeout"); return true; }
    const size_t at = doc["offset"] | SIZE_MAX;
    if (at != offset_) { ack(id_, "ready", nullptr); return true; }
    const char *encoded = doc["data"] | "";
    const size_t encodedLen = strlen(encoded);
    if (encodedLen == 0 || encodedLen > 512) { fail("invalid_chunk"); return true; }
    uint8_t decoded[384]; size_t decodedLen = 0;
    if (mbedtls_base64_decode(decoded, sizeof(decoded), &decodedLen,
         reinterpret_cast<const unsigned char *>(encoded), encodedLen) != 0 ||
         decodedLen == 0 || decodedLen > 384 || offset_ + decodedLen > expectedSize_ ||
         (offset_ + decodedLen < expectedSize_ && decodedLen != 384)) {
      fail("decode_failed"); return true;
    }
    if (Update.write(decoded, decodedLen) != decodedLen) { fail("flash_write_failed"); return true; }
    mbedtls_sha256_update(&hash_, decoded, decodedLen);
    offset_ += decodedLen;
    lastChunkAt_ = millis();
    if (offset_ == expectedSize_) {
      unsigned char digest[32];
      mbedtls_sha256_finish(&hash_, digest);
      mbedtls_sha256_free(&hash_); hashReady_ = false;
      char hex[65]; for (int i=0;i<32;i++) sprintf(hex + 2*i, "%02x", digest[i]);
      hex[64] = 0;
      if (!expectedHash_.equalsIgnoreCase(hex)) { fail("sha256_mismatch"); return true; }
      if (!Update.end(false)) { fail("update_end_failed"); return true; }
      ack(id_, "complete", nullptr);
      active_ = false;
      // Reboot from the main loop after MQTT has had time to flush the ACK.
      rebootPendingAt_ = millis();
      return true;
    }
    ack(id_, "ready", nullptr);
    return true;
  }
  void tick() {
    if (active_ && millis() - lastChunkAt_ > 180000UL) fail("timeout");
    if (rebootPendingAt_ && millis() - rebootPendingAt_ > 1500UL) ESP.restart();
  }
private:
  void ack(const String &id, const char *state, const char *reason) {
    JsonDocument d;
    d["id"] = id; d["state"] = state; d["nextOffset"] = offset_;
    if (reason) d["reason"] = reason;
    String out; serializeJson(d, out);
    if (publish_) publish_("journey/" + deviceID_ + "/ota/ack", out);
  }
  void stop() {
    if (active_) Update.abort();
    if (hashReady_) { mbedtls_sha256_free(&hash_); hashReady_ = false; }
    active_ = false; offset_ = 0; id_ = ""; expectedHash_ = "";
  }
  void fail(const char *reason) { ack(id_, "error", reason); stop(); }
  String deviceID_, id_, expectedHash_;
  PublishAck publish_;
  bool (*authorized_)(const String &);
  bool active_ = false, hashReady_ = false;
  size_t offset_ = 0, expectedSize_ = 0;
  unsigned long lastChunkAt_ = 0, rebootPendingAt_ = 0;
  mbedtls_sha256_context hash_;
};
