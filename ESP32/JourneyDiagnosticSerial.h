#pragma once
#include <Arduino.h>
#include "JourneyLogBuffer.h"

class JourneyDiagnosticSerial : public Print {
 public:
  void begin(unsigned long baud);
  int available() { return Serial0.available(); }
  int read() { return Serial0.read(); }
  size_t write(uint8_t byte) override { return write(&byte,1); }
  size_t write(const uint8_t* buffer,size_t size) override;
  String readLog(uint32_t since, uint32_t& end, bool& lost);
};
extern JourneyDiagnosticSerial JourneySerial;
