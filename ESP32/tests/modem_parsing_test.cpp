#include "../JourneyModemParsing.h"
#include <cassert>

int main() {
  assert(journeyCsqDbm(0) == -113);
  assert(journeyCsqDbm(31) == -51);
  assert(journeyCsqDbm(99) == -120);
  assert(journeyCsqDbm(-1) == -120);
  double lat = 1, lon = 2;
  assert(journeyGpsFix("+CGPSINFO:3030.000000,N,04748.000000,E,131026,120000.0,5,0,0\r\nOK", lat, lon));
  assert(std::fabs(lat - 30.5) < 0.000001 && std::fabs(lon - 47.8) < 0.000001);
  assert(journeyGpsFix("+CGPSINFO:3030.0,S,04748.0,W,,,,,", lat, lon));
  assert(lat < 0 && lon < 0);
  const double previousLat = lat, previousLon = lon;
  assert(!journeyGpsFix("+CGPSINFO:,,,,,,,,", lat, lon));
  assert(!journeyGpsFix("+CGPSINFO:,3030.0,N,04748.0,E,,,", lat, lon));
  assert(!journeyGpsFix("+CGPSINFO:bad,N,04748.0,E", lat, lon));
  assert(!journeyGpsFix("+CGPSINFO:3060.0,N,04748.0,E", lat, lon));
  assert(!journeyGpsFix("+CGPSINFO:9030.0,N,04748.0,E", lat, lon));
  assert(!journeyGpsFix("+CGPSINFO:nan,N,04748.0,E", lat, lon));
  assert(lat == previousLat && lon == previousLon);
}
