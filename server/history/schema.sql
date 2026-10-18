CREATE TABLE IF NOT EXISTS journey_trips (
 id BIGSERIAL PRIMARY KEY, device_id TEXT NOT NULL,
 started_at TIMESTAMPTZ NOT NULL, ended_at TIMESTAMPTZ,
 start_lat DOUBLE PRECISION NOT NULL, start_lon DOUBLE PRECISION NOT NULL,
 end_lat DOUBLE PRECISION, end_lon DOUBLE PRECISION,
 distance_m DOUBLE PRECISION NOT NULL DEFAULT 0,
 max_speed_kph DOUBLE PRECISION NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS journey_trips_device_time ON journey_trips(device_id,started_at DESC);
CREATE TABLE IF NOT EXISTS journey_points (
 id BIGSERIAL PRIMARY KEY, device_id TEXT NOT NULL,
 trip_id BIGINT REFERENCES journey_trips(id) ON DELETE SET NULL,
 recorded_at TIMESTAMPTZ NOT NULL,
 lat DOUBLE PRECISION NOT NULL CHECK(lat BETWEEN -90 AND 90),
 lon DOUBLE PRECISION NOT NULL CHECK(lon BETWEEN -180 AND 180),
 speed_kph DOUBLE PRECISION, heading DOUBLE PRECISION,
 engine_running BOOLEAN, accuracy_m DOUBLE PRECISION
);
CREATE INDEX IF NOT EXISTS journey_points_trip_time ON journey_points(trip_id,recorded_at);
CREATE INDEX IF NOT EXISTS journey_points_device_time ON journey_points(device_id,recorded_at DESC);
CREATE TABLE IF NOT EXISTS journey_stops (
 id BIGSERIAL PRIMARY KEY, device_id TEXT NOT NULL,
 trip_id BIGINT REFERENCES journey_trips(id) ON DELETE SET NULL,
 arrived_at TIMESTAMPTZ NOT NULL, departed_at TIMESTAMPTZ,
 lat DOUBLE PRECISION NOT NULL, lon DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS journey_stops_device_time ON journey_stops(device_id,arrived_at DESC);
-- Run the history service using a dedicated database role with only required table permissions.
-- Do not expose these tables directly to public clients.
