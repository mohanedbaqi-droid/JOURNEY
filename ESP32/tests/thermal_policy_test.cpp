#include "../EspThermalPolicy.h"
#include <cassert>
int main() {
  assert(espThermalNextLevel(49, 0, 50) == 0);
  assert(espThermalNextLevel(50, 0, 50) == 1);
  assert(espThermalNextLevel(46, 1, 50) == 1);
  assert(espThermalNextLevel(44, 1, 50) == 0);
  assert(espThermalNextLevel(55, 0, 50) == 1); // Lowering threshold triggers warning.
  assert(espThermalNextLevel(55, 1, 65) == 0); // Raising threshold clears warning.
  assert(espThermalNextLevel(80, 0, 35) == 2);
  assert(espThermalNextLevel(76, 2, 75) == 2);
  assert(espThermalNextLevel(74, 2, 75) == 1);
  assert(espThermalNextLevel(69, 2, 75) == 0);
  assert(espThermalNextLevel(35, 0, 35) == 1);
}
