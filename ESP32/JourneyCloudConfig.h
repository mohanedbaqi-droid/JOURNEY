#pragma once
#include <cstring>
inline bool journeyCloudConfigReady(const char* host, const char* user, const char* password, const char* ca) {
  return host && *host && user && *user && password && *password && ca &&
    !std::strstr(host, "CHANGE_ME") && !std::strstr(user, "CHANGE_ME") && !std::strstr(password, "CHANGE_ME") &&
    std::strstr(ca, "-----BEGIN CERTIFICATE-----") && std::strstr(ca, "-----END CERTIFICATE-----");
}
