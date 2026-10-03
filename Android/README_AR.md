# JOURNEY Android
نسخة Android الأصلية المتوافقة مع ESP32 firmware v12.65.

- Native Kotlin + Jetpack Compose
- minSdk 18 / targetSdk 35
- الصفحات: الرئيسية، السيارة، الخريطة، OBD، الإعدادات/المعلومات
- BLE إلى ESP، owner/keyless، OBD BLE/Wi-Fi، Wi-Fi العام، 4G/Hotspot، أولوية الاتصال.
- بروتوكول الأوامر schema=1 مطابق لنسخة iOS وESP32.

> Android 6+ يحتاج Location لمسح BLE القديم، Android 12+ يحتاج BLUETOOTH_SCAN/CONNECT، Android 13+ يحتاج إذن Notifications.
