#include "JourneyDiagnosticSerial.h"
#include <esp_log.h>
#include <cstdarg>
#include <cstdio>
#include <vector>

JourneyDiagnosticSerial JourneySerial;
static JourneyLogBuffer<8192> logBuffer;
static portMUX_TYPE logMux=portMUX_INITIALIZER_UNLOCKED;
static vprintf_like_t previousLogger=nullptr;
static void capture(const uint8_t* bytes,size_t n) {
  portENTER_CRITICAL(&logMux); logBuffer.append(bytes,n); portEXIT_CRITICAL(&logMux);
}
static int captureSystemLog(const char* format, va_list args) {
  va_list copy; va_copy(copy,args);
  const int n=vsnprintf(nullptr,0,format,copy); va_end(copy);
  if(n>0 && n<=8192) {
    std::vector<char> text(n+1); va_copy(copy,args);
    vsnprintf(text.data(),text.size(),format,copy); va_end(copy);
    capture(reinterpret_cast<const uint8_t*>(text.data()),n);
  }
  return previousLogger ? previousLogger(format,args) : vprintf(format,args);
}
void JourneyDiagnosticSerial::begin(unsigned long baud) {
  Serial0.begin(baud);
  previousLogger=esp_log_set_vprintf(captureSystemLog);
}
size_t JourneyDiagnosticSerial::write(const uint8_t* buffer,size_t size) {
  capture(buffer,size);
  return Serial0.write(buffer,size);
}
String JourneyDiagnosticSerial::readLog(uint32_t since,uint32_t& end,bool& lost) {
  // Allocate before taking the cross-core lock; copying bytes never allocates in the critical section.
  std::vector<char> bytes(8193);
  size_t length=0;
  portENTER_CRITICAL(&logMux);
  end=logBuffer.end;
  const uint32_t start=end>8192 ? end-8192 : 0;
  lost=since<start || since>end;
  const uint32_t first=since>end ? start : (since<start ? start : since);
  for(uint32_t i=first;i<end;++i) bytes[length++]=logBuffer.bytes[i%8192];
  portEXIT_CRITICAL(&logMux);
  bytes[length]=0;
  // A wrapped ring may begin inside a UTF-8 character; omit the partial leading line.
  size_t first=0;
  if(lost) { while(first<length && bytes[first]!='\n') ++first; if(first<length) ++first; }
  return String(bytes.data()+first);
}
