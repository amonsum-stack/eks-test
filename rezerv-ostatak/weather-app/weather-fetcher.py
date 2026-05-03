"""
weather-fetcher.py
------------------
Runs inside the Kubernetes CronJob every 10 minutes.
Fetches current weather from Open-Meteo and writes it
to a ConfigMap named 'weather-data' in the 'weather' namespace.
"""

import json
import os
import sys
import logging
from datetime import datetime, timezone

import requests
from kubernetes import client, config
from kubernetes.client.rest import ApiException

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

LAT = 44.8176
LON = 20.4633
NAMESPACE = os.getenv("NAMESPACE", "weather")
CONFIGMAP_NAME = os.getenv("CONFIGMAP_NAME", "weather-data")

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
        "temperature": round(c["temperature_2m"], 1),
        "feels_like": round(c["apparent_temperature"], 1),
        "humidity": c["relative_humidity_2m"],
        "pressure": round(c["surface_pressure"], 1),
        "wind_speed": round(c["wind_speed_10m"], 1),
        "wind_direction": c["wind_direction_10m"],
        "precipitation": c.get("precipitation", 0),
        "visibility": round(c.get("visibility", 0) / 1000, 1),
        "description": description,
        "emoji": emoji,
        "fetched_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
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

if __name__ == "__main__":
    try:
        logger.info("Fetching weather data from Open-Meteo...")
        data = fetch_weather()
        logger.info(f"Got: {data['temperature']}°C, {data['description']}")
        write_configmap(data)
        logger.info("Done.")
    except Exception as e:
        logger.error(f"Failed: {e}")
        sys.exit(1)
