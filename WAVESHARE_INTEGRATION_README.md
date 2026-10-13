# JOURNEY Waveshare integration — 2026-10-13

This branch preserves the full existing JOURNEY ESP32-S3 project and changes the hardware configuration for the Waveshare ESP32-S3-A-SIM7670X-4G V2 board.

## Files
Open `ESP32/JOURNEY_ESP32S3_OBD_BLE_V12_65.ino` in Arduino IDE. Keep `ESP32/ObdBleService.cpp`, `ESP32/ObdBleService.h`, `ESP32/config.h` and `ESP32/EspThermalPolicy.h` in the same sketch folder.

## Hardware pin mapping
- MAX17048 (Waveshare V2): SDA=15, SCL=16, enabled.
- HUD TM1637: CLK=12, DIO=13, moved off gauge pins.
- NFC PN532 I2C: SDA=8, SCL=9, IRQ=21, RESET=47 (external module, untested on this board).
- Fob: lock=4, unlock=5, start=6, alarm=7, BD140 power=10; outputs disabled until wiring verified.
- SIM7670G: modem RX=17, TX=18 (retained from original firmware).
- OBD: KONNWEI BLE adapter; no direct CAN transceiver.
- No ACC, AUX, or engine cut outputs in JOURNEY.

**Board DIP switches:** keep CAM and TF card usage OFF if using their shared pins for HUD/NFC/fob.

## BCM
The existing `ObdBleService.cpp` decodes frames 0x108, 0x180, 0x334, 0x324, 0x318 via `applyConfirmedBcmFrame`. Automatic BCM slices remain disabled by configuration because the existing raw scheduler owns the adapter; do not enable simultaneous raw monitoring and PID polling without testing.

## Security and commissioning
`ENABLE_OUTPUTS=false` and `ALLOW_REMOTE_START=false`. This is deliberate: the user has not wired or tested the fob, and remote engine start requires real safety checks. Do not change these until output polarities and vehicle interlocks are verified. BLE owner credentials remain in NVS; avoid Erase All Flash.

## Limitations
This branch has not been compiled or tested on the target Waveshare board. The 4G data/MQTT path needs valid credentials, SIM provisioning, and on-device verification. NFC/HUD require their physical modules. The MAX17048 percentage may need plausibility checks. It is full project source, not a proven production firmware binary.
