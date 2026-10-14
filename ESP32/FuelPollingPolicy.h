#pragma once
#include <stdint.h>

class JourneyFuelCache {
 public:
  static constexpr uint32_t intervalMs = 300000;
  bool due(uint32_t now) const { return !attempted_ || uint32_t(now - lastAttempt_) >= intervalMs; }
  void attempted(uint32_t now) { attempted_ = true; lastAttempt_ = now; }
  bool restorePercent(int percent) {
    if (percent < 0 || percent > 100) return false;
    percent_ = uint8_t(percent); valid_ = true; return true;
  }
  bool acceptRawByte(int raw) {
    if (raw < 0 || raw > 255) return false;
    return restorePercent((raw * 100) / 255);
  }
  bool valid() const { return valid_; }
  uint8_t percent() const { return percent_; }
 private:
  bool attempted_ = false, valid_ = false;
  uint32_t lastAttempt_ = 0;
  uint8_t percent_ = 0;
};
