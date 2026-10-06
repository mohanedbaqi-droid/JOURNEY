# Punisher Drive

This branch is reserved for the general multi-vehicle Punisher Drive project and must remain separate from the JOURNEY main branch.

## Current architecture
- Customer vehicle selection: Make -> Model -> Year only.
- Selected Vehicle Profile controls UI assets and available features.
- ESP receives and persists the selected vehicle profile ID.
- Technical connection/protocol settings remain hidden from the customer.

## Separate identifiers/settings
- iOS bundle ID target: `com.abuseif.punisherdrive`
- Widget bundle ID target: `com.abuseif.punisherdrive.widget`
- ESP device ID default: `punisher-drive-esp32s3-01`
- ESP NVS namespace: `punisher`
- OBD preferences namespace: `punisher-obd`
- MQTT topic root: `punisher/`
- Hotspot SSID: `PUNISHER-DRIVE`

Journey production code remains on `main`. Punisher Drive development belongs on the `punisher-drive` branch until moved to its own repository.