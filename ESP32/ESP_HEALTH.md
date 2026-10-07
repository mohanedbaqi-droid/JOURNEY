# ESP health v12.78

Every 2 seconds the ESP samples its internal die temperature. BLE uses a separate
partial `espHealthPacket` (<512 bytes); MQTT includes the same fields. Health
packets never refresh OBD or BCM readings. Apps expire health after 10 seconds.

Warnings are operational presets, not certified hardware limits: high defaults
to 50°C, adjustable from 35–75°C in 1°C steps using `esp_settings` with
`espSettings.espTempWarningC`. ESP clamps and persists the value in NVS
`tempWarnC`, reports it in health packets, and samples again after a change.
Apps confirm saving only after the ESP reports the requested value.
High clears below the chosen threshold minus 5°C; critical remains at 80°C
and clears below 75°C into the corresponding high/normal state. Sensor ranges switch
between -10..80°C and 50..125°C. Invalid readings display unavailable. A high
chip reading is not evidence that a battery is safe, or that heat caused a reset.
Reset reason 9 is shown as brownout separately. No brownout protection is disabled.
ESP events are replayed using the existing event acknowledgement mechanism.
Android additionally posts a notification on a fresh upward warning transition
when the app has a live connection and notification permission. This adds no
background Android monitoring service.

## Battery measurement

Generic N16R8 board: no onboard fuel gauge; default build leaves gauge disabled.
Never use the OBD vehicle battery voltage as the ESP battery voltage or estimate
state of charge from a USB/3.3V supply rail.

Waveshare ESP32-S3-SIM7670G: MAX17048 at I2C address 0x36. Its VCELL register
0x02 is 78.125µV/LSB; SOC register 0x04 is 1/256 percent/LSB. Reads are bounded
and invalid/no-device replies yield unavailable. Sensor reads only; no writes.

Enable `ESP_BATTERY_GAUGE_ENABLED` in config.h only after checking actual board:
V1 SDA=3, SCL=2; V2 SDA=15, SCL=16. V2 conflicts with the current TM1637 HUD.
Remap/disable that device and audit the remaining board pin assignments first;
the generic firmware is not a complete port to the Waveshare board. Gauge data
requires a connected battery; charger-only readings must not be taken as proof
of battery presence. No charging status is inferred without a charging signal.

Sources:
https://docs.waveshare.com/ESP32-S3-SIM7670G-4G/Arduino
https://www.analog.com/media/en/technical-documentation/data-sheets/max17048-max17049.pdf
https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-reference/peripherals/temp_sensor.html
