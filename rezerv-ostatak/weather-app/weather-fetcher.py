"""
weather-fetcher.py
------------------
Runs inside the Kubernetes CronJob every 10 minutes.

Does three things:
  1. Fetches current weather from Open-Meteo
  2. Writes latest reading to the ConfigMap (for the Flask UI)
  3. Writes the reading to RDS postgres (weather_readings table)

RDS credentials are read from environment variables injected
via the 'postgres-credentials' Kubernetes Secret.
"""

import json
import os
import sys
import logging
from datetime import datetime, timezone

import requests
import psycopg2
from kubernetes import client, config
from kubernetes.client.rest import ApiException

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

LAT = 44.8176
LON = 20.4633
NAMESPACE       = os.getenv("NAMESPACE", "weather")
CONFIGMAP_NAME  = os.getenv("CONFIGMAP_NAME", "weather-data")

# RDS — injected from postgres-credentials secret
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")

WMO_CODES = {
    0: ("Clear sky", "☀️"), 1: ("Mainly clear", "🌤️"), 2: ("Partly cloudy", "⛅"),
    3: ("Overcast", "☁️"), 45: ("Foggy", "🌫️"), 48: ("Icy fog", "🌫️"),
    51: ("Light drizzle", "🌦️"), 53: ("Drizzle", "🌦️"), 55: ("Heavy drizzle", "🌧️"),
    61: ("Light rain", "🌧️"), 63: ("Rain", "🌧️"), 65: ("Heavy rain", "🌧️"),
    71: ("Light snow", "🌨️"), 73: ("Snow", "❄️"), 75: ("Heavy snow", "❄️"),
    77: ("Snow grains", "🌨️"), 80: ("Light showers", "🌦️"), 81: ("Showers", "🌧️"),
    82: ("Heavy showers", "⛈️"), 85: ("Snow showers", "🌨️"), 86: ("Heavy snow showers", "❄️"),
    95: ("Thunderstorm", "⛈️"), 96: ("Thunderstorm + hail", "⛈️"), 99: ("Thunderstorm + heavy hail", "⛈️"),
}

def fetch_weather():
    url = (
        "https://api.open-meteo.com/v1/forecast"
        f"?latitude={LAT}&longitude={LON}"
        "&current=temperature_2m,relative_humidity_2m,apparent_temperature,"
        "weather_code,surface_pressure,wind_speed_10m,wind_direction_10m,"
        "precipitation,visibility"
        "&wind_speed_unit=ms"
        "&timezone=Europe/Belgrade"
    )
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    raw = resp.json()
    c = raw["current"]

    wmo = c.get("weather_code", 0)
    description, emoji = WMO_CODES.get(wmo, ("Unknown", "🌡️"))

    return {
        "temperature":    round(c["temperature_2m"], 1),
        "feels_like":     round(c["apparent_temperature"], 1),
        "humidity":       c["relative_humidity_2m"],
        "pressure":       round(c["surface_pressure"], 1),
        "wind_speed":     round(c["wind_speed_10m"], 1),
        "wind_direction": c["wind_direction_10m"],
        "precipitation":  round(c.get("precipitation", 0), 1),
        "visibility":     round(c.get("visibility", 0) / 1000, 1),
        "description":    description,
        "emoji":          emoji,
        "fetched_at":     datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    }

def write_configmap(data):
    config.load_incluster_config()
    v1 = client.CoreV1Api()

    cm_body = client.V1ConfigMap(
        metadata=client.V1ObjectMeta(
            name=CONFIGMAP_NAME,
            namespace=NAMESPACE,
            labels={"app": "weather-fetcher"},
        ),
        data={"weather.json": json.dumps(data)},
    )

    try:
        v1.read_namespaced_config_map(name=CONFIGMAP_NAME, namespace=NAMESPACE)
        v1.replace_namespaced_config_map(name=CONFIGMAP_NAME, namespace=NAMESPACE, body=cm_body)
        logger.info("ConfigMap updated successfully")
    except ApiException as e:
        if e.status == 404:
            v1.create_namespaced_config_map(namespace=NAMESPACE, body=cm_body)
            logger.info("ConfigMap created successfully")
        else:
            raise

def write_to_rds(data):
    """Insert one weather reading row into the weather_readings table."""
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASS,
        connect_timeout=10,
        sslmode="require"
    )
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO weather_readings (
                        recorded_at, temperature, feels_like, humidity,
                        pressure, wind_speed, wind_direction,
                        precipitation, visibility, description
                    ) VALUES (
                        NOW() AT TIME ZONE 'UTC',
                        %(temperature)s, %(feels_like)s, %(humidity)s,
                        %(pressure)s, %(wind_speed)s, %(wind_direction)s,
                        %(precipitation)s, %(visibility)s, %(description)s
                    )
                """, data)
        logger.info("Reading written to RDS successfully")
    finally:
        conn.close()

if __name__ == "__main__":
    errors = []

    try:
        logger.info("Fetching weather data from Open-Meteo...")
        data = fetch_weather()
        logger.info(f"Got: {data['temperature']}°C, {data['description']}")
    except Exception as e:
        logger.error(f"Fetch failed: {e}")
        sys.exit(1)

    # Write ConfigMap — non-fatal if it fails
    try:
        write_configmap(data)
    except Exception as e:
        logger.error(f"ConfigMap write failed: {e}")
        errors.append("configmap")

    # Write to RDS — non-fatal if RDS is unreachable
    try:
        write_to_rds(data)
    except Exception as e:
        logger.error(f"RDS write failed: {e}")
        errors.append("rds")

    if errors:
        logger.warning(f"Completed with errors in: {errors}")
        sys.exit(1)
    else:
        logger.info("Done — ConfigMap and RDS updated successfully.")
