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
