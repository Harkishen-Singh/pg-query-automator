-- This file contains SQL script to mimic a real-world IoT database. It supports following features:
-- 1. Tables
-- 2. Foreign key references
-- 3. Custom types
-- 4. Plain & Materialised views
-- 5. PLPGSQL functions
-- 6. Table inheritance
-- 7. Hash partitioning
-- 8. RBAC
--
-- The aim of this file is to create sufficiently large database that can be used to test Hypershift
-- migrations. At present, this files creates a 10 GB database. You can increase the size of the database
-- in multiples of 10 GB, by calling the clone_schema() function. Each call increases the database size by 10 GB.

CREATE SCHEMA iot_1;

-- Create custom types
CREATE TYPE iot_1.sensor_type AS ENUM ('temperature', 'humidity', 'pressure');

-- Create tables
CREATE TABLE iot_1.device (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    location VARCHAR(100) NOT NULL
);

INSERT INTO iot_1.device (name, location)
SELECT
    'Device ' || series_num,
    'Location ' || series_num
FROM generate_series(1, 100000) AS series_num;

CREATE TABLE iot_1.sensor (
    id SERIAL PRIMARY KEY,
    device_id INTEGER NOT NULL REFERENCES iot_1.device (id),
    type iot_1.sensor_type NOT NULL,
    name VARCHAR(50) NOT NULL,
    UNIQUE (device_id, name)
);

-- [EXPENSIVE]
INSERT INTO iot_1.sensor (device_id, type, name)
SELECT
    (SELECT id FROM iot_1.device ORDER BY random() LIMIT 1),
    CASE floor(random() * 3)::integer
        WHEN 0 THEN 'temperature'::iot_1.sensor_type
        WHEN 1 THEN 'humidity'::iot_1.sensor_type
        WHEN 2 THEN 'pressure'::iot_1.sensor_type
    END,
    'Sensor ' || series_num
FROM generate_series(1, 1000000) AS series_num;

CREATE TABLE iot_1.measurement (
    id SERIAL,
    sensor_id INTEGER NOT NULL,
    value FLOAT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (is_archived = false),
    FOREIGN KEY (sensor_id) REFERENCES iot_1.sensor (id),
    PRIMARY KEY (id, sensor_id)
);

-- [EXPENSIVE]
DO $$
DECLARE
    max_series_num INTEGER := 0;
BEGIN
    FOR i IN 1..20 LOOP
        INSERT INTO iot_1.measurement (sensor_id, value, timestamp)
        SELECT
            (SELECT id FROM iot_1.sensor ORDER BY random() LIMIT 1),
            random() * 100,
            NOW() - (random() * 365 + 1) * INTERVAL '1 day'
        FROM generate_series(max_series_num + 1, max_series_num + 1000000) AS series_num;

        SELECT max_series_num + 1000000 INTO max_series_num;

        RAISE NOTICE 'Inserted batch % of 1 million items', i;
        COMMIT;
    END LOOP;
END $$;

-- Let's duplicate the measurement table to increase the size of the database.
-- With 6 duplications, we get ~10GB in size.
CREATE TABLE iot_1.measurement_duplicate_1 AS
SELECT * FROM iot_1.measurement;

CREATE TABLE iot_1.measurement_duplicate_2 AS
SELECT * FROM iot_1.measurement;

CREATE TABLE iot_1.measurement_duplicate_3 AS
SELECT * FROM iot_1.measurement;

CREATE TABLE iot_1.measurement_duplicate_4 AS
SELECT * FROM iot_1.measurement;

CREATE TABLE iot_1.measurement_duplicate_5 AS
SELECT * FROM iot_1.measurement;

CREATE TABLE iot_1.measurement_duplicate_6 AS
SELECT * FROM iot_1.measurement;

-- Create indexes
CREATE INDEX idx_measurement_sensor_id ON iot_1.measurement (sensor_id);
CREATE INDEX idx_measurement_timestamp ON iot_1.measurement (timestamp);

