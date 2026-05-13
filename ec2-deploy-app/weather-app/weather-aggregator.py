"""
weather-aggregator.py
---------------------
Runs inside a Kubernetes CronJob at the top of every hour (:55 each hour,
so it captures the full previous hour's readings).

Reads all weather_readings rows from the past hour and writes one
summary row to weather_hourly_stats with averages for all fields.

RDS credentials are injected via the 'postgres-credentials' Secret.
"""

import os
import sys
import logging
from datetime import datetime, timezone

import psycopg2

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")

def get_connection():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASS,
        connect_timeout=10,
        sslmode="require"
    )

def aggregate():
    conn = get_connection()
    try:
        with conn:
            with conn.cursor() as cur:

                # Calculate averages for the previous full hour
                cur.execute("""
                    SELECT
                        DATE_TRUNC('hour', NOW() AT TIME ZONE 'UTC' - INTERVAL '1 hour') AS hour_start,
                        ROUND(AVG(temperature)::numeric, 2)    AS avg_temperature,
                        ROUND(AVG(feels_like)::numeric, 2)     AS avg_feels_like,
                        ROUND(AVG(humidity)::numeric, 2)       AS avg_humidity,
                        ROUND(AVG(pressure)::numeric, 2)       AS avg_pressure,
                        ROUND(AVG(wind_speed)::numeric, 2)     AS avg_wind_speed,
                        ROUND(AVG(wind_direction)::numeric, 1) AS avg_wind_direction,
                        ROUND(SUM(precipitation)::numeric, 2)  AS total_precipitation,
                        ROUND(AVG(visibility)::numeric, 2)     AS avg_visibility,
                        COUNT(*)                               AS reading_count
                    FROM weather_readings
                    WHERE recorded_at >= DATE_TRUNC('hour', NOW() AT TIME ZONE 'UTC' - INTERVAL '1 hour')
                      AND recorded_at <  DATE_TRUNC('hour', NOW() AT TIME ZONE 'UTC')
                """)

                row = cur.fetchone()

                if row is None or row[9] == 0:
                    logger.warning("No readings found for the previous hour — skipping aggregation.")
                    return

                (hour_start, avg_temp, avg_feels, avg_humidity, avg_pressure,
                 avg_wind_speed, avg_wind_dir, total_precip, avg_visibility,
                 reading_count) = row

                logger.info(
                    f"Aggregating hour {hour_start} — "
                    f"{reading_count} readings, avg temp: {avg_temp}°C"
                )

                # Upsert — safe to re-run if CronJob fires twice
                cur.execute("""
                    INSERT INTO weather_hourly_stats (
                        hour_start, avg_temperature, avg_feels_like,
                        avg_humidity, avg_pressure, avg_wind_speed,
                        avg_wind_direction, total_precipitation,
                        avg_visibility, reading_count
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                    )
                    ON CONFLICT (hour_start) DO UPDATE SET
                        avg_temperature   = EXCLUDED.avg_temperature,
                        avg_feels_like    = EXCLUDED.avg_feels_like,
                        avg_humidity      = EXCLUDED.avg_humidity,
                        avg_pressure      = EXCLUDED.avg_pressure,
                        avg_wind_speed    = EXCLUDED.avg_wind_speed,
                        avg_wind_direction= EXCLUDED.avg_wind_direction,
                        total_precipitation = EXCLUDED.total_precipitation,
                        avg_visibility    = EXCLUDED.avg_visibility,
                        reading_count     = EXCLUDED.reading_count,
                        updated_at        = NOW() AT TIME ZONE 'UTC'
                """, (
                    hour_start, avg_temp, avg_feels, avg_humidity,
                    avg_pressure, avg_wind_speed, avg_wind_dir,
                    total_precip, avg_visibility, reading_count
                ))

        logger.info("Hourly stats written successfully.")

    finally:
        conn.close()

if __name__ == "__main__":
    try:
        aggregate()
    except Exception as e:
        logger.error(f"Aggregation failed: {e}")
        sys.exit(1)
