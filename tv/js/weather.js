/* Weather and city search, using the same Open-Meteo endpoints as the Flutter
   launcher. No default temperature and no guessed city: if no location has
   been set, the TV says so instead of displaying an invented reading. */
(function () {
  'use strict';

  var CACHE_KEY = 'snlauncher.tv.weather.v1';
  var REFRESH_MS = 60 * 60 * 1000;
  var listeners = [];
  var current = null;
  var location = null;
  var loading = false;
  var error = '';
  var status = 'idle';
  var timer = null;
  var lastAttempt = 0;
  var inFlight = false;

  var LABELS = {
    clear: 'Clear',
    partlyCloudy: 'Partly cloudy',
    cloudy: 'Cloudy',
    fog: 'Fog',
    drizzle: 'Drizzle',
    rain: 'Rain',
    snow: 'Snow',
    thunder: 'Thunderstorm',
    unknown: 'Unknown'
  };

  var CLAUSES = {
    clear: "it's clear",
    partlyCloudy: "it's a bit cloudy",
    cloudy: "it's overcast",
    fog: "it's foggy",
    drizzle: "it's drizzling",
    rain: "it's raining",
    snow: "it's snowing",
    thunder: "there's a thunderstorm",
    unknown: 'the sky is doing something unclear'
  };

  var SKY = {
    clear: ['#4FA3E3', '#8FCBF0', '#DCEFFA'],
    partlyCloudy: ['#6FA8D6', '#A9C6DF', '#E3E9EE'],
    cloudy: ['#7C8A99', '#A8B4C0', '#D2D9DF'],
    fog: ['#9AA6AC', '#C2CACD', '#E6EAEA'],
    drizzle: ['#5E7284', '#8A9DAB', '#C3CFD7'],
    rain: ['#3E5265', '#63788A', '#9DB0BD'],
    snow: ['#6E7F92', '#A3B3C4', '#E6EEF5'],
    thunder: ['#1E2733', '#3A4756', '#6B7A8B'],
    unknown: ['#4A5568', '#7C8798', '#BFC7D1']
  };

  function emit() {
    for (var i = 0; i < listeners.length; i++) {
      try { listeners[i](); } catch (err) { /* never break rendering */ }
    }
  }

  function decodeCondition(code) {
    if (code === 0) return 'clear';
    if (code === 1 || code === 2) return 'partlyCloudy';
    if (code === 3) return 'cloudy';
    if (code === 45 || code === 48) return 'fog';
    if (code === 51 || code === 53 || code === 55 || code === 56 || code === 57) return 'drizzle';
    if (code === 61 || code === 63 || code === 65 || code === 66 || code === 67 ||
        code === 80 || code === 81 || code === 82) return 'rain';
    if (code === 71 || code === 73 || code === 75 || code === 77 || code === 85 || code === 86) return 'snow';
    if (code === 95 || code === 96 || code === 99) return 'thunder';
    return 'unknown';
  }

  function round1(value) {
    if (typeof value !== 'number' || !isFinite(value)) return null;
    return Math.round(value * 10) / 10;
  }

  function locKey(loc) {
    if (!loc) return '';
    return Number(loc.lat).toFixed(3) + ',' + Number(loc.lon).toFixed(3);
  }

  function readCache(loc) {
    try {
      var raw = window.localStorage.getItem(CACHE_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (!parsed || parsed.key !== locKey(loc) || !parsed.reading) return null;
      return parsed.reading;
    } catch (err) {
      return null;
    }
  }

  function writeCache(loc, reading) {
    try {
      window.localStorage.setItem(CACHE_KEY, JSON.stringify({
        key: locKey(loc),
        reading: reading
      }));
    } catch (err) { /* cache is an optimisation, not a requirement */ }
  }

  function parseResponse(json, loc) {
    if (!json || !json.current) return null;
    var cur = json.current;
    var daily = json.daily || {};
    var temp = Number(cur.temperature_2m);
    if (!isFinite(temp)) return null;
    function first(list) {
      return list && list.length && typeof list[0] === 'number' ? list[0] : null;
    }
    return {
      condition: decodeCondition(Number(cur.weather_code)),
      temperatureC: temp,
      feelsLikeC: round1(Number(cur.apparent_temperature)),
      humidity: typeof cur.relative_humidity_2m === 'number' ? Math.round(cur.relative_humidity_2m) : null,
      highC: round1(first(daily.temperature_2m_max)),
      lowC: round1(first(daily.temperature_2m_min)),
      fetchedAt: new Date().toISOString(),
      localTime: typeof cur.time === 'string' ? cur.time : '',
      place: loc.name || '',
      lat: Number(loc.lat),
      lon: Number(loc.lon),
      timezone: json.timezone || ''
    };
  }

  function fetchWeather(loc, quiet) {
    if (!loc || inFlight) return;
    inFlight = true;
    loading = true;
    if (!quiet) {
      status = current ? 'stale' : 'loading';
      emit();
    }
    lastAttempt = Date.now();

    var url = 'https://api.open-meteo.com/v1/forecast' +
      '?latitude=' + encodeURIComponent(Number(loc.lat).toFixed(4)) +
      '&longitude=' + encodeURIComponent(Number(loc.lon).toFixed(4)) +
      '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code' +
      '&daily=temperature_2m_max,temperature_2m_min' +
      '&temperature_unit=celsius&timezone=auto&forecast_days=1';

    SN.net.getJSON(url, 9000, function (err, data) {
      inFlight = false;
      loading = false;
      if (err) {
        error = err.message || 'Could not reach Open-Meteo';
        status = current ? 'stale' : 'error';
        emit();
        return;
      }
      var reading = parseResponse(data, loc);
      if (!reading) {
        error = 'Open-Meteo sent a reading without a temperature';
        status = current ? 'stale' : 'error';
        emit();
        return;
      }
      // A location change while the request was in flight wins over this answer.
      if (locKey(loc) !== locKey(location)) return;
      current = reading;
      error = '';
      status = 'ready';
      writeCache(loc, reading);
      emit();
    });
  }

  function schedule() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    if (!location) return;
    timer = setInterval(function () {
      fetchWeather(location, true);
    }, REFRESH_MS);
  }

  function configure(loc) {
    loc = SN.Store.validLocation(loc);
    var changed = locKey(loc) !== locKey(location);
    location = loc;
    if (!loc) {
      current = null;
      error = '';
      status = 'idle';
      if (timer) clearInterval(timer);
      timer = null;
      emit();
      return;
    }
    if (changed) {
      current = readCache(loc);
      error = '';
      status = current ? 'ready' : 'loading';
      emit();
      fetchWeather(loc, false);
    }
    schedule();
  }

  function refresh(force) {
    if (!location) return;
    if (!force && loading) return;
    if (!force && current && Date.now() - lastAttempt < 60 * 1000) return;
    fetchWeather(location, false);
  }

  function geocode(query, done) {
    var q = String(query || '').trim();
    if (!q) {
      done({ message: 'Type a city name first.' }, []);
      return;
    }
    var url = 'https://geocoding-api.open-meteo.com/v1/search' +
      '?name=' + encodeURIComponent(q) + '&count=6&language=en&format=json';
    SN.net.getJSON(url, 9000, function (err, data) {
      if (err) {
        done({ message: err.message || 'City search failed' }, []);
        return;
      }
      var rows = data && data.results;
      if (!rows || !rows.length) {
        done(null, []);
        return;
      }
      var out = [];
      for (var i = 0; i < rows.length; i++) {
        var r = rows[i];
        if (typeof r.latitude !== 'number' || typeof r.longitude !== 'number') continue;
        var extra = [r.admin1, r.country].filter(function (v) { return !!v; }).join(', ');
        out.push({
          lat: r.latitude,
          lon: r.longitude,
          name: r.name + (extra ? ', ' + extra : ''),
          shortName: r.name
        });
      }
      done(null, out);
    });
  }

  function sentence(condition, hour) {
    var part;
    if (hour >= 21 || hour < 5) part = 'tonight';
    else if (hour < 12) part = 'this morning';
    else if (hour < 18) part = 'this afternoon';
    else part = 'this evening';
    var clause = CLAUSES[condition] || CLAUSES.unknown;
    return clause.charAt(0).toUpperCase() + clause.slice(1) + ' ' + part + '.';
  }

  function sky(condition) {
    return SKY[condition] || SKY.unknown;
  }

  function inkFor(condition) {
    var colors = sky(condition);
    var r = parseInt(colors[0].slice(1, 3), 16) / 255;
    var g = parseInt(colors[0].slice(3, 5), 16) / 255;
    var b = parseInt(colors[0].slice(5, 7), 16) / 255;
    var lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return lum > 0.45 ? 'dark-ink' : 'light-ink';
  }

  SN.Weather = {
    labels: LABELS,
    configure: configure,
    refresh: refresh,
    geocode: geocode,
    sentence: sentence,
    sky: sky,
    inkFor: inkFor,
    onChange: function (fn) { if (typeof fn === 'function') listeners.push(fn); },
    current: function () { return current; },
    location: function () { return location; },
    loading: function () { return loading; },
    error: function () { return error; },
    status: function () { return status; },
    lastAttempt: function () { return lastAttempt; }
  };
})();