-- Create functions
CREATE FUNCTION iot_1.get_average_measurement(sensor_id INT, start_date DATE, end_date DATE)
    RETURNS FLOAT AS $$
    BEGIN
        RETURN (
            SELECT AVG(value)
            FROM iot_1.measurement
            WHERE sensor_id = iot_1.get_average_measurement.sensor_id
                AND timestamp >= iot_1.get_average_measurement.start_date
                AND timestamp < iot_1.get_average_measurement.end_date
        );
    END;
$$ LANGUAGE plpgsql;

-- Create views
CREATE OR REPLACE VIEW iot_1.latest_measurement AS
    SELECT DISTINCT ON (sensor_id)
        sensor_id,
        value,
        timestamp
    FROM iot_1.measurement
    ORDER BY sensor_id, timestamp DESC;

-- Create materialized views
CREATE MATERIALIZED VIEW iot_1.aggregated_measurement AS
    SELECT
        sensor_id,
        date_trunc('hour', timestamp) AS hour,
        AVG(value) AS average_value
    FROM iot_1.measurement
    WHERE NOT is_archived
    GROUP BY sensor_id, hour;

CREATE UNIQUE INDEX idx_aggregated_measurement_sensor_hour
    ON iot_1.aggregated_measurement (sensor_id, hour);

CREATE OR REPLACE FUNCTION iot_1.refresh_aggregated_measurement()
    RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY iot_1.aggregated_measurement;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a trigger to invoke the refresh function
CREATE TRIGGER trigger_refresh_aggregated_measurement
    AFTER INSERT OR UPDATE OR DELETE ON iot_1.measurement
    EXECUTE FUNCTION iot_1.refresh_aggregated_measurement();

CREATE TABLE iot_1.location (
    id SERIAL PRIMARY KEY,
    sensor_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    FOREIGN KEY (sensor_id) REFERENCES iot_1.sensor (id)
);

CREATE INDEX ON iot_1.location (sensor_id);

INSERT INTO iot_1.location (sensor_id, name, latitude, longitude)
SELECT
    s.id AS sensor_id,
    'Location ' || s.id AS name,
    random() * 90 AS latitude,
    random() * 180 AS longitude
FROM
    iot_1.sensor s
ORDER BY
    s.id;

CREATE TABLE iot_1."user" (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    password VARCHAR(255),
    role VARCHAR(50)
);

INSERT INTO iot_1."user" (username, email, password, role)
SELECT
    'User' || gs AS username,
    'user' || gs || '@example.com' AS email,
    'password' || gs AS password,
    CASE
        WHEN gs % 2 = 0 THEN 'Admin'
        ELSE 'User'
    END AS role
FROM generate_series(1, 100000) AS gs;

CREATE TABLE iot_1.event (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    event_type VARCHAR(255),
    description TEXT,
    sensor_id INTEGER,
    device_id INTEGER,
    FOREIGN KEY (sensor_id) REFERENCES iot_1.sensor (id),
    FOREIGN KEY (device_id) REFERENCES iot_1.device (id)
);

INSERT INTO iot_1.event (timestamp, event_type, description, sensor_id, device_id)
SELECT
    now() - (random() * interval '365' day) AS timestamp,
    'Event' || gs AS event_type,
    'Description of event ' || gs AS description,
    s.id AS sensor_id,
    d.id AS device_id
FROM generate_series(1, 100000) AS gs
CROSS JOIN LATERAL (
    SELECT id FROM iot_1.sensor ORDER BY random() LIMIT 1
) AS s
CROSS JOIN LATERAL (
    SELECT id FROM iot_1.device ORDER BY random() LIMIT 1
) AS d;

CREATE TABLE iot_1.dashboard (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    name VARCHAR(255),
    layout JSONB,
    widgets JSONB,
    FOREIGN KEY (user_id) REFERENCES iot_1."user" (id)
);

