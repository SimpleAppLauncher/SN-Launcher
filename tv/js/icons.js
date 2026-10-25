/* Inline SVG icons. They are drawn here rather than shipped as a font so the
   TV app does not depend on Google's Material Symbols artwork or licensing. */
(function () {
  'use strict';

  var ui = {
    settings: '<circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 .6 1.7 1.7 0 0 0-.4 1.1V21a2 2 0 1 1-4 0v-.09A1.7 1.7 0 0 0 8.6 19.4a1.7 1.7 0 0 0-1.88.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-.6-1 1.7 1.7 0 0 0-1.1-.4H3a2 2 0 1 1 0-4h.09A1.7 1.7 0 0 0 4.6 8.6a1.7 1.7 0 0 0-.34-1.88l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-.6 1.7 1.7 0 0 0 .4-1.1V3a2 2 0 1 1 4 0v.09a1.7 1.7 0 0 0 1 1.51 1.7 1.7 0 0 0 1.88-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.4 9c.14.38.36.72.65 1 .29.27.66.4 1.05.4H21a2 2 0 1 1 0 4h-.09A1.7 1.7 0 0 0 19.4 15Z"/>',
    close: '<path d="M18 6 6 18M6 6l12 12"/>',
    refresh: '<path d="M20 11a8.1 8.1 0 0 0-15.5-2M4 4v5h5M4 13a8.1 8.1 0 0 0 15.5 2M20 20v-5h-5"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.4-3.4"/>',
    play: '<path d="M8 5.5v13l11-6.5-11-6.5Z" fill="currentColor" stroke="none"/>',
    pause: '<path d="M8 5h3v14H8zM14 5h3v14h-3z" fill="currentColor" stroke="none"/>',
    previous: '<path d="M18 6 9 12l9 6V6Z" fill="currentColor" stroke="none"/><path d="M6 5v14" stroke-width="2.2"/>',
    next: '<path d="M6 6l9 6-9 6V6Z" fill="currentColor" stroke="none"/><path d="M18 5v14" stroke-width="2.2"/>',
    music: '<path d="M9 18V5l10-2v13"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="16" r="2.5"/>',
    weather: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/>',
    list: '<path d="M9 6h12M9 12h12M9 18h12"/><path d="M4 6h.01M4 12h.01M4 18h.01" stroke-width="2.6"/>',
    photo: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9" r="1.5"/><path d="m21 15-5-5L5 20"/>',
    palette: '<path d="M12 3a9 9 0 0 0 0 18h1.5a2 2 0 0 0 1.4-3.4 2 2 0 0 1 1.4-3.4H18a3 3 0 0 0 3-3A9 9 0 0 0 12 3Z"/><circle cx="7.5" cy="11.5" r="1" fill="currentColor"/><circle cx="10" cy="7.5" r="1" fill="currentColor"/><circle cx="15" cy="8" r="1" fill="currentColor"/>',
    volume: '<path d="M11 5 6 9H3v6h3l5 4V5Z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 6a9 9 0 0 1 0 12"/>',
    volumeLow: '<path d="M11 5 6 9H3v6h3l5 4V5Z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    location: '<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    alert: '<path d="M12 3 2 21h20L12 3Z"/><path d="M12 9v5M12 18h.01"/>',
    wifiOff: '<path d="m3 3 18 18"/><path d="M8.5 8.5A10.5 10.5 0 0 1 21 9M3 9a15.7 15.7 0 0 1 3-1.7M5.5 12.5a10 10 0 0 1 3.2-.7M8.5 16a5 5 0 0 1 6 0"/><circle cx="12" cy="20" r=".8" fill="currentColor"/>',
    chevronRight: '<path d="m9 5 7 7-7 7"/>',
    arrowLeft: '<path d="M19 12H5M11 18l-6-6 6-6"/>',
    arrowRight: '<path d="M5 12h14M13 6l6 6-6 6"/>'
  };

  var weather = {
    clear: '<circle cx="12" cy="12" r="5" fill="currentColor"/><g stroke="currentColor" stroke-linecap="round" stroke-width="1.7"><path d="M12 1.5v2.6M12 19.9v2.6M1.5 12h2.6M19.9 12h2.6M4.6 4.6l1.9 1.9M17.5 17.5l1.9 1.9M19.4 4.6l-1.9 1.9M6.5 17.5l-1.9 1.9"/></g>',
    partlyCloudy: '<circle cx="9" cy="9" r="4" fill="currentColor"/><g stroke="currentColor" stroke-linecap="round" stroke-width="1.5"><path d="M9 1.6v2M1.6 9h2M3.8 3.8l1.4 1.4M14.2 3.8l-1.4 1.4"/></g><path d="M7 19.5h10.2a3.6 3.6 0 0 0 .5-7.2A5.2 5.2 0 0 0 8 12.8a3.5 3.5 0 0 0-1 6.7Z" fill="currentColor"/>',
    cloudy: '<path d="M5 19.5h13a4 4 0 0 0 .4-8A6 6 0 0 0 7 12.2 3.7 3.7 0 0 0 5 19.5Z" fill="currentColor"/>',
    fog: '<path d="M5 15.5h13a3.7 3.7 0 0 0 .3-7.4A5.6 5.6 0 0 0 7 9.4 3.5 3.5 0 0 0 5 15.5Z" fill="currentColor" opacity=".8"/><g stroke="currentColor" stroke-linecap="round" stroke-width="1.6"><path d="M3.5 19h17M6 22h12"/></g>',
    drizzle: '<path d="M5 15.5h13a3.7 3.7 0 0 0 .3-7.4A5.6 5.6 0 0 0 7 9.4 3.5 3.5 0 0 0 5 15.5Z" fill="currentColor"/><g stroke="currentColor" stroke-linecap="round" stroke-width="1.7"><path d="M8 18.5v1.8M12 19v2.2M16 18.5v1.8"/></g>',
    rain: '<path d="M5 14.8h13a3.7 3.7 0 0 0 .3-7.4A5.6 5.6 0 0 0 7 8.7 3.5 3.5 0 0 0 5 14.8Z" fill="currentColor"/><g stroke="currentColor" stroke-linecap="round" stroke-width="1.8"><path d="m8 17-1.4 3.2M12.5 17l-1.4 3.2M17 17l-1.4 3.2"/></g>',
    snow: '<path d="M5 14.5h13a3.7 3.7 0 0 0 .3-7.4A5.6 5.6 0 0 0 7 8.4 3.5 3.5 0 0 0 5 14.5Z" fill="currentColor"/><g stroke="currentColor" stroke-linecap="round" stroke-width="1.5"><path d="M8 18v3M6.7 19.5l2.6-1.5M9.3 19.5 6.7 18M15.5 18v3M14.2 19.5l2.6-1.5M16.8 19.5l-2.6-1.5"/></g>',
    thunder: '<path d="M5 14.2h13a3.7 3.7 0 0 0 .3-7.4A5.6 5.6 0 0 0 7 8.1a3.5 3.5 0 0 0-2 6.1Z" fill="currentColor"/><path d="m12.2 13-3.4 5.1h2.7l-1.2 3.6 3.7-5.3h-2.6l.8-3.4Z" fill="currentColor"/>',
    unknown: '<path d="M5 16h13a3.7 3.7 0 0 0 .3-7.4A5.6 5.6 0 0 0 7 9.9 3.5 3.5 0 0 0 5 16Z" fill="currentColor"/><path d="M9.4 18.7h5.2" stroke="currentColor" stroke-linecap="round" stroke-width="1.7"/>'
  };

  function svg(body, className) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" ' +
      'aria-hidden="true" focusable="false" class="' + (className || '') + '">' +
      body + '</svg>';
  }

  SN.icon = function (name, className) {
    return svg(ui[name] || ui.alert, className);
  };

  SN.weatherIcon = function (condition, className) {
    var key = weather[condition] ? condition : 'unknown';
    return '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true" ' +
      'focusable="false" class="' + (className || '') + '">' +
      weather[key] + '</svg>';
  };
})();
