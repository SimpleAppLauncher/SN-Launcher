/* Nest Launcher TV — shell, pages, remote focus, weather and NCS UI. */
(function () {
  'use strict';

  var BUILD_DATA = window.SN_FEATURES || null;
  var CONFIG_MISSING = !BUILD_DATA || !BUILD_DATA.features;
  var FEATURES = (BUILD_DATA && BUILD_DATA.features) || { settings: true };
  var BUILD_NAME = (BUILD_DATA && (BUILD_DATA.build_name || BUILD_DATA.build)) || 'unknown';
  var PAGES = [];
  var PAGE_LABEL = {
    home: 'Home',
    digest: 'Digest',
    weather: 'Weather',
    music: 'Music'
  };
  var PHOTO = {
    title: 'Cub Lake at Dawn',
    author: 'Debra Miller',
    license: 'Public domain',
    licenseUrl: 'https://www.usa.gov/government-works',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Cub_Lake_at_dawn_in_Rocky_Mountain_National_Park._NPS-Debra_Miller_(18680833532).jpg'
  };
  var PRESET_CITIES = [
    { name: 'Hanoi, Vietnam', lat: 21.0278, lon: 105.8342 },
    { name: 'Da Nang, Vietnam', lat: 16.0544, lon: 108.2022 },
    { name: 'Ho Chi Minh City, Vietnam', lat: 10.8231, lon: 106.6297 },
    { name: 'Hue, Vietnam', lat: 16.4637, lon: 107.5909 },
    { name: 'Nha Trang, Vietnam', lat: 12.2388, lon: 109.1967 },
    { name: 'Can Tho, Vietnam', lat: 10.0452, lon: 105.7469 }
  ];
  var THEME_LABEL = {
    night: 'Night',
    day: 'Day',
    afternoon: 'Afternoon',
    white: 'White'
  };
  var WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];

  var state = {
    page: 0,
    overlay: null,
    returnFocus: null,
    library: [],
    libraryFor: '',
    libraryVersion: 0,
    musicSig: '',
    playerSig: '',
    digestSig: '',
    lastClockMinute: '',
    lastBackAt: 0,
    exitArmedAt: 0,
    returnFocusKey: '',
    hintTimer: null,
    toastTimer: null,
    settingsSection: 'display',
    draft: {
      cityQuery: '',
      searchResults: [],
      searching: false,
      searchError: '',
      searchMessage: '',
      ncsAddress: '',
      ncsError: '',
      manualPlace: '',
      manualLat: '',
      manualLon: '',
      error: ''
    }
  };

  var app, pagesEl, overlayEl, toastEl, hintEl, chromeEl, settingsBtn, dotsEl, bootEl;

  function flag(name) {
    return !!(FEATURES && FEATURES[name] === true);
  }

  function bodyEl() {
    return document.body;
  }

  function $(id) {
    return document.getElementById(id);
  }

  function esc(value) {
    return String(value === undefined || value === null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function cssUrl(url) {
    return encodeURI(String(url || ''))
      .replace(/'/g, '%27')
      .replace(/"/g, '%22')
      .replace(/\(/g, '%28')
      .replace(/\)/g, '%29');
  }

  function pad2(n) {
    return n < 10 ? '0' + n : '' + n;
  }

  function formatTime(date, use24h, withSeconds) {
    var h = use24h ? date.getHours() : (date.getHours() % 12 || 12);
    var out = (use24h ? pad2(h) : String(h)) + ':' + pad2(date.getMinutes());
    if (withSeconds) out += ':' + pad2(date.getSeconds());
    return out;
  }

  function meridiem(date) {
    return date.getHours() < 12 ? 'AM' : 'PM';
  }

  function nestDate(date) {
    return WEEKDAYS[date.getDay()].slice(0, 3) + ', ' +
      MONTHS[date.getMonth()].slice(0, 3) + ' ' + date.getDate();
  }

  function longDate(date) {
    return WEEKDAYS[date.getDay()] + ', ' + MONTHS[date.getMonth()] + ' ' + date.getDate();
  }

  function greeting(date) {
    var h = date.getHours();
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }

  function formatUpdated(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return formatTime(d, true, false);
  }

  function formatMs(ms) {
    var total = Math.max(0, Math.floor((ms || 0) / 1000));
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    if (h > 0) return h + ':' + pad2(m) + ':' + pad2(s);
    return m + ':' + pad2(s);
  }

  function coordinateLabel(lat, lon) {
    var ns = Number(lat) >= 0 ? 'N' : 'S';
    var ew = Number(lon) >= 0 ? 'E' : 'W';
    return Math.abs(Number(lat)).toFixed(2) + '°' + ns + ', ' +
      Math.abs(Number(lon)).toFixed(2) + '°' + ew;
  }

  function locationLabel(loc) {
    if (!loc) return '';
    if (loc.name) return loc.name;
    return coordinateLabel(loc.lat, loc.lon);
  }

  function tempLabel(value) {
    if (typeof value !== 'number' || !isFinite(value)) return '';
    return Math.round(value) + '°';
  }

  function conditionLabel(condition) {
    return SN.Weather.labels[condition] || SN.Weather.labels.unknown;
  }

  function themeLabel(theme) {
    return THEME_LABEL[theme] || 'Night';
  }

  function currentPageName() {
    return PAGES[state.page] || 'home';
  }

  function currentPageEl() {
    return $('page-' + currentPageName());
  }

  function isEditing() {
    var el = document.activeElement;
    if (!el) return false;
    var tag = (el.tagName || '').toLowerCase();
    return tag === 'input' || tag === 'textarea' || tag === 'select';
  }

  function finishEditing() {
    var el = document.activeElement;
    var targetId = el && el.getAttribute ? el.getAttribute('data-enter-target') : '';
    if (el && el.blur) el.blur();
    if (targetId) {
      var target = $(targetId);
      if (target && visible(target)) {
        focusEl(target, false);
        return;
      }
    }
    if (state.overlay) focusOverlay();
    else focusPage();
  }

  /* ────────────────────────────────────────────────────────────── scale */

  function applyScale() {
    var u = Math.min(window.innerWidth / 1024, window.innerHeight / 600);
    if (!isFinite(u) || u <= 0) u = 1.8;
    document.documentElement.style.setProperty('--u', u + 'px');
  }

  function applyTheme() {
    var theme = SN.Store.get('theme');
    bodyEl().setAttribute('data-theme', theme);
    state.lastClockMinute = '';
  }

  /* ────────────────────────────────────────────────────────────── shell */

  function buildPages() {
    PAGES = ['home'];
    if (flag('digestPage')) PAGES.push('digest');
    if (flag('weather')) PAGES.push('weather');
    if (flag('music') && flag('ncsPlayer')) PAGES.push('music');

    pagesEl.innerHTML = '';
    for (var i = 0; i < PAGES.length; i++) {
      var id = PAGES[i];
      var page = document.createElement('section');
      page.className = 'page' + (id === 'music' ? ' music-page' : '') +
        (id === 'weather' ? ' weather-page' : '') +
        (id !== 'home' && id !== 'music' && id !== 'weather' ? ' surface-page' : '');
      page.id = 'page-' + id;
      page.setAttribute('data-page', id);
      page.setAttribute('aria-label', PAGE_LABEL[id]);
      pagesEl.appendChild(page);
    }

    renderHome();
    if (flag('digestPage')) renderDigest();
    if (flag('weather')) renderWeather();
    if (flag('music') && flag('ncsPlayer')) renderMusic(true);

    renderDots();
    updateChrome();
  }

  function updateChrome() {
    settingsBtn.hidden = !flag('settings');
  }

  function renderDots() {
    var html = '';
    for (var i = 0; i < PAGES.length; i++) {
      html += '<span class="dot' + (i === state.page ? ' active' : '') + '"></span>' +
        '<span class="dot-label">' + esc(PAGE_LABEL[PAGES[i]]) + '</span>';
    }
    dotsEl.innerHTML = html;
  }

  function updateDots() {
    var dots = dotsEl.querySelectorAll('.dot');
    for (var i = 0; i < dots.length; i++) {
      if (i === state.page) dots[i].classList.add('active');
      else dots[i].classList.remove('active');
    }
  }

  function showPage(index, opts) {
    if (!PAGES.length) return;
    if (index < 0) index = 0;
    if (index >= PAGES.length) index = PAGES.length - 1;
    if (index === state.page && !(opts && opts.force)) {
      focusPage();
      return;
    }
    state.page = index;

    var els = pagesEl.querySelectorAll('.page');
    for (var i = 0; i < els.length; i++) {
      els[i].classList.toggle('active', i === index);
      els[i].classList.toggle('before', i < index);
    }

    var name = currentPageName();
    if (name === 'home') {
      updateHome(true);
    } else if (name === 'digest') {
      renderDigest();
    } else if (name === 'weather') {
      renderWeather();
      SN.Weather.refresh(false);
    } else if (name === 'music') {
      SN.Ncs.start();
      ensureLibrary();
      renderMusic(true);
    }

    if (name !== 'music') SN.Ncs.stop();

    updateDots();
    focusPage();
    flashHint();
  }

  function showPageById(id) {
    var index = PAGES.indexOf(id);
    if (index < 0) {
      toast('That page is not in this build.');
      return;
    }
    showPage(index, { force: true });
  }

  function focusPage() {
    var page = currentPageEl();
    var target = null;
    if (page) {
      target = firstVisible(focusableNodes(page));
    }
    if (!target && !settingsBtn.hidden) target = settingsBtn;
    if (target) focusEl(target, false);
  }

  /* ─────────────────────────────────────────────────────────────── home */

  function renderHome() {
    var home = $('page-home');
    if (!home) return;
    home.innerHTML =
      '<div class="home-photo"></div>' +
      '<div class="home-scrim"></div>' +
      '<div class="home-date" id="home-date"></div>' +
      '<div class="home-clock-row">' +
        '<div class="home-time" id="home-time"></div>' +
        '<div class="home-ampm" id="home-ampm"></div>' +
        '<div class="home-weather" id="home-weather" hidden></div>' +
      '</div>' +
      '<div class="home-credit">' +
        '<span>' + esc(PHOTO.title) + '</span>' +
        '<span class="credit-author">' + esc(PHOTO.author) + '</span>' +
      '</div>';
    updateHome(true);
  }

  function updateHome(force) {
    var now = new Date();
    var use24h = SN.Store.get('use24h') !== false;
    var minuteKey = now.getFullYear() + '-' + now.getMonth() + '-' + now.getDate() +
      '-' + now.getHours() + '-' + now.getMinutes() + '-' + (use24h ? '24' : '12');
    if (!force && minuteKey === state.lastClockMinute) return;
    state.lastClockMinute = minuteKey;

    var timeEl = $('home-time');
    var ampmEl = $('home-ampm');
    var dateEl = $('home-date');
    var weatherEl = $('home-weather');
    if (!timeEl || !dateEl || !weatherEl) return;

    timeEl.textContent = formatTime(now, use24h, false);
    dateEl.textContent = nestDate(now);

    if (!use24h) {
      ampmEl.textContent = meridiem(now);
      ampmEl.hidden = false;
    } else {
      ampmEl.textContent = '';
      ampmEl.hidden = true;
    }

    var reading = SN.Weather.current();
    var loc = SN.Weather.location();
    if (flag('weather') && reading && loc) {
      weatherEl.innerHTML = '<span class="home-weather-icon">' +
        SN.weatherIcon(reading.condition) + '</span>' +
        '<span class="home-temp">' + esc(tempLabel(reading.temperatureC)) + '</span>';
      weatherEl.hidden = false;
    } else {
      weatherEl.innerHTML = '';
      weatherEl.hidden = true;
    }
  }

  /* ───────────────────────────────────────────────────────────── digest */

  function cardOpen(action, key, title, icon, body, extra) {
    return '<button class="card focusable" type="button" data-action="' + action +
      '" data-fk="' + key + '">' +
      '<div class="card-title"><span class="card-title-icon">' + SN.icon(icon) + '</span>' +
      esc(title) + '</div>' + body + (extra || '') + '</button>';
  }

  function renderDigest() {
    var page = $('page-digest');
    if (!page) return;
    var now = new Date();
    var cards = [];

    if (flag('calendar')) {
      cards.push('<div class="card">' +
        '<div class="card-title"><span class="card-title-icon">' + SN.icon('calendar') + '</span>Calendar</div>' +
        '<p class="card-body">' + esc(nestDate(now)) + '</p>' +
        '<div class="card-row"><span class="pill bad">Not available</span></div>' +
        '<div class="card-note">Calendar reads are not implemented in this Tizen TV port. Nothing is being read, and no events are invented.</div>' +
        '</div>');
    }

    if (flag('todo')) {
      cards.push('<div class="card">' +
        '<div class="card-title"><span class="card-title-icon">' + SN.icon('list') + '</span>To-do</div>' +
        '<p class="card-body">No to-do source is connected to this TV.</p>' +
        '<div class="card-row"><span class="pill bad">Not available</span></div>' +
        '<div class="card-note">The Android app has a local to-do list. This TV port does not sync it, so it does not show an empty list that would imply otherwise.</div>' +
        '</div>');
    }

    if (flag('weather')) {
      cards.push(renderDigestWeatherCard());
    }

    if (flag('music') && flag('ncsPlayer')) {
      cards.push(renderDigestMusicCard());
    }

    if (flag('photoRotation')) {
      cards.push('<div class="card">' +
        '<div class="card-title"><span class="card-title-icon">' + SN.icon('photo') + '</span>Photo</div>' +
        '<p class="card-body"><strong>' + esc(PHOTO.title) + '</strong><br>' +
        esc(PHOTO.author) + ' · ' + esc(PHOTO.license) + '</p>' +
        '<div class="card-row"><span class="pill">One bundled photo</span></div>' +
        '<div class="card-note">Photo rotation needs a photo library. This TV build ships one credited landscape and does not pretend to rotate it.</div>' +
        '</div>');
    }

    if (flag('themePicker')) {
      cards.push('<button class="card focusable" type="button" data-action="cycle-theme" data-fk="digest-theme">' +
        '<div class="card-title"><span class="card-title-icon">' + SN.icon('palette') + '</span>Theme</div>' +
        '<p class="card-body"><strong>' + esc(themeLabel(SN.Store.get('theme'))) + '</strong><br>Pinned on this TV</p>' +
        '<div class="theme-options">' + themeSwatches(SN.Store.get('theme')) + '</div>' +
        '<div class="card-row"><span class="card-meta">Press OK to cycle</span></div>' +
        '</button>');
    }

    var grid = cards.length
      ? '<div class="digest-grid">' + cards.join('') + '</div>'
      : '<div class="card"><div class="card-title">Digest</div><p class="card-body">This build has no digest cards enabled.</p></div>';

    page.innerHTML =
      '<div class="page-head"><div class="page-head-copy">' +
        '<div class="eyebrow">' + esc(longDate(now)) + '</div>' +
        '<h1 class="page-title">' + esc(greeting(now)) + '</h1>' +
      '</div></div>' +
      '<div class="digest-scroll">' + grid + '</div>';

    state.digestSig = digestSignature();
    if (currentPageName() === 'digest' && !state.overlay) restoreFocus(page, 'digest-theme');
  }

  function themeSwatches(selected) {
    var themes = SN.Store.themes;
    var out = '';
    for (var i = 0; i < themes.length; i++) {
      out += '<span class="theme-swatch ' + themes[i] +
        (themes[i] === selected ? ' selected' : '') + '"></span>';
    }
    return out;
  }

  function renderDigestWeatherCard() {
    var loc = SN.Weather.location();
    var reading = SN.Weather.current();
    var status = SN.Weather.status();
    var body;
    var note = '';
    var extra = '';

    if (!loc) {
      body = '<p class="card-body">No weather location is set.</p>';
      note = '<div class="card-note">Open Settings → Weather location to search for a city or enter coordinates. This page will not invent a temperature.</div>';
    } else if (reading) {
      body = '<div class="weather-mini">' +
        '<span class="weather-mini-icon">' + SN.weatherIcon(reading.condition) + '</span>' +
        '<div><div class="weather-mini-temp">' + esc(tempLabel(reading.temperatureC)) + '</div>' +
        '<div class="weather-mini-text">' + esc(conditionLabel(reading.condition)) + '</div></div>' +
        '</div>' +
        '<p class="card-body" style="margin-top:' + 'calc(var(--u) * 12)">' +
        esc(locationLabel(loc)) + '<br>' +
        esc(highLow(reading)) + '</p>';
      note = '<div class="card-note">Open-Meteo · updated ' + esc(formatUpdated(reading.fetchedAt)) +
        (status === 'stale' ? ' · showing the last reading (offline)' : '') + '</div>';
      if (status === 'stale') extra = '<div class="card-row"><span class="pill warm">Offline</span></div>';
    } else if (status === 'loading') {
      body = '<p class="card-body">Fetching weather for <strong>' + esc(locationLabel(loc)) + '</strong>…</p>';
      note = '<div class="card-note">Open-Meteo. This card stays empty until a real reading arrives.</div>';
    } else {
      body = '<p class="card-body">Weather is unavailable.</p>';
      note = '<div class="card-note">' + esc(SN.Weather.error() || 'No reading has arrived yet.') + '</div>';
      extra = '<div class="card-row"><span class="pill bad">No reading</span></div>';
    }

    return cardOpen('go-weather', 'digest-weather', 'Weather', 'weather', body, extra + note);
  }

  function highLow(reading) {
    var bits = [];
    if (typeof reading.highC === 'number') bits.push('High ' + Math.round(reading.highC) + '°');
    if (typeof reading.lowC === 'number') bits.push('Low ' + Math.round(reading.lowC) + '°');
    if (typeof reading.feelsLikeC === 'number') bits.push('Feels ' + Math.round(reading.feelsLikeC) + '°');
    return bits.join(' · ');
  }

  function renderDigestMusicCard() {
    var snap = SN.Ncs.snapshot();
    var url = SN.Ncs.baseUrl();
    var body;
    var note;
    var extra = '';
    if (!url) {
      body = '<p class="card-body">No player address is configured.</p>';
      note = '<div class="card-note">Open Music to enter the address of NCS-SMLauncher. The TV is only a remote; it never plays the audio itself.</div>';
    } else if (snap && snap.track) {
      body = '<div class="now-mini">' + artThumb(snap.track, 'now-mini-art') +
        '<div class="now-mini-copy"><div class="now-mini-title">' + esc(snap.track.title) + '</div>' +
        '<div class="now-mini-sub">' + esc(snap.track.artist || 'Unknown artist') + '</div></div></div>' +
        '<p class="card-body" style="margin-top:' + 'calc(var(--u) * 12)">' +
        esc(snap.playing ? 'Playing' : 'Paused') + ' · ' + esc(snap.server || 'NCS player') + '</p>';
      var live = SN.Ncs.polling() && SN.Ncs.connected();
      extra = '<div class="card-row"><span class="pill ' + (live ? 'good' : 'warm') + '">' +
        (live ? 'Connected' : 'Last known') + '</span></div>';
      note = '<div class="card-note">Remote control only. Audio plays on the NCS-SMLauncher machine, not on this TV.' +
        (live ? '' : ' Polling is paused while you are not on the Music page.') + '</div>';
    } else {
      body = '<p class="card-body">' + (SN.Ncs.connected() ? 'No track is reported.' : 'No reading from the player.') + '</p>';
      if (SN.Ncs.error()) {
        note = '<div class="card-note">' + esc(SN.Ncs.error()) + '</div>';
        extra = '<div class="card-row"><span class="pill bad">Offline</span></div>';
      } else {
        note = '<div class="card-note">No reading yet. Open Music to connect to ' + esc(url) + '. The TV never plays the audio itself.</div>';
        extra = '<div class="card-row"><span class="pill">Not connected</span></div>';
      }
    }
    return cardOpen('go-music', 'digest-music', 'Music', 'music', body, extra + note);
  }

  function digestSignature() {
    var snap = SN.Ncs.snapshot();
    return [
      SN.Weather.status(),
      SN.Weather.location() ? locationLabel(SN.Weather.location()) : '',
      SN.Weather.current() ? String(SN.Weather.current().temperatureC) : '',
      SN.Ncs.connected() ? '1' : '0',
      SN.Ncs.baseUrl(),
      snap && snap.track ? snap.track.title + '|' + snap.track.artist : '',
      snap ? (snap.playing ? '1' : '0') : '',
      SN.Store.get('theme')
    ].join('~');
  }

  /* ──────────────────────────────────────────────────────────── weather */

  function renderWeather() {
    var page = $('page-weather');
    if (!page) return;
    var loc = SN.Weather.location();
    var reading = SN.Weather.current();
    var condition = reading ? reading.condition : 'unknown';
    var sky = SN.Weather.sky(condition);
    page.style.setProperty('--sky-1', sky[0]);
    page.style.setProperty('--sky-2', sky[1]);
    page.style.setProperty('--sky-3', sky[2]);
    page.classList.remove('dark-ink', 'light-ink');
    page.classList.add(reading ? SN.Weather.inkFor(condition) : 'light-ink');

    if (!loc) {
      page.innerHTML = weatherShell(
        'Weather',
        'This TV has no location yet',
        '<div class="weather-empty">' +
          '<h2>No weather location</h2>' +
          '<p>This launcher does not guess a city and does not show a placeholder temperature. Search for a city or enter coordinates in Settings.</p>' +
          '<button class="ghost-button focusable" type="button" data-action="open-settings-weather" data-fk="weather-settings"' +
          (flag('settings') ? ' data-autofocus' : ' disabled') + '>' +
          SN.icon('location') + 'Set a weather location</button>' +
        '</div>',
        ''
      );
      return;
    }

    var name = locationLabel(loc);
    var locationMeta = 'Location set by hand · ' + coordinateLabel(loc.lat, loc.lon);

    if (!reading) {
      var loading = SN.Weather.status() === 'loading';
      page.innerHTML = weatherShell(
        'Weather',
        name,
        '<div class="weather-empty">' +
          '<h2>' + (loading ? 'Fetching the weather…' : 'Weather unavailable') + '</h2>' +
          '<p>' + (loading
            ? 'Open-Meteo is being asked for ' + esc(name) + '. Nothing is shown until a real reading arrives.'
            : esc(SN.Weather.error() || 'No reading has arrived yet.')) + '</p>' +
          '<div class="mini-actions">' +
            '<button class="ghost-button focusable" type="button" data-action="refresh-weather" data-fk="weather-retry" data-autofocus>' +
              SN.icon('refresh') + 'Try again</button>' +
            (flag('settings')
              ? '<button class="ghost-button focusable" type="button" data-action="open-settings-weather" data-fk="weather-settings">' +
                SN.icon('settings') + 'Weather settings</button>'
              : '') +
          '</div>' +
        '</div>',
        locationMeta
      );
      return;
    }

    var stale = SN.Weather.status() === 'stale';
    var errorLine = stale
      ? 'Offline · showing the last reading from ' + formatUpdated(reading.fetchedAt) +
        (SN.Weather.error() ? ' · ' + esc(SN.Weather.error()) : '')
      : 'Open-Meteo · updated ' + formatUpdated(reading.fetchedAt) + ' · refreshed hourly';

    page.innerHTML = weatherShell(
      'Weather',
      name,
      '<div class="weather-main">' +
        '<div class="weather-glyph-large">' + SN.weatherIcon(reading.condition) + '</div>' +
        '<div class="weather-temp">' + esc(tempLabel(reading.temperatureC)) + '</div>' +
        '<div class="weather-condition">' + esc(conditionLabel(reading.condition)) + '</div>' +
        '<div class="weather-hilo">' + esc(highLow(reading) || ' ') + '</div>' +
        '<div class="weather-sentence">' + esc(SN.Weather.sentence(reading.condition, new Date().getHours())) + '</div>' +
        '<div class="weather-facts">' +
          (typeof reading.feelsLikeC === 'number' ? '<span>Feels like ' + Math.round(reading.feelsLikeC) + '°</span>' : '') +
          (typeof reading.humidity === 'number' ? '<span>Humidity ' + reading.humidity + '%</span>' : '') +
          '<span>' + esc(coordinateLabel(loc.lat, loc.lon)) + '</span>' +
        '</div>' +
      '</div>',
      locationMeta,
      '<div class="weather-source">' + errorLine +
        (stale ? '<br><strong>Not live.</strong>' : '') +
        '<br>Weather data by Open-Meteo.com (CC BY 4.0). Location is set by hand.</div>' +
      '<div class="weather-actions">' +
        '<button class="ghost-button focusable" type="button" data-action="refresh-weather" data-fk="weather-refresh">' +
          SN.icon('refresh') + 'Refresh</button>' +
        (flag('settings')
          ? '<button class="ghost-button focusable" type="button" data-action="open-settings-weather" data-fk="weather-settings">' +
            SN.icon('settings') + 'Settings</button>'
          : '') +
      '</div>',
      stale
    );

    if (currentPageName() === 'weather') {
      var pageFocus = SN.Weather.loading() ? 'weather-refresh' : 'weather-refresh';
      if (!state.overlay) restoreFocus(page, pageFocus);
    }
  }

  function weatherShell(title, place, main, locationMeta, footer, stale) {
    return '<div class="weather-inner">' +
      '<div class="weather-top">' +
        '<div class="weather-place">' +
          '<div class="eyebrow" style="color:inherit;opacity:.65">' + esc(title) + '</div>' +
          '<h1 class="weather-place-name">' + esc(place) + '</h1>' +
          '<div class="weather-place-meta">' + esc(locationMeta || '') + '</div>' +
        '</div>' +
        (stale ? '<span class="pill warm">Offline</span>' : '') +
      '</div>' +
      main +
      (footer ? '<div class="weather-footer">' + footer + '</div>' : '') +
      '</div>';
  }

  /* ────────────────────────────────────────────────────────────── music */

  function trackSig(t) {
    if (!t) return '';
    return [t.id, t.title, t.artist, t.album, t.artwork].join('\u0001');
  }

  function musicSignature() {
    var snap = SN.Ncs.snapshot();
    var lib = [];
    for (var i = 0; i < state.library.length; i++) lib.push(trackSig(state.library[i]));
    return [
      SN.Ncs.baseUrl(),
      SN.Ncs.connected() ? '1' : '0',
      SN.Ncs.error(),
      snap ? (snap.playing ? '1' : '0') : '',
      snap ? trackSig(snap.track) : '',
      snap ? snap.queue.map(trackSig).join('\u0002') : '',
      state.libraryVersion,
      lib.join('\u0003')
    ].join('|');
  }

  function artThumb(track, cls) {
    var url = SN.Ncs.artworkUrl(track);
    if (!url) return '<span class="' + cls + '"></span>';
    return '<span class="' + cls + '" style="background-image:url(' + "'" + cssUrl(url) + "'" + ')"></span>';
  }

  function renderMusic(force) {
    var page = $('page-music');
    if (!page) return;
    var snap = SN.Ncs.snapshot();
    var sig = musicSignature();
    if (!force && sig === state.musicSig) {
      updateMusicProgress();
      return;
    }
    state.musicSig = sig;

    var header = '<div class="music-head">' +
      '<div class="music-head-copy"><h1 class="music-title">Music</h1>' +
      '<div class="music-sub">Remote control for NCS-SMLauncher · audio stays on the player</div></div>' +
      connectionChip() +
      '</div>';

    if (!snap) {
      page.innerHTML = header + connectCard();
      if (currentPageName() === 'music' && !state.overlay) {
        restoreFocus(page, SN.Ncs.configured() ? 'connect-ncs' : 'ncs-address');
      }
      return;
    }

    var picks = quickPicks(snap);
    var upNext = [];
    for (var i = 0; i < snap.queue.length; i++) {
      var q = snap.queue[i];
      if (snap.track && q.title === snap.track.title) continue;
      upNext.push(q);
    }

    var feed = '';
    if (picks.length) {
      feed += '<div class="section-head"><div class="section-title">Quick picks</div>' +
        '<div class="section-note">' + (state.library.length ? 'Player library' : 'From the current queue') + '</div></div>' +
        '<div class="picks">';
      for (var p = 0; p < picks.length; p++) {
        feed += albumCard(picks[p], p, snap);
      }
      feed += '</div>';
    }

    if (upNext.length) {
      feed += '<div class="section-head"><div class="section-title">Up next</div>' +
        '<div class="section-note">' + upNext.length + ' queued</div></div>' +
        '<div class="queue">';
      for (var u = 0; u < upNext.length; u++) {
        feed += queueRow(upNext[u], u);
      }
      feed += '</div>';
    } else if (!picks.length) {
      feed += '<div class="connect-card" style="margin-top:calc(var(--u) * 24)">' +
        '<h2>Nothing in the queue</h2>' +
        '<p class="connect-copy">The player reported a current track but no library or queue. The transport below still controls what is playing.</p>' +
        '</div>';
    } else {
      feed += '<div class="section-head"><div class="section-title">Up next</div></div>' +
        '<div class="connect-copy">The player did not report anything after this track.</div>';
    }

    page.innerHTML = header + '<div class="music-scroll">' + feed + '</div>' + miniPlayer(snap);
    if (currentPageName() === 'music' && !state.overlay) {
      restoreFocus(page, 'mini-open');
    }
  }

  function connectionChip() {
    var snap = SN.Ncs.snapshot();
    var stateClass = 'offline';
    var label = 'Not connected';
    if (SN.Ncs.connected()) {
      stateClass = 'connected';
      label = snap && snap.server ? snap.server : 'Player';
    } else if (snap) {
      stateClass = 'reconnecting';
      label = 'Reconnecting…';
    } else if (SN.Ncs.configured() && !SN.Ncs.error()) {
      stateClass = 'reconnecting';
      label = 'Connecting…';
    } else if (SN.Ncs.configured()) {
      stateClass = 'offline';
      label = 'Offline';
    }
    return '<div class="connection-chip ' + stateClass + '" title="' + esc(SN.Ncs.baseUrl() || 'No address') + '">' +
      '<span class="status-dot"></span><span>' + esc(label) + '</span></div>';
  }

  function quickPicks(snap) {
    var all = state.library.concat(snap ? snap.queue : []);
    var seen = {};
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var t = all[i];
      if (!t || !t.title) continue;
      var key = t.id || t.title;
      if (seen[key]) continue;
      seen[key] = true;
      out.push(t);
      if (out.length >= 24) break;
    }
    return out;
  }

  function albumCard(track, index, snap) {
    var playing = snap && snap.playing && snap.track && snap.track.title === track.title;
    var art = SN.Ncs.artworkUrl(track);
    var initial = esc(track.title.charAt(0).toUpperCase() || '♪');
    return '<button class="album-card focusable" type="button" data-action="play-track" data-id="' +
      esc(track.id) + '" data-fk="album-' + index + '">' +
      '<div class="album-art">' +
        '<div class="album-art-fallback">' + initial + '</div>' +
        (art ? '<img src="' + esc(art) + '" alt="" onerror="this.style.display=\'none\'">' : '') +
        (playing ? '<span class="album-playing">' + SN.icon('play') + 'Playing</span>' : '') +
      '</div>' +
      '<div class="album-copy"><div class="album-title">' + esc(track.title) + '</div>' +
      '<div class="album-artist">' + esc(track.artist || 'Unknown artist') + '</div></div>' +
      '</button>';
  }

  function queueRow(track, index) {
    var duration = track.durationMs ? formatMs(track.durationMs) : '';
    var art = SN.Ncs.artworkUrl(track);
    return '<button class="queue-row focusable" type="button" data-action="play-track" data-id="' +
      esc(track.id) + '" data-fk="queue-' + index + '">' +
      '<span class="queue-index">' + (index + 1) + '</span>' +
      '<span class="queue-art"' + (art ? ' style="background-image:url(' + "'" + cssUrl(art) + "'" + ')"' : '') + '></span>' +
      '<span class="queue-copy"><span class="queue-title">' + esc(track.title) + '</span>' +
      '<span class="queue-artist">' + esc(track.artist || 'Unknown artist') + '</span></span>' +
      '<span class="queue-duration">' + esc(duration) + '</span>' +
      '</button>';
  }

  function miniPlayer(snap) {
    if (!snap || !snap.track) return '';
    var art = SN.Ncs.artworkUrl(snap.track);
    var pct = snap.durationMs > 0 ? Math.min(100, NcsPositionPercent(snap)) : 0;
    return '<div class="mini-player">' +
      '<button class="mini-open focusable" type="button" data-action="open-player" data-fk="mini-open">' +
        '<span class="mini-art"' + (art ? ' style="background-image:url(' + "'" + cssUrl(art) + "'" + ')"' : '') + '></span>' +
        '<span class="mini-copy"><span class="mini-title">' + esc(snap.track.title) + '</span>' +
        '<span class="mini-artist">' + esc(snap.track.artist || 'Unknown artist') + '</span></span>' +
      '</button>' +
      '<div class="mini-controls">' +
        '<button class="transport focusable" type="button" data-action="prev-track" data-fk="mini-prev" aria-label="Previous track">' + SN.icon('previous') + '</button>' +
        '<button class="transport primary focusable" type="button" data-action="toggle-play" data-fk="mini-toggle" aria-label="' +
          (snap.playing ? 'Pause' : 'Play') + '">' + SN.icon(snap.playing ? 'pause' : 'play') + '</button>' +
        '<button class="transport focusable" type="button" data-action="next-track" data-fk="mini-next" aria-label="Next track">' + SN.icon('next') + '</button>' +
      '</div>' +
      '<div class="mini-progress-track"><div class="mini-progress-fill" id="mini-fill" style="width:' + pct.toFixed(2) + '%"></div></div>' +
      '</div>';
  }

  function connectCard() {
    var configured = SN.Ncs.configured();
    var error = SN.Ncs.error();
    var status = '';
    if (error) {
      status = '<div class="connect-status error">' + SN.icon('alert') + '<span>' + esc(error) + '</span></div>';
    } else if (configured) {
      status = '<div class="connect-status"><span class="status-dot" style="color:#ffb300"></span><span>Connecting to ' +
        esc(SN.Ncs.baseUrl()) + '…</span></div>';
    } else {
      status = '<div class="connect-status error">' + SN.icon('alert') + '<span>No player address is configured.</span></div>';
    }

    return '<div class="connect-wrap"><div class="connect-card">' +
      '<h2>Connect to NCS-SMLauncher</h2>' +
      status +
      '<p class="connect-copy">Enter the address of the machine running the player, for example <code>http://192.168.1.123:8737</code>.</p>' +
      '<div class="field-row">' +
        '<input id="connect-ncs-input" class="field" type="text" inputmode="url" spellcheck="false" autocomplete="off" ' +
          'aria-label="Player address" data-draft="ncsAddress" data-enter-target="connect-ncs" data-fk="ncs-address" ' +
          'value="' + esc(SN.Store.get('ncsBaseUrl') || '') + '" placeholder="http://192.168.1.123:8737">' +
        '<button id="connect-ncs" class="primary-button focusable" type="button" data-action="connect-ncs" data-fk="connect-ncs" data-autofocus>' +
          (error ? 'Retry' : 'Connect') + '</button>' +
      '</div>' +
      '<div class="connect-actions">' +
        '<button class="secondary-button focusable" type="button" data-action="refresh-ncs" data-fk="ncs-refresh">' + SN.icon('refresh') + ' Check now</button>' +
        '<button class="secondary-button focusable" type="button" data-action="open-settings" data-fk="ncs-settings">Player address settings</button>' +
      '</div>' +
      '<div class="connect-note"><strong>The TV is a remote, not a player.</strong> It sends play, pause, next and seek to NCS-SMLauncher. Audio comes out of the player machine, never this TV.<br><br>' +
        'Mock server: <code>python3 tool/ncs_mock_server.py --port 8737</code>, then enter the printed LAN address. The mock controls state; it does not make the TV play sound.</div>' +
      '</div></div>';
  }

  function NcsPositionPercent(snap) {
    if (!snap || !snap.durationMs) return 0;
    return Math.max(0, Math.min(100, (SN.Ncs.positionAt(Date.now()) / snap.durationMs) * 100));
  }

  function updateMusicProgress() {
    var fill = $('mini-fill');
    var snap = SN.Ncs.snapshot();
    if (fill && snap) fill.style.width = NcsPositionPercent(snap).toFixed(2) + '%';
  }

  function ensureLibrary() {
    if (!SN.Ncs.connected()) return;
    var base = SN.Ncs.baseUrl();
    if (!base || state.libraryFor === base) return;
    state.libraryFor = base;
    SN.Ncs.browse(function (tracks) {
      if (SN.Ncs.baseUrl() !== base) return;
      state.library = tracks || [];
      state.libraryVersion++;
      if (currentPageName() === 'music') renderMusic(false);
    });
  }

  /* ───────────────────────────────────────────────────────────── player */

  function openPlayer() {
    var snap = SN.Ncs.snapshot();
    if (!snap || !snap.track) {
      toast('Nothing is playing yet.');
      return;
    }
    renderPlayer();
  }

  function playerSignature() {
    var snap = SN.Ncs.snapshot();
    if (!snap) return 'none';
    return [
      trackSig(snap.track),
      snap.playing ? '1' : '0',
      Number(snap.volume).toFixed(2),
      SN.Ncs.connected() ? '1' : '0',
      snap.server
    ].join('|');
  }

  function renderPlayer() {
    var snap = SN.Ncs.snapshot();
    if (!snap || !snap.track) {
      if (state.overlay === 'player') closeOverlay();
      return;
    }
    state.playerSig = playerSignature();
    var art = SN.Ncs.artworkUrl(snap.track);
    var pos = Math.min(SN.Ncs.positionAt(Date.now()), snap.durationMs || 0);
    var pct = snap.durationMs > 0 ? Math.min(100, (pos / snap.durationMs) * 100) : 0;
    var html = '<div class="sheet player-sheet" role="document">' +
      '<div class="sheet-head">' +
        '<div><h2 class="sheet-title">Now playing</h2>' +
          '<p class="sheet-sub">Remote control · the TV does not play the audio</p></div>' +
        '<button class="icon-button focusable" type="button" data-action="close-player" data-fk="player-close" aria-label="Close player">' + SN.icon('close') + '</button>' +
      '</div>' +
      '<div class="player-body">' +
        '<div class="player-art-wrap"><div class="player-art"' +
          (art ? ' style="background-image:url(' + "'" + cssUrl(art) + "'" + ')"' : '') + '></div></div>' +
        '<div class="player-info">' +
          '<div class="player-eyebrow">' + esc(snap.playing ? 'Playing' : 'Paused') + ' · ' + esc(snap.server || 'NCS-SMLauncher') + '</div>' +
          '<h3 class="player-track">' + esc(snap.track.title) + '</h3>' +
          '<div class="player-artist">' + esc(snap.track.artist || 'Unknown artist') + '</div>' +
          '<div class="player-album">' + esc(snap.track.album || '') + '</div>' +
          '<div class="player-timeline">' +
            '<div class="timeline-track"><div class="timeline-fill" id="player-fill" style="width:' + pct.toFixed(2) + '%"></div></div>' +
            '<div class="timeline-times"><span id="player-current">' + esc(formatMs(pos)) + '</span>' +
            '<span id="player-duration">' + esc(formatMs(snap.durationMs)) + '</span></div>' +
          '</div>' +
          '<div class="player-controls">' +
            '<button class="transport focusable" type="button" data-action="prev-track" data-fk="player-prev" aria-label="Previous track">' + SN.icon('previous') + '</button>' +
            '<button class="transport focusable" type="button" data-action="seek-back" data-fk="player-back" aria-label="Back 10 seconds">' +
              SN.icon('arrowLeft') + '</button>' +
            '<button class="transport primary focusable" type="button" data-action="toggle-play" data-fk="player-toggle" data-autofocus aria-label="' +
              (snap.playing ? 'Pause' : 'Play') + '">' + SN.icon(snap.playing ? 'pause' : 'play') + '</button>' +
            '<button class="transport focusable" type="button" data-action="seek-forward" data-fk="player-forward" aria-label="Forward 10 seconds">' +
              SN.icon('arrowRight') + '</button>' +
            '<button class="transport focusable" type="button" data-action="next-track" data-fk="player-next" aria-label="Next track">' + SN.icon('next') + '</button>' +
          '</div>' +
          '<div class="player-volume">' +
            '<button class="transport focusable" type="button" data-action="volume-down" data-fk="player-vol-down" aria-label="Volume down">' + SN.icon('volumeLow') + '</button>' +
            '<div class="volume-track"><div class="volume-fill" id="player-volume-fill" style="width:' + Math.round(snap.volume * 100) + '%"></div></div>' +
            '<span id="player-volume-text">' + Math.round(snap.volume * 100) + '%</span>' +
            '<button class="transport focusable" type="button" data-action="volume-up" data-fk="player-vol-up" aria-label="Volume up">' + SN.icon('volume') + '</button>' +
          '</div>' +
          '<div class="player-note">Every button sends a real /control request to NCS-SMLauncher. The player reports its state back on the next two-second poll.</div>' +
        '</div>' +
      '</div>' +
      '</div>';
    applyOverlay('player', html, state.overlay === 'player' ? overlayFocusKey() : 'player-toggle');
  }

  function updatePlayerProgress() {
    if (state.overlay !== 'player') return;
    var snap = SN.Ncs.snapshot();
    if (!snap || !snap.track) return;
    var pos = Math.min(SN.Ncs.positionAt(Date.now()), snap.durationMs || 0);
    var pct = snap.durationMs > 0 ? Math.min(100, (pos / snap.durationMs) * 100) : 0;
    var fill = $('player-fill');
    var current = $('player-current');
    var duration = $('player-duration');
    var volFill = $('player-volume-fill');
    var volText = $('player-volume-text');
    if (fill) fill.style.width = pct.toFixed(2) + '%';
    if (current) current.textContent = formatMs(pos);
    if (duration) duration.textContent = formatMs(snap.durationMs);
    if (volFill) volFill.style.width = Math.round(snap.volume * 100) + '%';
    if (volText) volText.textContent = Math.round(snap.volume * 100) + '%';
  }

  /* ─────────────────────────────────────────────────────────── settings */

  function syncDrafts() {
    var loc = SN.Store.get('location');
    state.draft.cityQuery = '';
    state.draft.searchResults = [];
    state.draft.searching = false;
    state.draft.searchError = '';
    state.draft.searchMessage = '';
    state.draft.ncsAddress = SN.Store.get('ncsBaseUrl') || '';
    state.draft.manualPlace = loc && loc.name ? loc.name : '';
    state.draft.manualLat = loc ? String(loc.lat) : '';
    state.draft.manualLon = loc ? String(loc.lon) : '';
    state.draft.error = '';
    state.draft.ncsError = '';
  }

  function openSettings(section) {
    if (!flag('settings')) {
      toast('Settings are not included in this build.');
      return;
    }
    if (state.overlay) return;
    state.settingsSection = section || 'display';
    syncDrafts();
    var key = section === 'weather' ? 'city-search-input'
      : (flag('themePicker') ? 'settings-theme' : 'settings-clock');
    renderSettings(key);
  }

  function renderSettings(focusKey) {
    var loc = SN.Store.get('location');
    var storage = SN.Store.storageAvailable();
    var showWeather = flag('weather');
    var showMusic = flag('music') && flag('ncsPlayer');
    var showTheme = flag('themePicker');

    var sectionDisplay = '<div class="settings-section">' +
      '<h3>Display</h3>' +
      (showTheme
        ? '<button class="setting-row focusable" type="button" data-action="cycle-theme" data-fk="settings-theme" data-autofocus>' +
          '<span><span class="setting-label">Theme</span><br><span class="setting-hint">Pinned colour scheme</span></span>' +
          '<span class="setting-value">' + esc(themeLabel(SN.Store.get('theme'))) + '</span></button>'
        : '') +
      '<button class="setting-row focusable" type="button" data-action="toggle-clock" data-fk="settings-clock"' +
        (!showTheme ? ' data-autofocus' : '') + '>' +
        '<span><span class="setting-label">Clock</span><br><span class="setting-hint">Big clock on the home page</span></span>' +
        '<span class="setting-value">' + (SN.Store.get('use24h') !== false ? '24-hour' : '12-hour') + '</span></button>' +
      '<p>Theme and clock are stored on this TV. ' +
        (storage ? 'Storage is available.' : 'Storage is unavailable; changes last for this session only.') +
      '</p>' +
      '</div>';

    var sectionWeather = '';
    if (showWeather) {
      var weatherStatus = '';
      if (!loc) {
        weatherStatus = '<div class="location-state">No location set. Weather stays blank until you choose a place.</div>';
      } else {
        weatherStatus = '<div class="location-state"><strong>' + esc(locationLabel(loc)) + '</strong><br>' +
          esc(coordinateLabel(loc.lat, loc.lon)) + ' · location set by hand' +
          (SN.Weather.status() === 'stale' ? '<br><span style="color:#f6c56b">Last reading is offline/stale.</span>' : '') +
          '</div>';
      }

      var resultHtml = '';
      if (state.draft.searching) {
        resultHtml = '<div class="setting-hint">Searching Open-Meteo geocoding…</div>';
      } else if (state.draft.searchError) {
        resultHtml = '<div class="setting-hint" style="color:#ff9a92">' + esc(state.draft.searchError) + '</div>';
      } else if (state.draft.searchMessage) {
        resultHtml = '<div class="setting-hint">' + esc(state.draft.searchMessage) + '</div>';
      } else if (state.draft.searchResults.length) {
        resultHtml = '<div class="city-results">';
        for (var r = 0; r < state.draft.searchResults.length; r++) {
          var city = state.draft.searchResults[r];
          resultHtml += '<button class="city-result focusable" type="button" data-action="choose-city" ' +
            'data-lat="' + esc(city.lat) + '" data-lon="' + esc(city.lon) + '" data-name="' + esc(city.name) + '" ' +
            'data-fk="city-result-' + r + '"><span>' + esc(city.name) + '</span>' +
            '<span>' + esc(coordinateLabel(city.lat, city.lon)) + '</span></button>';
        }
        resultHtml += '</div>';
      }

      var presets = '<div class="mini-actions">';
      for (var p = 0; p < PRESET_CITIES.length; p++) {
        presets += '<button class="chip-button focusable" type="button" data-action="preset-city" ' +
          'data-index="' + p + '" data-fk="preset-city-' + p + '">' + esc(PRESET_CITIES[p].name.split(',')[0]) + '</button>';
      }
      presets += '</div>';

      sectionWeather = '<div class="settings-section full">' +
        '<h3>Weather location</h3>' +
        weatherStatus +
        '<label class="field-label" for="city-search-input">Search for a city</label>' +
        '<div class="field-row">' +
          '<input id="city-search-input" class="setting-field" type="text" autocomplete="off" spellcheck="false" ' +
            'placeholder="Da Nang" data-draft="cityQuery" data-enter-target="city-search-button" data-fk="city-search-input" ' +
            'value="' + esc(state.draft.cityQuery) + '">' +
          '<button id="city-search-button" class="secondary-button focusable" type="button" data-action="search-city" data-fk="city-search-button">Search</button>' +
        '</div>' +
        resultHtml +
        '<div class="field-label">Quick choices</div>' + presets +
        '<div class="field-label">Or enter coordinates by hand</div>' +
        '<div class="field-grid">' +
          '<div><label class="field-label" for="manual-place">Place name</label>' +
            '<input id="manual-place" class="setting-field" type="text" autocomplete="off" data-draft="manualPlace" data-enter-target="save-location" ' +
              'value="' + esc(state.draft.manualPlace) + '" placeholder="Home"></div>' +
          '<div><label class="field-label" for="manual-lat">Latitude</label>' +
            '<input id="manual-lat" class="setting-field" type="text" inputmode="decimal" data-draft="manualLat" data-enter-target="save-location" ' +
              'value="' + esc(state.draft.manualLat) + '" placeholder="16.0544"></div>' +
          '<div><label class="field-label" for="manual-lon">Longitude</label>' +
            '<input id="manual-lon" class="setting-field" type="text" inputmode="decimal" data-draft="manualLon" data-enter-target="save-location" ' +
              'value="' + esc(state.draft.manualLon) + '" placeholder="108.2022"></div>' +
        '</div>' +
        '<div class="mini-actions">' +
          '<button id="save-location" class="primary-button focusable" type="button" data-action="save-location" data-fk="save-location">Save coordinates</button>' +
          (loc ? '<button class="secondary-button focusable" type="button" data-action="clear-location" data-fk="clear-location">Clear location</button>' : '') +
        '</div>' +
        (state.draft.error ? '<div class="setting-hint" style="color:#ff9a92">' + esc(state.draft.error) + '</div>' : '') +
        '<p>This TV has no automatic location service in this port. A city search result or your coordinates are stored as “set by hand”; the weather page says the same thing.</p>' +
        '</div>';
    }

    var sectionMusic = '';
    if (showMusic) {
      sectionMusic = '<div class="settings-section">' +
        '<h3>Music player</h3>' +
        '<div class="location-state">' + (SN.Ncs.baseUrl()
          ? '<strong>' + esc(SN.Ncs.baseUrl()) + '</strong><br>' + (SN.Ncs.connected() ? 'Connected' : 'Not connected') +
            (SN.Ncs.error() ? ' · ' + esc(SN.Ncs.error()) : '')
          : 'No player address is configured.') + '</div>' +
        '<label class="field-label" for="settings-ncs">NCS-SMLauncher address</label>' +
        '<input id="settings-ncs" class="setting-field" type="text" inputmode="url" autocomplete="off" spellcheck="false" ' +
          'data-draft="ncsAddress" data-enter-target="save-ncs" data-fk="settings-ncs" ' +
          'value="' + esc(state.draft.ncsAddress) + '" placeholder="http://192.168.1.123:8737">' +
        '<div class="mini-actions">' +
          '<button id="save-ncs" class="primary-button focusable" type="button" data-action="save-ncs" data-fk="save-ncs">Save address</button>' +
          (SN.Ncs.configured()
            ? '<button class="secondary-button focusable" type="button" data-action="refresh-ncs" data-fk="settings-refresh-ncs">Check now</button>'
            : '') +
        '</div>' +
        (state.draft.ncsError ? '<div class="setting-hint" style="color:#ff9a92">' + esc(state.draft.ncsError) + '</div>' : '') +
        '<p>The TV sends remote commands only. NCS-SMLauncher owns the library and the audio. The app polls <code>/state</code> every 2 seconds while the Music page is open; it stops when you leave that page.</p>' +
        '</div>';
    }

    var aboutWeather = flag('weather')
      ? '<div><strong>Weather</strong> · Open-Meteo (CC BY 4.0), fetched by location and refreshed hourly.</div>'
      : '';
    var aboutMusic = (flag('music') && flag('ncsPlayer'))
      ? '<div><strong>Music</strong> · NCS-SMLauncher remote protocol, polling only. Audio is never played by this TV.</div>'
      : '';
    var sectionAbout = '<div class="settings-section full">' +
      '<h3>About this TV build</h3>' +
      '<div class="about-list">' +
        '<div><strong>Build</strong> · ' + esc(BUILD_NAME) + (CONFIG_MISSING ? ' · feature file missing' : '') + '</div>' +
        '<div><strong>Pages</strong> · ' + esc(PAGES.map(function (p) { return PAGE_LABEL[p]; }).join(', ')) + '</div>' +
        aboutWeather +
        aboutMusic +
        '<div><strong>Photo</strong> · “' + esc(PHOTO.title) + '” by ' + esc(PHOTO.author) + ', ' + esc(PHOTO.license) + '.</div>' +
        '<div><strong>Photo source</strong> · ' + esc(PHOTO.sourceUrl) + '</div>' +
        '<div><strong>No Google assets</strong> · This is an independent launcher. No Google logos, artwork or Material Symbols are included. “Nest” is a trademark of Google LLC; this project is not affiliated with Google.</div>' +
        '<div><strong>Built with OpenCode</strong> · Author: Giathinh1234.</div>' +
      '</div>' +
      '</div>';

    var html = '<div class="sheet settings-sheet" role="document">' +
      '<div class="sheet-head">' +
        '<div><h2 class="sheet-title">Settings</h2>' +
        '<p class="sheet-sub">Remote-first controls. Everything here is local to this TV.</p></div>' +
        '<button class="icon-button focusable" type="button" data-action="close-settings" data-fk="settings-close" aria-label="Close settings">' + SN.icon('close') + '</button>' +
      '</div>' +
      '<div class="sheet-body"><div class="settings-grid">' +
        sectionDisplay + sectionWeather + sectionMusic + sectionAbout +
      '</div></div></div>';

    applyOverlay('settings', html, focusKey || overlayFocusKey());
  }

  function focusKeyOf(el) {
    if (!el || !el.getAttribute) return '';
    return el.getAttribute('data-fk') || el.id || '';
  }

  function applyOverlay(type, html, focusKey) {
    var opening = !state.overlay;
    if (opening) {
      state.overlay = type;
      state.returnFocus = document.activeElement;
      state.returnFocusKey = focusKeyOf(document.activeElement);
      pagesEl.setAttribute('aria-hidden', 'true');
      chromeEl.setAttribute('aria-hidden', 'true');
    }
    overlayEl.hidden = false;
    overlayEl.innerHTML = html;
    if (opening) {
      requestAnimationFrame(function () {
        overlayEl.classList.add('visible');
        focusOverlay(focusKey || null);
      });
    } else {
      focusOverlay(focusKey || null);
    }
  }

  function closeOverlay() {
    if (!state.overlay) return;
    var restore = state.returnFocus;
    var restoreKey = state.returnFocusKey;
    state.overlay = null;
    state.returnFocus = null;
    state.returnFocusKey = '';
    overlayEl.classList.remove('visible');
    setTimeout(function () {
      if (!state.overlay) {
        overlayEl.hidden = true;
        overlayEl.innerHTML = '';
      }
    }, 230);
    pagesEl.removeAttribute('aria-hidden');
    chromeEl.removeAttribute('aria-hidden');
    setTimeout(function () {
      if (restore && document.contains(restore) && !restore.disabled) {
        focusEl(restore, false);
        return;
      }
      // The page may have re-rendered while the overlay was open, so the old
      // DOM node is gone. Restore by the control's stable focus key instead.
      var byKey = restoreKey && document.querySelector('[data-fk="' + restoreKey + '"]');
      if (!byKey && restoreKey) byKey = document.getElementById(restoreKey);
      if (byKey && document.contains(byKey) && visible(byKey)) {
        focusEl(byKey, false);
        return;
      }
      focusPage();
    }, 40);
  }

  function focusOverlay(key) {
    if (!state.overlay) return;
    var target = key ? overlayEl.querySelector('[data-fk="' + key + '"]') : null;
    if (!target) target = firstVisible(focusableNodes(overlayEl));
    if (!target) target = overlayEl.querySelector('[data-autofocus]');
    if (target) focusEl(target, true);
  }

  function overlayFocusKey() {
    var el = document.activeElement;
    if (el && el.getAttribute) {
      var key = el.getAttribute('data-fk');
      if (key && overlayEl.contains(el)) return key;
    }
    return null;
  }

  /* ───────────────────────────────────────────────────────────── focus */

  function visible(el) {
    if (!el || el.disabled) return false;
    if (el.hidden) return false;
    var rect = el.getBoundingClientRect();
    if (rect.width < 1 || rect.height < 1) return false;
    var style = window.getComputedStyle ? window.getComputedStyle(el) : null;
    if (style && style.visibility === 'hidden') return false;
    if (style && style.display === 'none') return false;
    return true;
  }

  function firstVisible(nodes) {
    for (var i = 0; i < nodes.length; i++) {
      if (visible(nodes[i])) return nodes[i];
    }
    return null;
  }

  function focusableNodes(root) {
    return root.querySelectorAll('.focusable, input, textarea, select');
  }

  function pageFocusables() {
    var page = currentPageEl();
    var out = [];
    if (page) {
      var nodes = focusableNodes(page);
      for (var i = 0; i < nodes.length; i++) {
        if (visible(nodes[i])) out.push(nodes[i]);
      }
    }
    if (!settingsBtn.hidden && visible(settingsBtn)) out.push(settingsBtn);
    return out;
  }

  function overlayFocusables() {
    var nodes = focusableNodes(overlayEl);
    var out = [];
    for (var i = 0; i < nodes.length; i++) {
      if (visible(nodes[i])) out.push(nodes[i]);
    }
    return out;
  }

  function focusEl(el, scroll) {
    if (!el) return;
    try {
      el.focus();
    } catch (err) {
      try { el.focus(); } catch (err2) { return; }
    }
    if (scroll !== false && el.scrollIntoView) {
      try {
        el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      } catch (err) {
        try { el.scrollIntoView(false); } catch (err2) { /* nothing */ }
      }
    }
  }

  function restoreFocus(root, key) {
    if (!root || !key || state.overlay) return false;
    var target = root.querySelector('[data-fk="' + key + '"]');
    if (!target || !visible(target)) return false;
    focusEl(target, false);
    return true;
  }

  function movePageFocus(delta) {
    var list = pageFocusables();
    if (!list.length) return;
    var idx = list.indexOf(document.activeElement);
    if (idx < 0) idx = delta > 0 ? -1 : 0;
    idx = (idx + delta + list.length) % list.length;
    focusEl(list[idx], true);
  }

  function moveOverlayVertical(delta) {
    if (state.overlay !== 'settings') {
      moveOverlayFocus(delta > 0 ? 'down' : 'up');
      return;
    }
    var list = overlayFocusables();
    if (!list.length) return;
    var idx = list.indexOf(document.activeElement);
    if (idx < 0) idx = delta > 0 ? -1 : 0;
    var next = idx + delta;
    if (next < 0 || next >= list.length) return;
    focusEl(list[next], true);
  }

  function moveOverlayFocus(direction) {
    var list = overlayFocusables();
    if (!list.length) return;
    var current = document.activeElement;
    if (list.indexOf(current) < 0) {
      focusEl(list[0], true);
      return;
    }
    var cr = current.getBoundingClientRect();
    var cx = cr.left + cr.width / 2;
    var cy = cr.top + cr.height / 2;
    var best = null;
    var bestScore = Infinity;
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (el === current) continue;
      var r = el.getBoundingClientRect();
      var x = r.left + r.width / 2;
      var y = r.top + r.height / 2;
      var dx = x - cx;
      var dy = y - cy;
      var primary;
      var orth;
      if (direction === 'left') {
        if (dx > -4) continue;
        primary = -dx;
        orth = Math.abs(dy);
      } else if (direction === 'right') {
        if (dx < 4) continue;
        primary = dx;
        orth = Math.abs(dy);
      } else if (direction === 'up') {
        if (dy > -4) continue;
        primary = -dy;
        orth = Math.abs(dx);
      } else {
        if (dy < 4) continue;
        primary = dy;
        orth = Math.abs(dx);
      }
      var score = primary + orth * 1.35;
      if (!(direction === 'up' || direction === 'down')) {
        // Keep horizontal moves within the same row when possible.
        if (Math.abs(dy) > cr.height * 0.7) score += orth * 1.4;
      }
      if (score < bestScore) {
        bestScore = score;
        best = el;
      }
    }
    if (best) focusEl(best, true);
  }

  function activateFocused() {
    var el = document.activeElement;
    if (el && el.classList && el.classList.contains('focusable') && !el.disabled) {
      el.click();
      return true;
    }
    var list = state.overlay ? overlayFocusables() : pageFocusables();
    if (list.length) {
      focusEl(list[0], true);
      // Do not activate the first control just because focus was missing; the
      // first OK press should establish focus, the second should act.
      return true;
    }
    return false;
  }

  function overlayFocusDirection(direction) {
    moveOverlayFocus(direction);
  }

  /* ────────────────────────────────────────────────────────── actions */

  function handleAction(action, el) {
    switch (action) {
      case 'open-settings':
        openSettings();
        break;
      case 'open-settings-weather':
        openSettings('weather');
        break;
      case 'close-settings':
      case 'close-player':
        closeOverlay();
        break;
      case 'cycle-theme':
        cycleTheme();
        break;
      case 'toggle-clock':
        SN.Store.update({ use24h: SN.Store.get('use24h') === false });
        toast(SN.Store.get('use24h') !== false ? 'Clock set to 24-hour.' : 'Clock set to 12-hour.');
        break;
      case 'go-weather':
        showPageById('weather');
        break;
      case 'go-music':
        showPageById('music');
        break;
      case 'open-player':
        openPlayer();
        break;
      case 'play-track':
        playTrack(el.getAttribute('data-id') || '');
        break;
      case 'toggle-play':
        togglePlay();
        break;
      case 'next-track':
        sendControl('next');
        break;
      case 'prev-track':
        sendControl('previous');
        break;
      case 'seek-back':
        seekBy(-10000);
        break;
      case 'seek-forward':
        seekBy(10000);
        break;
      case 'volume-down':
        changeVolume(-0.1);
        break;
      case 'volume-up':
        changeVolume(0.1);
        break;
      case 'connect-ncs':
        connectFromCard();
        break;
      case 'refresh-ncs':
        refreshNcs();
        break;
      case 'save-ncs':
        saveNcs();
        break;
      case 'search-city':
        searchCity();
        break;
      case 'choose-city':
        chooseCity(el);
        break;
      case 'preset-city':
        presetCity(Number(el.getAttribute('data-index')));
        break;
      case 'save-location':
        saveManualLocation();
        break;
      case 'clear-location':
        clearLocation();
        break;
      case 'refresh-weather':
        if (!SN.Weather.location()) openSettings('weather');
        else {
          SN.Weather.refresh(true);
          toast('Refreshing weather…');
        }
        break;
      default:
        break;
    }
  }

  function cycleTheme() {
    if (!flag('themePicker')) {
      toast('Theme switching is not included in this build.');
      return;
    }
    var themes = SN.Store.themes;
    var i = themes.indexOf(SN.Store.get('theme'));
    var next = themes[(i + 1) % themes.length];
    SN.Store.update({ theme: next });
    toast('Theme: ' + themeLabel(next));
  }

  function playTrack(id) {
    if (!SN.Ncs.configured()) {
      toast('No player address is configured.');
      return;
    }
    if (!id) toast('This track has no id; asked the player to resume.');
    SN.Ncs.control('play', null, id || null, function (err) {
      if (err) toast(err.message || 'The player did not acknowledge that.');
    });
  }

  function togglePlay() {
    var snap = SN.Ncs.snapshot();
    if (!snap) return;
    sendControl(snap.playing ? 'pause' : 'play');
  }

  function sendControl(action) {
    if (!SN.Ncs.configured()) {
      toast('No player address is configured.');
      return;
    }
    SN.Ncs.control(action, null, null, function (err) {
      if (err) toast(err.message || 'The player did not acknowledge that.');
    });
  }

  function seekBy(deltaMs) {
    var snap = SN.Ncs.snapshot();
    if (!snap) return;
    var next = SN.Ncs.positionAt(Date.now()) + deltaMs;
    if (next < 0) next = 0;
    if (snap.durationMs > 0 && next > snap.durationMs) next = snap.durationMs;
    SN.Ncs.control('seek', Math.round(next), null, function (err) {
      if (err) toast(err.message || 'The player did not acknowledge that.');
    });
  }

  function changeVolume(delta) {
    var snap = SN.Ncs.snapshot();
    if (!snap) return;
    var next = Math.max(0, Math.min(1, snap.volume + delta));
    SN.Ncs.control('volume', Math.round(next * 100) / 100, null, function (err) {
      if (err) toast(err.message || 'The player did not acknowledge that.');
    });
  }

  function validBaseUrl(url) {
    // Require a host and reject whitespace or a half-typed path. A bare
    // hostname such as "tv.local" is fine; "not a url" is not.
    return /^https?:\/\/[^\s\/]+(\/[^\s]*)?$/i.test(url);
  }

  function connectFromCard() {
    var input = $('connect-ncs-input');
    var raw = input ? input.value : SN.Store.get('ncsBaseUrl');
    var url = SN.Ncs.normalize(raw);
    if (url && !validBaseUrl(url)) {
      toast('Use an address like http://192.168.1.123:8737');
      return;
    }
    commitNcsUrl(url);
    toast(url ? 'Connecting to ' + url + '…' : 'Player address cleared.');
  }

  function saveNcs() {
    var url = SN.Ncs.normalize(state.draft.ncsAddress);
    if (url && !validBaseUrl(url)) {
      state.draft.ncsError = 'Use an address like http://192.168.1.123:8737';
      renderSettings('save-ncs');
      return;
    }
    state.draft.ncsError = '';
    commitNcsUrl(url);
    toast(url ? 'Player address saved.' : 'Player address cleared.');
    renderSettings('save-ncs');
  }

  function commitNcsUrl(url) {
    SN.Store.update({ ncsBaseUrl: url });
    SN.Ncs.configure(url, false);
    state.library = [];
    state.libraryFor = '';
    state.libraryVersion++;
    if (currentPageName() === 'music') {
      if (url) {
        SN.Ncs.start();
        ensureLibrary();
      } else {
        SN.Ncs.stop();
      }
      renderMusic(true);
    }
  }

  function refreshNcs() {
    if (!SN.Ncs.configured()) {
      toast('No player address is configured.');
      return;
    }
    SN.Ncs.refresh();
    toast('Checking ' + SN.Ncs.baseUrl() + '…');
  }

  function searchCity() {
    var q = state.draft.cityQuery.trim();
    if (!q) {
      state.draft.searchError = 'Type a city name first.';
      renderSettings('city-search-input');
      return;
    }
    state.draft.searching = true;
    state.draft.searchError = '';
    state.draft.searchMessage = '';
    state.draft.searchResults = [];
    renderSettings('city-search-input');

    SN.Weather.geocode(q, function (err, results) {
      state.draft.searching = false;
      if (err) {
        state.draft.searchError = err.message || 'City search failed.';
        renderSettings('city-search-input');
        return;
      }
      if (!results.length) {
        state.draft.searchMessage = 'No cities found for “' + q + '”. Try a different spelling.';
        renderSettings('city-search-input');
        return;
      }
      state.draft.searchResults = results;
      renderSettings('city-result-0');
    });
  }

  function chooseCity(el) {
    var lat = Number(el.getAttribute('data-lat'));
    var lon = Number(el.getAttribute('data-lon'));
    var name = el.getAttribute('data-name') || '';
    commitLocation({ lat: lat, lon: lon, name: name, source: 'manual' });
    state.draft.cityQuery = '';
    state.draft.searchResults = [];
    state.draft.searchMessage = 'Location set to ' + name + '.';
    renderSettings('city-search-input');
  }

  function presetCity(index) {
    var city = PRESET_CITIES[index];
    if (!city) return;
    commitLocation({ lat: city.lat, lon: city.lon, name: city.name, source: 'manual' });
    state.draft.searchResults = [];
    state.draft.searchMessage = 'Location set to ' + city.name + '.';
    renderSettings('preset-city-' + index);
  }

  function saveManualLocation() {
    var lat = parseFloat(String(state.draft.manualLat).replace(',', '.'));
    var lon = parseFloat(String(state.draft.manualLon).replace(',', '.'));
    if (!isFinite(lat) || !isFinite(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      state.draft.error = 'Enter a latitude between -90 and 90 and a longitude between -180 and 180.';
      renderSettings('save-location');
      return;
    }
    var name = String(state.draft.manualPlace || '').trim();
    if (!name) name = coordinateLabel(lat, lon);
    state.draft.error = '';
    commitLocation({ lat: lat, lon: lon, name: name, source: 'manual' });
    state.draft.manualLat = String(lat);
    state.draft.manualLon = String(lon);
    state.draft.manualPlace = name;
    renderSettings('save-location');
  }

  function commitLocation(loc) {
    SN.Store.update({ location: loc });
    SN.Weather.configure(loc);
    toast('Weather location: ' + locationLabel(loc));
  }

  function clearLocation() {
    SN.Store.update({ location: null });
    SN.Weather.configure(null);
    state.draft.manualPlace = '';
    state.draft.manualLat = '';
    state.draft.manualLon = '';
    toast('Weather location cleared.');
    renderSettings('city-search-input');
  }

  /* ──────────────────────────────────────────────────────────── keys */

  function keyIsMediaPlayPause(k) {
    return k === 10252 || k === 179;
  }

  function musicContext() {
    return currentPageName() === 'music' || state.overlay === 'player';
  }

  function handleMediaKey(k) {
    if (!musicContext() || state.overlay === 'settings') return false;
    if (k === 415 || (k === 10232)) {
      sendControl('play');
      return true;
    }
    if (k === 19 || k === 10233) {
      sendControl('pause');
      return true;
    }
    if (keyIsMediaPlayPause(k)) {
      togglePlay();
      return true;
    }
    if (k === 412) {
      seekBy(-10000);
      return true;
    }
    if (k === 417) {
      seekBy(10000);
      return true;
    }
    if (k === 413) {
      // NCS has no stop verb. Be explicit rather than pretending.
      sendControl('pause');
      toast('NCS has no stop command; paused the player instead.');
      return true;
    }
    return false;
  }

  function onKeyDown(e) {
    var key = e.keyCode || e.which;
    var editing = isEditing();
    var overlayOpen = !!state.overlay;

    if (handleMediaKey(key)) {
      e.preventDefault();
      flashHint();
      return;
    }

    if (key === 10009 || key === 27) {
      e.preventDefault();
      if (editing) {
        finishEditing();
        flashHint();
        return;
      }
      handleBack();
      return;
    }

    if (overlayOpen) {
      if (editing) {
        if (key === 38 || key === 40) {
          e.preventDefault();
          moveOverlayVertical(key === 38 ? -1 : 1);
          flashHint();
          return;
        }
        if (key === 13 || key === 65385) {
          var targetId = document.activeElement.getAttribute('data-enter-target');
          if (targetId) {
            var target = $(targetId);
            if (target) {
              e.preventDefault();
              target.click();
              return;
            }
          }
          return;
        }
        // Left/right stay with the text caret while typing.
        return;
      }
      if (key === 13 || key === 65385 || key === 32) {
        e.preventDefault();
        activateFocused();
        return;
      }
      if (key === 37) {
        e.preventDefault();
        moveOverlayFocus('left');
        flashHint();
        return;
      }
      if (key === 39) {
        e.preventDefault();
        moveOverlayFocus('right');
        flashHint();
        return;
      }
      if (key === 38) {
        e.preventDefault();
        moveOverlayVertical(-1);
        flashHint();
        return;
      }
      if (key === 40) {
        e.preventDefault();
        moveOverlayVertical(1);
        flashHint();
        return;
      }
      return;
    }

    if (editing) {
      if (key === 38 || key === 40) {
        e.preventDefault();
        movePageFocus(key === 38 ? -1 : 1);
        flashHint();
        return;
      }
      if (key === 13 || key === 65385) {
        var cardTarget = document.activeElement.getAttribute('data-enter-target');
        if (cardTarget) {
          var cardButton = $(cardTarget);
          if (cardButton) {
            e.preventDefault();
            cardButton.click();
            return;
          }
        }
        return;
      }
      // Left/right are part of editing, not page changes.
      return;
    }

    if (key === 37) {
      e.preventDefault();
      showPage(state.page - 1);
      return;
    }
    if (key === 39) {
      e.preventDefault();
      showPage(state.page + 1);
      return;
    }
    if (key === 38) {
      e.preventDefault();
      movePageFocus(-1);
      flashHint();
      return;
    }
    if (key === 40) {
      e.preventDefault();
      movePageFocus(1);
      flashHint();
      return;
    }
    if (key === 13 || key === 65385 || key === 32) {
      e.preventDefault();
      activateFocused();
      flashHint();
      return;
    }
  }

  function handleBack() {
    var now = Date.now();
    if (now - state.lastBackAt < 260) return;
    state.lastBackAt = now;

    if (state.overlay) {
      closeOverlay();
      return;
    }
    if (currentPageName() !== 'home') {
      showPage(0);
      return;
    }
    // Home is the launcher's own home. A second Back within the window exits.
    if (now - state.exitArmedAt < 2600) {
      exitLauncher();
      return;
    }
    state.exitArmedAt = now;
    toast('Press Back again to close the launcher.');
  }

  function exitLauncher() {
    try {
      if (window.tizen && tizen.application && tizen.application.getCurrentApplication) {
        tizen.application.getCurrentApplication().exit();
        return;
      }
    } catch (err) { /* fall through */ }
    toast('This browser tab cannot close itself.');
  }

  /* ───────────────────────────────────────────────────────────── misc */

  function toast(message, ms) {
    if (!toastEl) return;
    toastEl.textContent = message;
    toastEl.classList.add('show');
    if (state.toastTimer) clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(function () {
      toastEl.classList.remove('show');
      state.toastTimer = null;
    }, ms || 3200);
  }

  function flashHint() {
    if (!hintEl) return;
    hintEl.classList.remove('hide');
    if (state.hintTimer) clearTimeout(state.hintTimer);
    state.hintTimer = setTimeout(function () {
      hintEl.classList.add('hide');
    }, 4500);
  }

  function tick() {
    updateHome(false);
    if (state.overlay === 'player') updatePlayerProgress();
    else if (currentPageName() === 'music') updateMusicProgress();
  }

  function bindEvents() {
    window.addEventListener('resize', applyScale, false);
    window.addEventListener('keydown', onKeyDown, true);

    document.addEventListener('tizenhwkey', function (e) {
      if (e.keyName === 'back') {
        try { e.preventDefault(); } catch (err) { /* older Tizen */ }
        if (isEditing()) {
          finishEditing();
        } else {
          handleBack();
        }
      }
    }, false);

    app.addEventListener('click', function (e) {
      if (e.target === overlayEl) {
        closeOverlay();
        return;
      }
      var el = e.target;
      while (el && el !== app && !el.getAttribute) el = el.parentNode;
      var action = el && el.getAttribute ? el.getAttribute('data-action') : null;
      if (!action) return;
      e.preventDefault();
      handleAction(action, el);
    }, false);

    overlayEl.addEventListener('input', function (e) {
      var field = e.target.getAttribute && e.target.getAttribute('data-draft');
      if (field && Object.prototype.hasOwnProperty.call(state.draft, field)) {
        state.draft[field] = e.target.value;
        if (field === 'cityQuery' || field === 'manualLat' || field === 'manualLon') {
          state.draft.error = '';
        }
        if (field === 'ncsAddress') state.draft.ncsError = '';
      }
    }, false);

    document.addEventListener('visibilitychange', function () {
      if (document.hidden) {
        SN.Ncs.stop();
      } else if (currentPageName() === 'music' && SN.Ncs.configured()) {
        SN.Ncs.start();
      }
    }, false);

    window.addEventListener('beforeunload', function () {
      SN.Ncs.stop();
    }, false);
  }

  function registerTvKeys() {
    if (!window.tizen || !tizen.tvinputdevice) return;
    var keys = ['MediaPlay', 'MediaPause', 'MediaPlayPause', 'MediaStop',
      'MediaRewind', 'MediaFastForward', 'MediaTrackPrevious', 'MediaTrackNext'];
    try {
      if (tizen.tvinputdevice.registerKeyBatch) {
        tizen.tvinputdevice.registerKeyBatch(keys);
      } else {
        for (var i = 0; i < keys.length; i++) {
          try { tizen.tvinputdevice.registerKey(keys[i]); } catch (err) { /* optional */ }
        }
      }
    } catch (err) {
      // Registration is only needed for the extra media keys. Arrows, OK and
      // Back work without it, so a failure must not stop the launcher.
    }
  }

  function connectServices() {
    SN.Store.onChange(function () {
      applyTheme();
      state.lastClockMinute = '';
      if (currentPageName() === 'home') updateHome(true);
      else if (currentPageName() === 'digest') renderDigest();
      else if (currentPageName() === 'weather') renderWeather();
      if (state.overlay === 'settings') renderSettings(overlayFocusKey() || 'settings-close');
    });

    SN.Weather.onChange(function () {
      updateHome(true);
      if (currentPageName() === 'digest') renderDigest();
      if (currentPageName() === 'weather') renderWeather();
    });

    SN.Ncs.onChange(function () {
      if (state.overlay === 'player') {
        var snap = SN.Ncs.snapshot();
        if (!snap || !snap.track) {
          closeOverlay();
          toast('The player stopped reporting a track.');
          return;
        }
        var psig = playerSignature();
        if (psig !== state.playerSig) {
          renderPlayer();
        } else {
          updatePlayerProgress();
        }
      }
      if (currentPageName() === 'music') {
        ensureLibrary();
        if (musicSignature() !== state.musicSig) renderMusic(false);
        else updateMusicProgress();
      }
      if (currentPageName() === 'digest') {
        var dsig = digestSignature();
        if (dsig !== state.digestSig) renderDigest();
      }
    });
  }

  function init() {
    app = $('app');
    pagesEl = $('pages');
    overlayEl = $('overlay');
    toastEl = $('toast');
    hintEl = $('hint');
    chromeEl = $('chrome');
    settingsBtn = $('settings-button');
    dotsEl = $('dots');
    bootEl = $('boot');

    settingsBtn.innerHTML = '<span class="chrome-icon">' + SN.icon('settings') + '</span>' +
      '<span class="chrome-label">Settings</span>';

    applyScale();
    applyTheme();
    buildPages();
    bindEvents();
    connectServices();
    registerTvKeys();

    SN.Weather.configure(SN.Store.get('location'));
    SN.Ncs.configure(SN.Store.get('ncsBaseUrl') || '', false);

    showPage(0, { force: true });
    updateHome(true);
    renderDots();

    setTimeout(function () {
      bootEl.classList.add('hidden');
      setTimeout(function () { bootEl.hidden = true; }, 600);
    }, 350);

    setTimeout(function () {
      hintEl.classList.add('hide');
    }, 11000);

    if (CONFIG_MISSING) {
      setTimeout(function () {
        toast('Feature file missing. Running the safe home-only shell.');
      }, 900);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, false);
  } else {
    init();
  }
})();
