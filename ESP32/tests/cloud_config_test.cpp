#include "../JourneyCloudConfig.h"
#include <cassert>
int main() {
 const char* pem="-----BEGIN CERTIFICATE-----\nexample\n-----END CERTIFICATE-----";
 assert(!journeyCloudConfigReady("broker", "esp", "CHANGE_ME", pem));
 assert(!journeyCloudConfigReady("broker", "esp", "pass", "A placeholder comment longer than forty characters is not a certificate"));
 assert(!journeyCloudConfigReady("broker", "esp", "pass", "-----BEGIN CERTIFICATE-----"));
 assert(!journeyCloudConfigReady("", "esp", "pass", pem));
 assert(journeyCloudConfigReady("broker", "esp", "pass", pem));
}