INSERT INTO iot_1.dashboard (user_id, name, layout, widgets)
SELECT
    u.id AS user_id,
    'Dashboard ' || gs AS name,
    '{}'::jsonb AS layout,
    '{}'::jsonb AS widgets
FROM generate_series(1, 100000) AS gs
JOIN iot_1."user" u ON u.id = (random() * (SELECT max(id) FROM iot_1."user"))::integer;

CREATE TABLE iot_1.command (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    command_type VARCHAR(255),
    payload JSONB,
    sensor_id INTEGER,
    device_id INTEGER,
    FOREIGN KEY (sensor_id) REFERENCES iot_1.sensor (id),
    FOREIGN KEY (device_id) REFERENCES iot_1.device (id)
);

INSERT INTO iot_1.command (timestamp, command_type, payload, sensor_id, device_id)
SELECT
    now() - (random() * interval '365' day) AS timestamp,
    'Command' || gs AS command_type,
    '{}'::jsonb AS payload,
    s.id AS sensor_id,
    d.id AS device_id
FROM generate_series(1, 100000) AS gs
CROSS JOIN LATERAL (
    SELECT id FROM iot_1.sensor ORDER BY random() LIMIT 1
) AS s
CROSS JOIN LATERAL (
    SELECT id FROM iot_1.device ORDER BY random() LIMIT 1
) AS d;

CREATE TABLE iot_1.firmware (
    id SERIAL PRIMARY KEY,
    version VARCHAR(50) NOT NULL,
    release_date DATE,
    description TEXT
);

INSERT INTO iot_1.firmware (version, release_date, description)
SELECT
    'Version ' || gs AS version,
    current_date - (random() * interval '365' day) AS release_date,
    'Description of firmware ' || gs AS description
FROM generate_series(1, 10000) AS gs;

CREATE TABLE iot_1.sensor_data (
    id SERIAL PRIMARY KEY,
    sensor_id INTEGER NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    data JSONB,
    FOREIGN KEY (sensor_id) REFERENCES iot_1.sensor (id)
);

INSERT INTO iot_1.sensor_data (sensor_id, timestamp, data)
SELECT
    s.id AS sensor_id,
    now() - (random() * interval '365' day) AS timestamp,
    jsonb_build_object('value', random() * 100) AS data
FROM generate_series(1, 10000) AS gs
JOIN iot_1.sensor s ON s.id = (random() * (SELECT max(id) FROM iot_1.sensor))::integer;

CREATE TABLE iot_1.device_status (
    id SERIAL PRIMARY KEY,
    device_id INTEGER NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    status VARCHAR(50),
    FOREIGN KEY (device_id) REFERENCES iot_1.device (id)
);

INSERT INTO iot_1.device_status (device_id, timestamp, status)
SELECT
    d.id AS device_id,
    now() - (random() * interval '365' day) AS timestamp,
    CASE floor(random() * 3)::integer
        WHEN 0 THEN 'Online'
        WHEN 1 THEN 'Offline'
        WHEN 2 THEN 'Idle'
    END AS status
FROM generate_series(1, 10000) AS gs
JOIN iot_1.device d ON d.id = (random() * (SELECT max(id) FROM iot_1.device))::integer;

CREATE TABLE iot_1.gateway (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    ip_address INET,
    location_id INTEGER,
    FOREIGN KEY (location_id) REFERENCES iot_1.location (id)
);

INSERT INTO iot_1.gateway (name, ip_address, location_id)
SELECT
    'Gateway ' || gs AS name,
    ('192.168.0.' || (10 + (gs % 245)))::inet AS ip_address,
    l.id AS location_id
FROM generate_series(1, 100) AS gs
CROSS JOIN iot_1.location l
ORDER BY random()
LIMIT 100;

