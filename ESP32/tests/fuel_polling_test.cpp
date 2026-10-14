#include "../FuelPollingPolicy.h"
#include <cassert>
#include <cstdint>

int main() {
  JourneyFuelCache fuel;
  assert(!fuel.valid() && fuel.due(0));
  assert(fuel.acceptRawByte(115) && fuel.percent() == 45);
  fuel.attempted(10);
  assert(!fuel.due(300009) && fuel.due(300010));
  // A failed attempt starts the interval too, while retaining the last sample.
  fuel.attempted(300010);
  assert(!fuel.acceptRawByte(-1) && !fuel.acceptRawByte(256));
  assert(fuel.valid() && fuel.percent() == 45 && !fuel.due(300011));
  assert(fuel.due(600010));
  assert(fuel.acceptRawByte(0) && fuel.valid() && fuel.percent() == 0);
  assert(fuel.acceptRawByte(255) && fuel.percent() == 100);
  JourneyFuelCache reboot;
  assert(reboot.restorePercent(45) && reboot.percent() == 45 && reboot.due(0));
  assert(!reboot.restorePercent(101) && reboot.percent() == 45);
  fuel.attempted(UINT32_MAX - 100);
  assert(!fuel.due(299898) && fuel.due(299899));
}
