#!/usr/bin/env python3

from pyquery import PyQuery
import json
import sys
import random
import os
import time

location_id = "f370fc9f1e5d07401a72fab32be4e1abe8f8f9df412cbaef3110e44cbf45cc56"
unit = "metric"
forecast_type = "Daily"

CACHE_FILE = ".cache/weather.json"
CACHE_MAX_AGE = 1800  # 30 minutes

weather_icons = {
    "haze": "󰖞",
    "clearnight": "󰖔",
    "cloudyfoggyday": "",
    "cloudyfoggynight": "",
    "rainyday": "",
    "rainynight": "",
    "snowyicyday": "",
    "snowyicynight": "",
    "severe": "󰙾",
    "default": "",
}

def write_output(data):
    with open(CACHE_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    print(json.dumps(data, ensure_ascii=False))


def clean_temp(t):
    return t.replace("°", "").strip() if t else "–"


def get_cached():
    if os.path.exists(CACHE_FILE):
        age = time.time() - os.path.getmtime(CACHE_FILE)
        if age < CACHE_MAX_AGE:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    return None


def random_weather():
    fake_conditions = ["Clear", "Cloudy", "Haze", "Rain", "Storm", "Fog", "Windy"]
    temp = str(random.randint(20, 34))
    status = random.choice(fake_conditions)
    icon = weather_icons.get(status.lower(), weather_icons["default"])

    return {
        "text": temp,
        "alt": status,
        # "tooltip": f"<big>{icon}</big>\n<big>{status}</big>\n<small>Fallback weather</small>",
        "class": "fallback",
    }


_l = "en-IN" if unit == "metric" else "en-US"
url = f"https://weather.com/{_l}/weather/today/l/{location_id}"

try:
    html = PyQuery(url=url, headers={"User-Agent": "curl/7.68.0"})

    temp_raw = html("span[data-testid='TemperatureValue']").eq(0).text()
    temp = clean_temp(temp_raw) or "–"

    status = html("div[data-testid='wxPhrase']").text()
    status = status[:16] + ".." if len(status) > 17 else status

    icon = weather_icons.get(status.lower(), weather_icons["default"])

    temp_feel = clean_temp(
        html("div[data-testid='FeelsLikeSection'] span[data-testid='TemperatureValue']").text()
    )

    temp_max = clean_temp(
        html("div[data-testid='wxData'] span[data-testid='TemperatureValue']").eq(0).text()
    )
    temp_min = clean_temp(
        html("div[data-testid='wxData'] span[data-testid='TemperatureValue']").eq(1).text()
    )

    wind = html("span[data-testid='Wind']").text()
    wind_speed = wind.split()[-2] if wind and ("mph" in wind or "km/h" in wind) else "–"

    humidity = html("span[data-testid='PercentageValue']").eq(0).text() or "–"

    vis = html("span[data-testid='VisibilityValue']").text()
    visibility = vis.split()[0] if vis else "–"

    aqi = html("text[data-testid='DonutChartValue']").text() or "–"

    # tooltip = (
    #     f"<span size='xx-large'>{temp}°</span>\n"
    #     f"<big>{icon}</big>\n"
    #     f"<big>{status}</big>\n"
    #     f"<small>Feels like {temp_feel}°C</small>\n\n"
    #     f"<big> {temp_min}°   {temp_max}°</big>\n"
    #     f"風 {wind_speed}    {humidity}\n"
    #     f" {visibility}   AQI {aqi}"
    # )

    out = {
        "text": temp,   
        "alt": status,
        "class": "live",
    }

    write_output(out)

except Exception:
    # 🔹 try cache first
    cached = get_cached()
    if cached:
        cached["class"] = "cache"
        write_output(cached)
    else:
        # 🔹 fallback to random
        fallback = random_weather()
        write_output(fallback)