/* Client for the NCS-SMLauncher remote-control protocol.

   This app is a remote, never a player: it polls /state, sends /control and
   never claims the TV is producing audio. Audio lives in NCS-SMLauncher. */
(function () {
  'use strict';

  var POLL_MS = 2000;
  var listeners = [];
  var baseUrl = '';
  var configured = false;
  var connected = false;
  var polling = false;
  var snapshot = null;
  var error = '';
  var lastPollAt = 0;
  var timer = null;
  var inFlight = false;
  var browseInFlight = false;
  var browseCache = [];
  var browseFor = '';
  var lastControlError = '';

  function emit() {
    for (var i = 0; i < listeners.length; i++) {
      try { listeners[i](); } catch (err) { /* keep the shell alive */ }
    }
  }

  function normalize(raw) {
    var value = String(raw || '').trim();
    if (!value) return '';
    if (value.indexOf('://') < 0) value = 'http://' + value;
    while (value.length > 1 && value.charAt(value.length - 1) === '/') {
      value = value.slice(0, -1);
    }
    return value.slice(0, 300);
  }

  function trackFrom(raw) {
    if (!raw || typeof raw !== 'object') return null;
    var title = typeof raw.title === 'string' ? raw.title : '';
    if (!title) return null;
    return {
      id: raw.id === undefined || raw.id === null ? '' : String(raw.id),
      title: title,
      artist: typeof raw.artist === 'string' ? raw.artist : '',
      album: typeof raw.album === 'string' ? raw.album : '',
      artwork: typeof raw.artwork === 'string' ? raw.artwork : '',
      durationMs: typeof raw.durationMs === 'number' ? raw.durationMs : 0
    };
  }

  function parseSnapshot(json) {
    if (!json || typeof json !== 'object') return null;
    var track = trackFrom(json.track) || trackFrom(json.current);
    var queue = [];
    if (Object.prototype.toString.call(json.queue) === '[object Array]') {
      for (var i = 0; i < json.queue.length; i++) {
        var item = trackFrom(json.queue[i]);
        if (item) queue.push(item);
      }
    }
    var durationMs = typeof json.durationMs === 'number' ? json.durationMs : 0;
    if (!durationMs && track) durationMs = track.durationMs || 0;
    return {
      playing: json.playing === true,
      server: typeof json.server === 'string' ? json.server : '',
      positionMs: typeof json.positionMs === 'number' ? json.positionMs : 0,
      durationMs: durationMs,
      volume: typeof json.volume === 'number' ? json.volume : 1,
      track: track,
      queue: queue,
      receivedAt: Date.now()
    };
  }

  function artworkUrl(track) {
    if (!track || !track.artwork) return '';
    var art = track.artwork;
    if (art.indexOf('http://') === 0 || art.indexOf('https://') === 0) return art;
    return baseUrl + (art.charAt(0) === '/' ? '' : '/') + art;
  }

  function fail(message) {
    connected = false;
    error = message || 'Could not reach the player';
    lastPollAt = Date.now();
    emit();
  }

  function refresh() {
    if (!configured || inFlight) return;
    inFlight = true;
    SN.net.getJSON(baseUrl + '/state', 6000, function (err, data) {
      inFlight = false;
      lastPollAt = Date.now();
      if (err) {
        if (err.code === 'http') fail('The player answered ' + err.status);
        else if (err.code === 'timeout') fail('The player did not answer');
        else if (err.code === 'json') fail('The player sent something that is not JSON');
        else fail('No player at ' + hostOf(baseUrl));
        return;
      }
      var next = parseSnapshot(data);
      if (!next) {
        fail('The player sent a state without a track');
        return;
      }
      snapshot = next;
      connected = true;
      error = '';
      emit();
    });
  }

  function hostOf(url) {
    var m = /^[a-z]+:\/\/([^/]+)/i.exec(url || '');
    return m ? m[1] : (url || 'that address');
  }

  function start() {
    if (!configured) return;
    if (timer) return;
    polling = true;
    timer = setInterval(refresh, POLL_MS);
    refresh();
    emit();
  }

  function stop() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    polling = false;
  }

  function configure(raw, autoStart) {
    var next = normalize(raw);
    if (next === baseUrl && autoStart === undefined) return;
    stop();
    baseUrl = next;
    configured = !!baseUrl;
    snapshot = null;
    connected = false;
    error = '';
    browseCache = [];
    browseFor = '';
    emit();
    if (autoStart && configured) start();
  }

  function parseBrowse(json) {
    if (!json || typeof json !== 'object') return [];
    var raw = json.tracks || json.albums || json.items;
    if (Object.prototype.toString.call(raw) !== '[object Array]') return [];
    var out = [];
    for (var i = 0; i < raw.length; i++) {
      var track = trackFrom(raw[i]);
      if (track) out.push(track);
    }
    return out;
  }

  function browse(done) {
    if (!configured) {
      done([]);
      return;
    }
    if (browseFor === baseUrl && browseCache.length) {
      done(browseCache.slice());
      return;
    }
    if (browseInFlight) {
      done([]);
      return;
    }
    browseInFlight = true;
    SN.net.getJSON(baseUrl + '/browse', 6000, function (err, data) {
      browseInFlight = false;
      if (err) {
        // /browse is optional. Silence is the correct answer for a player that
        // has no library; the queue already sent with /state still works.
        done([]);
        return;
      }
      var tracks = parseBrowse(data);
      if (tracks.length) {
        browseCache = tracks;
        browseFor = baseUrl;
      }
      done(tracks);
    });
  }

  function control(action, value, id, done) {
    if (!configured) {
      if (done) done({ message: 'No player address is configured.' });
      return;
    }
    var body = { action: action };
    if (typeof value === 'number' && isFinite(value)) body.value = value;
    if (id) body.id = id;
    SN.net.postJSON(baseUrl + '/control', body, 6000, function (err) {
      if (err) {
        lastControlError = 'The player did not acknowledge the command.';
        if (done) done({ message: lastControlError });
        // The next poll is the source of truth. Do not optimistically change
        // what the screen says a paused/playing player is doing.
        return;
      }
      lastControlError = '';
      if (done) done(null);
      refresh();
    });
  }

  function positionAt(now) {
    if (!snapshot) return 0;
    if (!snapshot.playing) return snapshot.positionMs;
    var elapsed = Math.max(0, (now || Date.now()) - snapshot.receivedAt);
    var moved = snapshot.positionMs + elapsed;
    if (snapshot.durationMs > 0 && moved > snapshot.durationMs) return snapshot.durationMs;
    return moved;
  }

  SN.Ncs = {
    exampleAddress: 'http://192.168.1.20:8737',
    pollMs: POLL_MS,
    normalize: normalize,
    configure: configure,
    start: start,
    stop: stop,
    refresh: refresh,
    browse: browse,
    control: control,
    artworkUrl: artworkUrl,
    positionAt: positionAt,
    onChange: function (fn) { if (typeof fn === 'function') listeners.push(fn); },
    baseUrl: function () { return baseUrl; },
    configured: function () { return configured; },
    connected: function () { return connected; },
    polling: function () { return polling; },
    snapshot: function () { return snapshot; },
    error: function () { return error; },
    lastPollAt: function () { return lastPollAt; }
  };
})();
