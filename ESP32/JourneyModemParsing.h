#pragma once
#include <cmath>
#include <cstdlib>
#include <cstring>

inline int journeyCsqDbm(int csq) {
  return csq >= 0 && csq <= 31 ? -113 + 2 * csq : -120;
}

// CGPSINFO uses degrees/minutes. Reject empty and malformed fields rather
// than turning an invalid numeric string into a plausible zero coordinate.
inline bool journeyCoordinate(const char* field, char hemisphere, bool latitude, double& result) {
  if (!field || !*field) return false;
  if (latitude ? (hemisphere != 'N' && hemisphere != 'S') : (hemisphere != 'E' && hemisphere != 'W')) return false;
  char* end = nullptr;
  const double raw = std::strtod(field, &end);
  if (end == field || *end || !std::isfinite(raw) || raw < 0) return false;
  const int degrees = static_cast<int>(raw / 100.0);
  const double minutes = raw - degrees * 100.0;
  if (minutes < 0 || minutes >= 60) return false;
  const double coordinate = degrees + minutes / 60.0;
  if (coordinate > (latitude ? 90.0 : 180.0)) return false;
  result = (hemisphere == 'S' || hemisphere == 'W') ? -coordinate : coordinate;
  return true;
}

inline bool journeyGpsFix(const char* response, double& lat, double& lon) {
  if (!response) return false;
  const char* payload = std::strstr(response, "+CGPSINFO:");
  if (!payload) return false;
  payload += std::strlen("+CGPSINFO:");
  while (*payload == ' ') ++payload;
  char buffer[220];
  const size_t length = std::strcspn(payload, "\r\n");
  if (length >= sizeof(buffer)) return false;
  std::memcpy(buffer, payload, length);
  buffer[length] = 0;
  // Preserve empty CSV fields: strtok would shift the hemisphere columns.
  char* fields[9] = {buffer};
  size_t count = 1;
  for (char* p = buffer; *p && count < 9; ++p) {
    if (*p == ',') { *p = 0; fields[count++] = p + 1; }
  }
  double nextLat, nextLon;
  if (count < 4 || std::strlen(fields[1]) != 1 || std::strlen(fields[3]) != 1 ||
      !journeyCoordinate(fields[0], fields[1][0], true, nextLat) ||
      !journeyCoordinate(fields[2], fields[3][0], false, nextLon)) return false;
  lat = nextLat;
  lon = nextLon;
  return true;
}

// CEREG? returns <n>,<stat>[,...]; 1=home, 5=roaming. Ignore optional location fields.
inline bool journeyNetworkRegistered(const char* reply) {
  if (!reply) return false;
  const char* p = std::strstr(reply, "+CEREG:");
  if (!p) return false;
  p += 7;
  char* end = nullptr;
  std::strtol(p, &end, 10);
  if (end == p) return false;
  while (*end == ' ') ++end;
  if (*end != ',') return false;
  p = end + 1;
  const long state = std::strtol(p, &end, 10);
  return end != p && (state == 1 || state == 5);
}
