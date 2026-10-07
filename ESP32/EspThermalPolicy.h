#pragma once
// Warning hysteresis prevents repeated alerts near the user-selected threshold.
inline int espThermalNextLevel(float sample, int previous, int warning) {
  if (sample >= 80 || (previous == 2 && sample >= 75)) return 2;
  if (sample >= warning) return 1;
  if (sample < warning - 5) return 0;
  return previous == 2 ? 1 : previous;
}