-- Use table inheritance for sensor data.
CREATE TABLE iot_1.temperature_sensor (
    threshold FLOAT NOT NULL,
    FOREIGN KEY (device_id) REFERENCES iot_1.device (id)
) INHERITS (iot_1.sensor);

DO $$
BEGIN
    FOR i IN 1..100000 LOOP
        INSERT INTO iot_1.temperature_sensor (device_id, type, name, threshold)
        SELECT
            (SELECT id FROM iot_1.device LIMIT 1),
            CASE floor(random() * 3)::integer
                WHEN 0 THEN 'temperature'::iot_1.sensor_type
                WHEN 1 THEN 'humidity'::iot_1.sensor_type
                WHEN 2 THEN 'pressure'::iot_1.sensor_type
            END,
            'Name ' || floor(random() * 100)::text,
            random() * 500;
    END LOOP;
END $$;

CREATE TABLE iot_1.humidity_sensor (
    threshold FLOAT NOT NULL,
    FOREIGN KEY (device_id) REFERENCES iot_1.device (id)
) INHERITS (iot_1.sensor);

DO $$
BEGIN
    FOR i IN 1..100000 LOOP
        INSERT INTO iot_1.humidity_sensor (device_id, type, name, threshold)
        SELECT
            (SELECT id FROM iot_1.device LIMIT 1),
            CASE floor(random() * 3)::integer
                WHEN 0 THEN 'temperature'::iot_1.sensor_type
                WHEN 1 THEN 'humidity'::iot_1.sensor_type
                WHEN 2 THEN 'pressure'::iot_1.sensor_type
            END,
            'Name ' || floor(random() * 100)::text,
            random() * 99;
    END LOOP;
END $$;

CREATE TABLE iot_1.pressure_sensor (
    unit VARCHAR(10) NOT NULL,
    FOREIGN KEY (device_id) REFERENCES iot_1.device (id)
) INHERITS (iot_1.sensor);

DO $$
BEGIN
    FOR i IN 1..100000 LOOP
        INSERT INTO iot_1.pressure_sensor (device_id, type, name, unit)
        SELECT
            (SELECT id FROM iot_1.device LIMIT 1),
            CASE floor(random() * 3)::integer
                WHEN 0 THEN 'temperature'::iot_1.sensor_type
                WHEN 1 THEN 'humidity'::iot_1.sensor_type
                WHEN 2 THEN 'pressure'::iot_1.sensor_type
            END,
            'Name ' || floor(random() * 100)::text,
            'Unit' || floor(random() * 99)::text;
    END LOOP;
END $$;

-- Function to clone the a schema.
-- This functions copies the tables, views and materialised views from source_schema
-- and duplicates into the dest_schema.
CREATE OR REPLACE FUNCTION clone_schema(source_schema text, dest_schema text)
RETURNS void AS
$BODY$
DECLARE
    objeto record;
    buffer text;
BEGIN
    EXECUTE 'CREATE SCHEMA ' || dest_schema ;
    FOR objeto IN SELECT c.relname::text, c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = source_schema LOOP
        buffer := dest_schema || '.' || objeto.relname;
        IF objeto.relkind = 'r' THEN
            EXECUTE 'CREATE TABLE ' || buffer || ' (LIKE ' || source_schema || '.' || objeto.relname || ' INCLUDING DEFAULTS)';
            EXECUTE 'INSERT INTO ' || buffer || ' (SELECT * FROM ' || source_schema || '.' || objeto.relname || ')';
        ELSIF objeto.relkind = 'v' THEN
            EXECUTE (SELECT 'CREATE OR REPLACE VIEW ' || buffer || ' AS ' || definition FROM pg_views WHERE viewname = objeto.relname AND schemaname = source_schema);
        ELSIF objeto.relkind = 'm' THEN
            EXECUTE (SELECT 'CREATE MATERIALIZED VIEW ' || buffer || ' AS ' || definition FROM pg_matviews WHERE matviewname = objeto.relname AND schemaname = source_schema);
        END IF;
    END LOOP;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;

