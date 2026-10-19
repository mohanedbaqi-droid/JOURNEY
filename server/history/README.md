# JOURNEY history server (initial integration)

This is server **source**, not a deployed service. It subscribes to the existing MQTT state topic and exposes a protected history API.

## Deployment
1. Provision a PostgreSQL database (Supabase PostgreSQL is suitable). Run `schema.sql` in its SQL editor.
2. Deploy this folder to a Node.js 20+ server with outbound TLS MQTT access.
3. Configure `DATABASE_URL`, `MQTT_URL` (e.g. `mqtts://YOUR_EMQX_HOST:8883`), `MQTT_USERNAME`, `MQTT_PASSWORD`, `JOURNEY_DEVICE_ID`, and a new random `JOURNEY_API_TOKEN`. Never commit secrets.
4. Run `npm install && npm start`. The service listens on `PORT` or 8080. Put HTTPS in front of the API.
5. The MQTT user needs subscribe permission only to `journey/<device>/telemetry/state`, not command topics.

API endpoints (Authorization: Bearer YOUR_SERVER_API_TOKEN): `/api/trips`, `/api/stops`, `/api/trips/:id/points`, `/api/stats`. `/health` is public.

### Important limitations
- The parser recognizes GPS fields `lat/latitude/gps_lat`, `lon/lng/longitude/gps_lon`, `speed_kph/speedKph/gps_speed_kph`, `heading/course`, `rpm/engine_rpm`. **Confirm actual ESP telemetry JSON before deployment.** Without GPS coordinates in telemetry, no history is saved.
- Trips are estimated from received points; not a certified odometer. GPS jumps are filtered.
- Server-side GPS history is not yet wired into the iOS app. Do not embed the API token in a public app; add per-owner authentication or a scoped server proxy before enabling remote access.
- No offline buffering in ESP yet; gaps remain if cellular/Wi-Fi fails.
- Device isolation is enforced by a configured device ID, and the broker's device-scoped MQTT ACL is essential.

## Private 4G OTA distribution (not deployed yet)

The history API now includes a private OTA staging mechanism. It does **not** automatically deploy to the Internet and it does **not** automatically flash a vehicle.

Set server environment variables:
- `JOURNEY_OTA_FILE`: absolute persistent private path, e.g. `/var/lib/journey/firmware.bin` (not inside the public web directory)
- `JOURNEY_OTA_SIGNING_KEY`: random secret of at least 32 characters; separate from MQTT and API tokens
- `JOURNEY_OTA_PUBLIC_BASE_URL`: the public HTTPS origin only, e.g. `https://updates.example.com` (requires a real domain, TLS certificate and hosting)

Existing `JOURNEY_API_TOKEN` authenticates both staging and URL issuance. Upload the **validated** ESP32 application binary via `PUT /api/ota/firmware`, with headers `Authorization: Bearer <API_TOKEN>` and `Content-Type: application/octet-stream`. The body is the raw `firmware.bin` bytes, not the ZIP. The server enforces 100KB–3MB and ESP image magic 0xE9; this is only basic format checking, **not cryptographic firmware signing**.

Get a 15-minute signed direct-download URL from `GET /api/ota/link` with the same bearer header. The response has `url`, `sha256`, `bytes`, and `expires_at`. Only the URL is given to the ESP; never send the bearer token or signing key to it. `GET /ota/firmware.bin?exp=...&sha256=...&sig=...` validates HMAC, expiry and hash, then responds with the raw binary and a Content-Length.

**Before attempting vehicle OTA:** confirm the firmware's cellular HTTPS client trusts the deployed certificate via `OTA_ROOT_CA`; test the URL on the ESP and verify the downloaded SHA-256; confirm the running partition table and OTA slot are compatible; verify the 4G link can download the full image reliably. The current server is a distribution layer, not a complete OTA safety system: signed images, device-specific authorization, rollout controls, and rollback checks are future work. The app's existing update field still requires manual URL entry until the app is connected to `/api/ota/link`.

## Recommended hosting: Cloudflare R2 (pending account connection)

For durable OTA distribution without replacing EMQX, use a **private Cloudflare R2 bucket**. R2 presigned GET links work at the account's S3 API endpoint (`https://<account-id>.r2.cloudflarestorage.com/...`), not a custom public domain. Avoid enabling public bucket access: compiled firmware currently contains embedded credentials. Keep MQTT control on EMQX unchanged.

**Required account setup:** Create an R2 bucket such as `journey-ota-private` and scoped R2 API credentials (object read/write for that bucket), stored only in the deployment's secrets. Do not commit keys or compiled firmware to the repository. Choose a short expiration (e.g. 15 minutes) for presigned GET links; the ESP must complete download before expiry. Before deployment, verify ESP's TLS trust chain for the R2 endpoint and cellular download behavior. Do not trigger an OTA on the vehicle until verified.

The existing `/api/ota/*` endpoints use a private local persistent file and are **not yet connected to R2**. They need an R2-backed storage adapter before a free/ephemeral web host can safely serve firmware. The iOS app likewise needs integration with the authorized URL issuance endpoint. No R2 bucket, API key, or live download URL has been created by this repository change.
