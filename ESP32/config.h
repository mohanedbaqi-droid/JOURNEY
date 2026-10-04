#pragma once

// General Wi-Fi is controlled at runtime from the iPhone and persisted in NVS.
// No compile-time ENABLE_WIFI switch is used.
// Local Wi-Fi used only for firmware updates from the iPhone.
constexpr bool ENABLE_LOCAL_OTA_AP = true;
constexpr char OTA_AP_PASSWORD[] = "CHANGE_ME";
constexpr bool ENABLE_CELLULAR = true;
// APN for downloading a firmware URL through the SIM7670/SIM7600 modem.
constexpr char CELLULAR_APN[] = "internet";
constexpr bool ENABLE_GNSS = true;
// OBD BLE: لا تربط MCP2515 ولا CAN-H/CAN-L بهذا الإصدار.
// الاسم يُحفظ من التطبيق بعد اختيار القطعة. هذا الحقل مجرد بديل أولي
// إذا تريد تثبيت الاسم يدوياً قبل الرفع.
constexpr char OBD_BLE_NAME[] = "KONNWEI";
constexpr char OBD_BLE_ADDRESS[] = "22:C0:20:12:8A:EE";
// Many KONNWEI adapters advertise slowly after power-up.  Give BLE discovery
// a full window before reporting that no adapter was found.
constexpr uint8_t OBD_SCAN_SECONDS = 20; // manual discovery only
constexpr uint32_t OBD_RESCAN_DELAY_MS = 6000;
constexpr uint32_t OBD_RECONNECT_DELAY_MS = 4000;
constexpr uint32_t OBD_COMMAND_GAP_MS = 80;
// KONNWEI BLE adapters can lose standard PID replies after automatic ATMA/BCM
// monitor slices. Leave this off for dependable continuous RPM/speed telemetry.
constexpr bool ENABLE_AUTO_BCM_SLICES = false;
// فعّلها فقط بعد تحديد المخارج وفحص كل قناة بالأفوميتر.
constexpr bool ENABLE_OUTPUTS = true;
// غيّرها إلى true لرفعة واحدة فقط إذا بدّلت الآيفون، ثم أرجعها false.
constexpr bool CLEAR_TRUSTED_PHONE_ON_BOOT = false;

constexpr char WIFI_SSID[] = "CHANGE_ME";
constexpr char WIFI_PASSWORD[] = "CHANGE_ME";


constexpr char MQTT_HOST[] = "CHANGE_ME";
constexpr uint16_t MQTT_PORT = 8883;
constexpr char MQTT_USERNAME[] = "CHANGE_ME";
constexpr char MQTT_PASSWORD[] = "CHANGE_ME";
constexpr char DEVICE_ID[] = "journey-esp32s3-01";

// Waveshare ESP32-S3-SIM7670G-4G modem UART.
constexpr int MODEM_RX_PIN = 17;
constexpr int MODEM_TX_PIN = 18;
constexpr uint32_t MODEM_BAUD = 115200;
constexpr uint32_t GNSS_QUERY_INTERVAL_MS = 10000;
constexpr uint32_t GPS_FIX_MAX_AGE_MS = 30000;

// أزرار الريموت سالبة مباشرة، بدون أوتوكبلر: كل GPIO يمر عبر مقاومة 1k
// إلى طرف إشارة الزر، وسالب الريموت مشترك مع GND الـESP. في وضع السكون
// تبقى الأرجل INPUT (عائمة)؛ أثناء النبضة فقط تصير OUTPUT LOW.
constexpr uint16_t REMOTE_BUTTON_SERIES_RESISTOR_OHMS = 1000;
// نبضة زر الريموت: 450ms.
constexpr uint32_t OUTPUT_PULSE_MS = 450;
constexpr bool ALLOW_REMOTE_START = false;
// ترتيب التوصيل النهائي للريموت:
// GPIO4 قفل، GPIO5 فتح، GPIO6 تشغيل، GPIO7 إنذار.
// GPIO10 يذهب إلى قاعدة BD140: HIGH يطفئ طاقة الريموت و LOW يشغّلها.
constexpr int LOCK_PIN = 4;
constexpr int UNLOCK_PIN = 5;
constexpr int START_PIN = 6;
constexpr int ALARM_PIN = 7;
constexpr int REMOTE_POWER_PIN = 10;
constexpr uint32_t REMOTE_POWER_WAKE_DELAY_MS = 1000;
constexpr uint32_t REMOTE_POWER_OFF_DELAY_MS = 2000;
// Presence is reported by each authorised phone over BLE. The car locks only
// after the final nearby phone is gone for this delay.
constexpr uint32_t KEYLESS_DEFAULT_LOCK_DELAY_MS = 20000;
constexpr uint32_t KEYLESS_PRESENCE_STALE_MS = 12000;
constexpr int DOORS_PIN = -1;
// زر الإنذار في ريموت السيارة هو نفس أمر horn في التطبيق.
constexpr int HORN_PIN = ALARM_PIN;
constexpr int LIGHTS_PIN = -1;
// الإضاءة والإشارات لا تقرأ من OBD القياسي، لا تتصل بأي GPIO.
constexpr int LEFT_SIGNAL_PIN = -1;
constexpr int RIGHT_SIGNAL_PIN = -1;

// الملحقات الاختيارية، لا تدخل في مخارج الريموت.
// TM1637 (4 digits): CLK=15, DIO=16. Supply the module at 3.3 V.
constexpr int TM1637_CLK_PIN = 15;
constexpr int TM1637_DIO_PIN = 16;
constexpr uint8_t TM1637_BRIGHTNESS = 5;
// PN532 بوضع I2C: SDA=8 و SCL=9.
constexpr int PN532_SDA_PIN = 8;
constexpr int PN532_SCL_PIN = 9;
constexpr int PN532_IRQ_PIN = 21;
constexpr int PN532_RESET_PIN = 47;
constexpr bool ENABLE_PN532 = true;

// ألصق شهادة Root CA الخاصة بالـ broker بين السطرين.
constexpr char MQTT_ROOT_CA[] = R"PEM(
)PEM";

constexpr char BLE_SERVICE_UUID[] = "AF10A000-17B7-4A86-A7D7-9A3B40C8D001";
constexpr char BLE_COMMAND_UUID[] = "AF10A001-17B7-4A86-A7D7-9A3B40C8D001";
constexpr char BLE_STATE_UUID[] = "AF10A002-17B7-4A86-A7D7-9A3B40C8D001";
constexpr uint32_t STATE_INTERVAL_MS = 250;
