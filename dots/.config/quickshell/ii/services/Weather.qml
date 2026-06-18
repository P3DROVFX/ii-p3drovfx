pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtPositioning

import qs.modules.common

Singleton {
    id: root

    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    
    // For backward compatibility and UI settings
    property bool gpsActive: Config.options.bar.weather.enableGPS
    readonly property string city: Config.options.bar.weather.city

    onUseUSCSChanged: getData(true)
    onCityChanged: getData(true)
    onGpsActiveChanged: {
        if (root.gpsActive) {
            positionSource.start();
        } else {
            positionSource.stop();
            getData(true);
        }
    }
    onFetchIntervalChanged: {
        timer.restart();
    }

    property var location: ({
        valid: false,
        lat: 0,
        lon: 0,
        long: 0,
        city: ""
    })

    property var data: ({
        uv: 0,
        humidity: "0%",
        sunrise: "00:00",
        sunset: "00:00",
        windDir: "N",
        wCode: 113,
        wDesc: "",
        city: "City",
        wind: "0 km/h",
        precip: "0 mm",
        visib: "0 km",
        press: "0 hPa",
        temp: "0°C",
        tempFeelsLike: "0°C",
        lastRefresh: "00:00",
    })

    // Forecast data properties consumed by popup/cards
    property var forecastData: []
    property var hourlyData: []
    property bool forecastLoading: true

    function wmoToWwo(wmo) {
        if (wmo === 0 || wmo === 1) return 113; // Clear
        if (wmo === 2) return 116; // Partly Cloudy
        if (wmo === 3) return 122; // Overcast
        if (wmo === 45 || wmo === 48) return 248; // Fog
        if (wmo === 51 || wmo === 53 || wmo === 55) return 266; // Drizzle
        if (wmo === 56 || wmo === 57) return 284; // Freezing Drizzle
        if (wmo === 61 || wmo === 63 || wmo === 65) return 296; // Rain
        if (wmo === 66 || wmo === 67) return 311; // Freezing Rain
        if (wmo === 71 || wmo === 73 || wmo === 75 || wmo === 77) return 332; // Snow
        if (wmo === 80 || wmo === 81 || wmo === 82) return 353; // Rain Showers
        if (wmo === 85 || wmo === 86) return 368; // Snow Showers
        if (wmo === 95) return 386; // Thunderstorm
        if (wmo === 96 || wmo === 99) return 389; // Thunderstorm with hail
        return 113;
    }

    function degreesToCompass(deg) {
        const val = Math.floor((deg / 22.5) + 0.5);
        const arr = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        return arr[(val % 16)];
    }

    function formatTime(isoStr) {
        if (!isoStr) return "00:00";
        const parts = isoStr.split("T");
        if (parts.length < 2) return isoStr;
        let timeStr = parts[1];
        
        let uses12h = Config.options.time.format.toLowerCase().includes("a");
        if (uses12h) {
            let t = timeStr.split(":");
            if (t.length >= 2) {
                let h = parseInt(t[0]);
                let ampm = h >= 12 ? "PM" : "AM";
                h = h % 12;
                if (h === 0) h = 12;
                return h + ":" + t[1] + " " + ampm;
            }
        }
        return timeStr;
    }

    function getWeatherDescription(code) {
        const codeInt = parseInt(code);
        const descriptions = {
            "113": Translation.tr("Clear"),
            "116": Translation.tr("Partly Cloudy"),
            "119": Translation.tr("Cloudy"),
            "122": Translation.tr("Overcast"),
            "143": Translation.tr("Mist"),
            "176": Translation.tr("Patchy Rain"),
            "200": Translation.tr("Thundery Outbreaks"),
            "248": Translation.tr("Fog"),
            "266": Translation.tr("Light Drizzle"),
            "296": Translation.tr("Light Rain"),
            "302": Translation.tr("Moderate Rain"),
            "308": Translation.tr("Heavy Rain"),
            "326": Translation.tr("Light Snow"),
            "332": Translation.tr("Moderate Snow"),
            "338": Translation.tr("Heavy Snow"),
            "353": Translation.tr("Light Rain Shower"),
            "389": Translation.tr("Heavy Rain with Thunder")
        };

        if (descriptions[code]) {
            return descriptions[code];
        }

        let keys = Object.keys(descriptions).map(Number).sort((a, b) => a - b);
        let bestMatch = keys[0];

        for (let i = 0; i < keys.length; i++) {
            if (codeInt >= keys[i]) {
                bestMatch = keys[i];
            } else {
                break;
            }
        }

        return descriptions[bestMatch.toString()] || Translation.tr("Unknown");
    }

    function refineData(wData, cityName) {
        let temp = {};
        const current = wData.current;
        const daily = wData.daily;
        const hourly = wData.hourly;

        temp.uv = current.uv_index;
        temp.humidity = current.relative_humidity_2m + "%";
        temp.sunrise = formatTime(daily.sunrise[0]);
        temp.sunset = formatTime(daily.sunset[0]);
        temp.windDir = degreesToCompass(current.wind_direction_10m);
        temp.wCode = wmoToWwo(current.weather_code);
        temp.wDesc = getWeatherDescription(temp.wCode);
        temp.city = cityName;
        
        if (root.useUSCS) {
            temp.wind = Math.round(current.wind_speed_10m * 0.621371) + " mph";
            temp.precip = (current.precipitation * 0.0393701).toFixed(2) + " in";
            temp.visib = (current.visibility / 1609.34).toFixed(1) + " mi";
            temp.press = Math.round(current.pressure_msl) + " hPa"; 
            temp.temp = Math.round(current.temperature_2m * 9 / 5 + 32) + "°F";
            temp.tempFeelsLike = Math.round(current.apparent_temperature * 9 / 5 + 32) + "°F";
        } else {
            temp.wind = Math.round(current.wind_speed_10m) + " km/h";
            temp.precip = current.precipitation.toFixed(1) + " mm";
            temp.visib = (current.visibility / 1000).toFixed(1) + " km";
            temp.press = Math.round(current.pressure_msl) + " hPa";
            temp.temp = Math.round(current.temperature_2m) + "°C";
            temp.tempFeelsLike = Math.round(current.apparent_temperature) + "°C";
        }
        
        temp.lastRefresh = DateTime.time + " • " + DateTime.date;
        root.data = temp;
        console.info(`[WeatherService] Successfully fetched weather for ${cityName}: ${temp.temp}, ${temp.wDesc}`);

        // Parse forecastData (daily)
        let forecastList = [];
        if (daily && daily.time) {
            for (let i = 0; i < daily.time.length; i++) {
                let maxC = daily.temperature_2m_max[i];
                let minC = daily.temperature_2m_min[i];
                let maxF = maxC * 9 / 5 + 32;
                let minF = minC * 9 / 5 + 32;
                forecastList.push({
                    date: daily.time[i],
                    maxC: Math.round(maxC),
                    minC: Math.round(minC),
                    maxF: Math.round(maxF),
                    minF: Math.round(minF),
                    code: wmoToWwo(daily.weather_code[i])
                });
            }
        }
        root.forecastData = forecastList;

        // Parse hourlyData (3-hour slots)
        let hourlyList = [];
        if (hourly && hourly.time) {
            // Pick hourly slots every 3 hours for up to 48 hours (current day and next day)
            for (let i = 0; i < Math.min(hourly.time.length, 48); i++) {
                const hourOfDay = i % 24;
                if (hourOfDay % 3 === 0) {
                    let tempC = hourly.temperature_2m[i];
                    let tempF = tempC * 9 / 5 + 32;
                    hourlyList.push({
                        time: (hourOfDay * 100).toString(),
                        tempC: Math.round(tempC).toString(),
                        tempF: Math.round(tempF).toString(),
                        code: wmoToWwo(hourly.weather_code[i]).toString()
                    });
                }
            }
        }
        root.hourlyData = hourlyList;
        root.forecastLoading = false;
    }

    property double lastFetchTimestamp: 0

    function getData(force = false) {
        const now = Date.now();
        if (!force && (now - lastFetchTimestamp < 60000)) { // 1 minute rate limit
            return;
        }
        lastFetchTimestamp = now;

        if (root.gpsActive && root.location.valid) {
            // If GPS is active and we have a valid position, fetch weather for it directly
            fetchWeather(root.location.lat, root.location.lon, root.location.city || "Current Location");
        } else if (root.city !== "" && !root.gpsActive) {
            // If manual city is set and GPS is off, use geocoding
            fetchCoordinates(root.city);
        } else {
            // Default to ip-api for automatic location
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        try {
                            const loc = JSON.parse(xhr.responseText);
                            if (loc.status === "success") {
                                root.location.lat = loc.lat;
                                root.location.lon = loc.lon;
                                root.location.long = loc.lon;
                                root.location.city = loc.city;
                                root.location.valid = true;
                                fetchWeather(loc.lat, loc.lon, loc.city);
                            } else {
                                console.error("[WeatherService] ip-api failed:", loc.message);
                            }
                        } catch (e) {
                            console.error("[WeatherService] Failed to parse location:", e);
                        }
                    }
                }
            };
            xhr.open("GET", "http://ip-api.com/json/");
            xhr.send();
        }
    }

    function fetchCoordinates(cityName) {
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(cityName)}&count=1&language=en&format=json`;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        const res = JSON.parse(xhr.responseText);
                        if (res.results && res.results.length > 0) {
                            const loc = res.results[0];
                            root.location.lat = loc.latitude;
                            root.location.lon = loc.longitude;
                            root.location.long = loc.longitude;
                            root.location.city = loc.name;
                            root.location.valid = true;
                            fetchWeather(loc.latitude, loc.longitude, loc.name);
                        } else {
                            console.error("[WeatherService] Geocoding failed for:", cityName);
                        }
                    } catch (e) {
                        console.error("[WeatherService] Failed to parse geocoding:", e);
                    }
                }
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function fetchWeather(lat, lon, cityName) {
        root.forecastLoading = true;
        const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,uv_index,visibility&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code&hourly=temperature_2m,weather_code&timezone=auto`;
        
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        const weather = JSON.parse(xhr.responseText);
                        root.refineData(weather, cityName);
                    } catch (e) {
                        console.error("[WeatherService] Failed to parse weather:", e);
                        root.forecastLoading = false;
                    }
                } else {
                    console.error("[WeatherService] Weather API error:", xhr.status);
                    root.forecastLoading = false;
                }
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    Component.onCompleted: {
        if (root.gpsActive) {
            console.info("[WeatherService] Starting the GPS service.");
            positionSource.start();
            fallbackTimer.start();
        } else {
            root.getData(true);
        }
    }

    Timer {
        id: fallbackTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (!root.location.valid) {
                console.info("[WeatherService] GPS timed out or invalid. Falling back to IP-based location.");
                positionSource.stop();
                root.gpsActive = false;
                root.getData(true);
            }
        }
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                fallbackTimer.stop();
                root.location.lat = position.coordinate.latitude;
                root.location.lon = position.coordinate.longitude;
                root.location.long = position.coordinate.longitude;
                root.location.valid = true;
                root.getData();
            } else {
                root.gpsActive = root.location.valid ? true : false;
                console.error("[WeatherService] Failed to get the GPS location.");
            }
        }

        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop();
                fallbackTimer.stop();
                root.location.valid = false;
                root.gpsActive = false;
                Quickshell.execDetached(["notify-send", Translation.tr("Weather Service"), Translation.tr("Cannot find a GPS service. Using the fallback method instead."), "-a", "Shell"]);
                console.error("[WeatherService] Could not aquire a valid backend plugin.");
                root.getData(true);
            }
        }
    }

    Timer {
        id: timer
        running: Config.options.bar.weather.enable
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: true
        onTriggered: root.getData()
    }
}
