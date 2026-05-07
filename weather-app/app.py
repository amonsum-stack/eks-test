"""
Belgrade Weather App
--------------------
Serves current weather conditions for Belgrade, Serbia.

Data flow:
  - A Kubernetes CronJob (fetcher) calls Open-Meteo every 10 minutes
    and writes the result as a ConfigMap named 'weather-data' in the
    'weather' namespace.
  - This Flask app reads that ConfigMap via the Kubernetes API
    (in-cluster config) and renders it as an HTML page.
  - If the ConfigMap doesn't exist yet, it falls back to fetching
    directly from Open-Meteo so the first load always works.

Metrics:
  - /metrics endpoint exposes Prometheus metrics via
    prometheus-flask-exporter (HTTP request counts, latency)
  - Custom gauge: belgrade_temperature_celsius (current temperature)
  - Custom gauge: belgrade_humidity_percent
  - Custom gauge: belgrade_wind_speed_ms
  - Custom gauge: belgrade_pressure_hpa
"""
# test CI/CD pipeline trigger

import json
import os
import logging
from datetime import datetime, timezone

import requests
from flask import Flask, render_template, jsonify
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import Gauge

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
metrics = PrometheusMetrics(app)
metrics.info("weather_app_info", "Belgrade Weather App", version="1.0")

# Custom gauges — updated on every page load from the latest data
TEMP_GAUGE     = Gauge("belgrade_temperature_celsius",  "Current temperature in Belgrade (°C)")
HUMIDITY_GAUGE = Gauge("belgrade_humidity_percent",     "Current humidity in Belgrade (%)")
WIND_GAUGE     = Gauge("belgrade_wind_speed_ms",        "Current wind speed in Belgrade (m/s)")
PRESSURE_GAUGE = Gauge("belgrade_pressure_hpa",         "Current atmospheric pressure in Belgrade (hPa)")
VISIBILITY_GAUGE = Gauge("belgrade_visibility_km",      "Current visibility in Belgrade (km)")

# Belgrade coordinates
LAT = 44.8176
LON = 20.4633
NAMESPACE = os.getenv("NAMESPACE", "weather")
CONFIGMAP_NAME = os.getenv("CONFIGMAP_NAME", "weather-data")

# Open-Meteo WMO weather code descriptions
WMO_CODES = {
    0: ("Clear sky", "☀️"),
    1: ("Mainly clear", "🌤️"),
    2: ("Partly cloudy", "⛅"),
    3: ("Overcast", "☁️"),
    45: ("Foggy", "🌫️"),
    48: ("Icy fog", "🌫️"),
    51: ("Light drizzle", "🌦️"),
    53: ("Drizzle", "🌦️"),
    55: ("Heavy drizzle", "🌧️"),
    61: ("Light rain", "🌧️"),
    63: ("Rain", "🌧️"),
    65: ("Heavy rain", "🌧️"),
    71: ("Light snow", "🌨️"),
    73: ("Snow", "❄️"),
    75: ("Heavy snow", "❄️"),
    77: ("Snow grains", "🌨️"),
    80: ("Light showers", "🌦️"),
    81: ("Showers", "🌧️"),
    82: ("Heavy showers", "⛈️"),
    85: ("Snow showers", "🌨️"),
    86: ("Heavy snow showers", "❄️"),
    95: ("Thunderstorm", "⛈️"),
    96: ("Thunderstorm + hail", "⛈️"),
    99: ("Thunderstorm + heavy hail", "⛈️"),
}

def fetch_from_api():
    """Fetch current weather directly from Open-Meteo API."""
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
        "source": "Open-Meteo (live fetch)",
    }

def read_from_configmap():
    """Read cached weather data from the Kubernetes ConfigMap."""
    try:
        config.load_incluster_config()
        v1 = client.CoreV1Api()
        cm = v1.read_namespaced_config_map(name=CONFIGMAP_NAME, namespace=NAMESPACE)
        data = json.loads(cm.data["weather.json"])
        data["source"] = "Open-Meteo (cached via CronJob)"
        return data
    except ApiException as e:
        if e.status == 404:
            logger.info("ConfigMap not found yet, fetching directly from API")
        else:
            logger.warning(f"ConfigMap read failed ({e.status}), falling back to API")
        return None
    except Exception as e:
        logger.warning(f"ConfigMap read error: {e}, falling back to API")
        return None

def wind_direction_label(degrees):
    """Convert wind degrees to compass label."""
    dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    idx = round(degrees / 45) % 8
    return dirs[idx]

def update_gauges(weather):
    """Update Prometheus gauges with latest weather data."""
    TEMP_GAUGE.set(weather.get("temperature", 0))
    HUMIDITY_GAUGE.set(weather.get("humidity", 0))
    WIND_GAUGE.set(weather.get("wind_speed", 0))
    PRESSURE_GAUGE.set(weather.get("pressure", 0))
    VISIBILITY_GAUGE.set(weather.get("visibility", 0))

@app.route("/")
def index():
    weather = read_from_configmap()
    if weather is None:
        weather = fetch_from_api()
    weather["wind_label"] = wind_direction_label(weather.get("wind_direction", 0))
    update_gauges(weather)
    return render_template("index.html", weather=weather)

@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200

@app.route("/api/weather")
def api_weather():
    """Raw JSON endpoint — useful for debugging."""
    weather = read_from_configmap()
    if weather is None:
        weather = fetch_from_api()
    return jsonify(weather)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
