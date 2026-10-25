/* Persistent TV settings. localStorage is the only store a Tizen web app
   reliably has without a native plugin; if it is unavailable we keep the
   session in memory and say so in Settings instead of pretending to save. */
(function () {
  'use strict';

  var SN = window.SN = window.SN || {};

  var KEY = 'snlauncher.tv.settings.v1';
  var DEFAULTS = {
    theme: 'night',
    use24h: true,
    location: null,
    ncsBaseUrl: 'http://192.168.1.123:8737'
  };
  var THEMES = ['night', 'day', 'afternoon', 'white'];
  var listeners = [];
  var storageOk = true;
  var state = copy(DEFAULTS);

  function copy(v) {
    return JSON.parse(JSON.stringify(v));
  }

  function validLocation(loc) {
    if (!loc || typeof loc !== 'object') return null;
    var lat = Number(loc.lat);
    var lon = Number(loc.lon);
    if (!isFinite(lat) || !isFinite(lon)) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return {
      lat: lat,
      lon: lon,
      name: typeof loc.name === 'string' ? loc.name.slice(0, 120) : '',
      source: 'manual'
    };
  }

  function normalize(raw) {
    var next = copy(DEFAULTS);
    if (!raw || typeof raw !== 'object') return next;
    if (THEMES.indexOf(raw.theme) >= 0) next.theme = raw.theme;
    next.use24h = raw.use24h !== false;
    next.location = validLocation(raw.location);
    var url = typeof raw.ncsBaseUrl === 'string' ? raw.ncsBaseUrl.trim() : '';
    if (url) next.ncsBaseUrl = url.slice(0, 300);
    return next;
  }

  function load() {
    try {
      var raw = window.localStorage.getItem(KEY);
      if (raw) state = normalize(JSON.parse(raw));
    } catch (err) {
      storageOk = false;
      state = copy(DEFAULTS);
    }
    return state;
  }

  function save() {
    if (!storageOk) return false;
    try {
      window.localStorage.setItem(KEY, JSON.stringify(state));
      return true;
    } catch (err) {
      storageOk = false;
      return false;
    }
  }

  function emit() {
    for (var i = 0; i < listeners.length; i++) {
      try { listeners[i](state); } catch (err) { /* a listener must not break settings */ }
    }
  }

  function update(patch) {
    if (!patch) return state;
    if (patch.theme !== undefined) {
      state.theme = THEMES.indexOf(patch.theme) >= 0 ? patch.theme : state.theme;
    }
    if (patch.use24h !== undefined) state.use24h = !!patch.use24h;
    if (patch.location !== undefined) state.location = validLocation(patch.location);
    if (patch.ncsBaseUrl !== undefined) {
      var url = String(patch.ncsBaseUrl || '').trim();
      state.ncsBaseUrl = url ? url.slice(0, 300) : '';
    }
    save();
    emit();
    return state;
  }

  function onChange(fn) {
    if (typeof fn === 'function') listeners.push(fn);
  }

  SN.Store = {
    themes: THEMES.slice(),
    load: load,
    save: save,
    update: update,
    onChange: onChange,
    get: function (key) { return state[key]; },
    all: function () { return state; },
    storageAvailable: function () { return storageOk; },
    validLocation: validLocation
  };

  load();
})();
