# Punisher Drive Vehicle Protocol v1 — draft for bench testing
Status: **design contract only**. ESP32, 4G/GPS modem, BLE OBD and server adapter are not implemented or certified by this document.

## Separation of modes
- `simulation` is opt-in, on-device, uses synthetic data, and has **no transport**. Apps must label every simulated status and action. Demo state never counts as a connected device.
- `live` must be activated only after successful authenticated ownership pairing AND transport verification. Hardware adapters should not reuse demo state objects.
- Never upload user documents or vehicle telemetry without explicit authorization. Credentials and private keys must be provisioned separately; never committed to Git.

## Envelopes
All frames encoded UTF-8 JSON (BLE GATT payloads will require length framing and MTU fragmentation/reassembly). Example telemetry:
```json
{"version":1,"type":"telemetry","deviceId":"unit-123","vehicleId":"car-uuid","seq":101,"sentAt":"2026-10-12T00:00:00Z","data":{"engineRunning":false,"locked":true,"doorsClosed":true,"parked":true,"speedKmh":0,"rpm":0,"batteryV":12.5,"espTempC":32.1,"gps":{"valid":false},"obd":{"connected":false,"dtcs":[]}}}
```
A control request:
```json
{"version":1,"type":"command","requestId":"uuid-v4","deviceId":"unit-123","vehicleId":"car-uuid","seq":102,"sentAt":"2026-10-12T00:00:00Z","expiresAt":"2026-10-12T00:00:15Z","command":"lock","params":{}}
```
A device response:
```json
{"version":1,"type":"ack","requestId":"uuid-v4","deviceId":"unit-123","seq":102,"accepted":false,"reason":"not-paired"}
```
An ACK only confirms acceptance/rejection, **not** that a lock or starter physically operated. Real state must be read back from a verified input, or shown as unknown.

## Command and safety requirements
- Commands allowed for initial *hardware development*: `lock`, `unlock`, `start`, `stop`, `alarm`; never assume all car models support them.
- Pair owner/admin with a per-device secret/key, verify signed requests, secure BLE bonding and TLS for internet. Require nonce/sequence anti-replay, allowlisted device ID and vehicle ID; fail closed on expired, duplicate or out-of-order requests.
- `start` requires explicit user authentication/confirmation, transmission in Park, vehicle stationary, hood closed, doors safe, valid immobilizer authorization and known engine state. Missing or stale safety signals -> DENY. Never bridge arbitrary OBD/CAN frames.
- Hardware watchdog, remote start timeout, high/low voltage protection and physical override required. Stop remote start when a door/hood safety condition changes.
- Every command must return a status code (`accepted`, `denied`, `timeout`, `fault`), followed by independently verified state. Retry only idempotent requests with same `requestId`.
- GPS samples include timestamp/accuracy and explicit `valid`; simulator coordinates must not be displayed as real tracking.
- OBD read access requires support detection and never assume BCAN/doors are standard PIDs. Separate BLE OBD adapter from vehicle control controller.
- No remote owner enrolment, pairing reset, unlocking or engine start without local authorization and audit logging.

## Next hardware integration gates
1. ESP32 simulator board: accept authenticated mock frames on a bench and ACK; **no vehicle GPIO**.
2. ESP32 + modem: tests for disconnect/reconnect, clocks, TLS identity, watchdog and anti-replay.
3. BLE OBD: discover supported adapter, read VIN/voltage/PIDs where supported; clearly label unavailable sensors.
4. Vehicle bench: fused 12V->5V converter, safe I/O isolation, proof of lock/start interlocks.
5. Stationary vehicle test with owner present; only then enable `live` in a separately reviewed build.