-- Till now, the size of the database is ~10GB. Let's make it 20GB.
SELECT clone_schema('iot_1', 'iot_2');

-- RBAC scripts.
CREATE ROLE role1;
CREATE ROLE role2;

CREATE TABLE iot_1.new_table1 (
    id SERIAL PRIMARY KEY,
    device_id INTEGER NOT NULL REFERENCES iot_1.device (id),
    value FLOAT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (device_id) REFERENCES iot_1.device (id)
);

CREATE TABLE iot_1.new_table2 (
    id SERIAL PRIMARY KEY,
    sensor_id INTEGER NOT NULL REFERENCES iot_1.sensor (id),
    value FLOAT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (sensor_id) REFERENCES iot_1.sensor (id)
);

CREATE VIEW iot_1.new_view1 AS
SELECT d.id, d.name, m.value, m.timestamp
FROM iot_1.device d
JOIN iot_1.measurement m ON d.id = m.id;

CREATE VIEW iot_1.new_view2 AS
SELECT s.id, s.name, m.value, m.timestamp
FROM iot_1.sensor s
JOIN iot_1.measurement m ON s.id = m.sensor_id;

CREATE MATERIALIZED VIEW iot_1.new_mat_view1 AS
SELECT d.id, d.name, AVG(m.value) AS average_value
FROM iot_1.device d
JOIN iot_1.measurement m ON d.id = m.id
GROUP BY d.id, d.name;

CREATE MATERIALIZED VIEW iot_1.new_mat_view2 AS
SELECT s.id, s.name, COUNT(m.id) AS measurement_count
FROM iot_1.sensor s
JOIN iot_1.measurement m ON s.id = m.sensor_id
GROUP BY s.id, s.name;

-- Grant access to tables
GRANT SELECT, INSERT, UPDATE, DELETE ON iot_1.new_table1 TO role1;
GRANT SELECT, INSERT, UPDATE, DELETE ON iot_1.new_table2 TO role2;

-- Grant access to views
GRANT SELECT ON iot_1.new_view1 TO role1;
GRANT SELECT ON iot_1.new_view2 TO role2;

-- Grant access to materialized views
GRANT SELECT ON iot_1.new_mat_view1 TO role1;
GRANT SELECT ON iot_1.new_mat_view2 TO role2;

-- Make the db size to 100GB.
DO $$
BEGIN
    RAISE NOTICE 'Cloing schema to iot_3';
    PERFORM clone_schema('iot_1', 'iot_3');

    RAISE NOTICE 'Cloing schema to iot_4';
    PERFORM clone_schema('iot_1', 'iot_4');

    RAISE NOTICE 'Cloing schema to iot_5';
    PERFORM clone_schema('iot_1', 'iot_5');

    RAISE NOTICE 'Cloing schema to iot_6';
    PERFORM clone_schema('iot_1', 'iot_6');

    RAISE NOTICE 'Cloing schema to iot_7';
    PERFORM clone_schema('iot_1', 'iot_7');

    RAISE NOTICE 'Cloing schema to iot_8';
    PERFORM clone_schema('iot_1', 'iot_8');

    RAISE NOTICE 'Cloing schema to iot_9';
    PERFORM clone_schema('iot_1', 'iot_9');

    RAISE NOTICE 'Cloing schema to iot_10';
    PERFORM clone_schema('iot_1', 'iot_10');

    RAISE NOTICE 'Cloing schema to iot_11';
    PERFORM clone_schema('iot_1', 'iot_11');

    RAISE NOTICE 'Cloing schema to iot_12';
    PERFORM clone_schema('iot_1', 'iot_12');

    RAISE NOTICE 'Cloing schema to iot_13';
    PERFORM clone_schema('iot_1', 'iot_13');
END $$;
