#include "../JourneyLogBuffer.h"
#include <cassert>
int main() {
 JourneyLogBuffer<8> log; bool lost=false;
 log.append(reinterpret_cast<const uint8_t*>("abcd"),4);
 assert(log.read(0,lost)=="abcd" && !lost);
 assert(log.read(4,lost).empty() && !lost);
 log.append(reinterpret_cast<const uint8_t*>("efghij"),6);
 assert(log.read(0,lost)=="cdefghij" && lost);
 assert(log.read(4,lost)=="efghij" && !lost);
 assert(log.read(100,lost)=="cdefghij" && lost); // ESP reboot or invalid prior cursor
}
