#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

// Monotonic byte cursor, bounded RAM and explicit overrun detection.
template<size_t Capacity> struct JourneyLogBuffer {
  char bytes[Capacity] = {};
  uint32_t end = 0;
  void append(const uint8_t* data, size_t size) {
    for (size_t i=0;i<size;++i) bytes[end++ % Capacity]=static_cast<char>(data[i]);
  }
  std::string read(uint32_t since, bool& lost) const {
    const uint32_t start=end>Capacity ? end-Capacity : 0;
    lost=since<start || since>end;
    const uint32_t first=since>end ? start : (since<start ? start : since);
    std::string result; result.reserve(end-first);
    for(uint32_t i=first;i<end;++i) result+=bytes[i%Capacity];
    return result;
  }
};
