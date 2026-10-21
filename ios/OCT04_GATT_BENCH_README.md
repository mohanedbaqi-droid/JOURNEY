# JOURNEY Oct 4 direct GATT BLE comparison (bench only)

**App build:** 2.4.78 (109), from the user's current iOS branch.
**ESP source:** separate ZIP delivered in ChatGPT named `JOURNEY_KR17_9_OCT04_DIRECT_GATT_SAFE_BENCH_SOURCE.zip`.

- Reverts GATT connection sequence to October 4: discover service and characteristics -> subscribe to state notifications -> confirm readiness -> first state read and owner_status.
- No encrypted GATT read or SMP/Pair requirement before subscription. Existing state/command UUIDs are unchanged.
- Reuses current reconnection and RSSI-generation guards from the October 20 app.
- Labels UI honestly: direct, **not encrypted, not authenticated**.
- Companion ESP bench build retains original KR17.9 cellular/GPS/MQTT and KONNWEI code, but vehicle GPIO outputs and NFC are **disabled**, and all vehicle-changing commands are blocked over BLE and cloud.

**Do not install this iOS test build with an ESP firmware that permits unencrypted vehicle actuation.** The companion open-GATT ESP source is explicitly non-actuating.

## Test sequence
1. Preserve existing production ESP firmware and iPhone installation before updating.
2. Flash the non-actuating ESP bench source with matching Arduino core as KR17.9.
3. Connect using iOS app 2.4.78, 15 minutes near the board. Note BLE disconnects and connect duration.
4. Leave KONNWEI plugged in and compare iPhone vs OBD disconnects during the same period.
5. Optionally compare using nRF Connect on identical firmware and range.
6. Return to secured original build before re-enabling any remote outputs.

**Validation:** no local Xcode/Arduino board compilation was possible; host KONNWEI tests passed. GitHub iOS Actions triggered by the branch changes.
