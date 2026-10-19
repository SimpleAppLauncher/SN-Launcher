import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/platform_bridge.dart';
import '../services/settings_store.dart';

/// A place, and how it was worked out.
@immutable
class GeoPlace {
  const GeoPlace({
    required this.latitude,
    required this.longitude,
    this.name = '',
    this.source = 'unknown',
  });

  final double latitude;
  final double longitude;

  /// A human label — a city, or "Home" for a manually pinned location.
  final String name;

  /// Where the coordinates came from: `wifi`, `gps`, `ip`, `manual` or
  /// `cached`. Shown on the weather page, because a location that came from a
  /// network lookup is not as good as one that came from the device.
  final String source;

  /// True when the fix is a rough guess rather than the device's own
  /// position. The weather page says so.
  bool get isApproximate => source == 'ip';

  /// A label for the place, falling back to the coordinates when there is no
  /// name.
  String get displayName {
    if (name.isNotEmpty) return name;
    return '${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)}';
  }

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        'name': name,
        'source': source,
      };

  static GeoPlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lon = raw['lon'];
    if (lat is! num || lon is! num) return null;
    return GeoPlace(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      name: raw['name'] is String ? raw['name'] as String : '',
      source: raw['source'] is String ? raw['source'] as String : 'cached',
    );
  }
}

/// Works out where the device is.
///
/// Three sources, in order, and it says which one it used:
///
/// 1. **The device's own location.** The network provider first, which on a
///    device with WiFi is derived from the access points — fast, indoor, and
///    no view of the sky required. GPS second. This is the accurate path and
///    it needs the location permission.
/// 2. **A pinned location** the user set, which always wins.
/// 3. **An IP lookup.** Rough — city level, and wrong behind a VPN — but it
///    needs no permission at all, so the weather still works if the user says
///    no. It is labelled as approximate everywhere it appears.
///
/// The result is cached, because a launcher that asks the platform for a
/// location fix on every launch is a launcher that drains the battery and
/// pings the user for permission every morning.
class LocationService extends ChangeNotifier {
  LocationService(
    this._bridge,
    this._settings, {
    this.pinnedLatitude,
    this.pinnedLongitude,
    this.pinnedName = '',
  });

  final PlatformBridge _bridge;
  final SettingsStore _settings;

  /// A location pinned at build time, with `--dart-define=NEST_LAT=…`.
  ///
  /// A build-time pin has to beat the automatic one. It was set deliberately,
  /// by whoever built the APK, and letting the device's own location quietly
  /// override it would make the flag a lie.
  final double? pinnedLatitude;
  final double? pinnedLongitude;
  final String pinnedName;

  GeoPlace? _place;
  bool _resolving = false;
  String _lastError = '';

  GeoPlace? get place => _place;
  bool get resolving => _resolving;
  String get lastError => _lastError;

  /// Resolves the location, or returns null.
  ///
  /// [askPermission] is false when the user has already declined — asking
  /// again on every launch is exactly the behaviour people hate.
  /// Sets the resolved place by hand and tells listeners.
  ///
  /// For tests and screenshot capture, in the same spirit as
  /// [ClockService.overrideForTesting] and [ShellController.setPaletteForTest].
  ///
  /// This exists because the alternative is untestable: `LocationService` needs
  /// a `PlatformBridge`, which is a `MethodChannel`, so a widget test cannot
  /// make one resolve — and the bug this was added for was precisely that a
  /// resolved location did not reach the screen.
  @visibleForTesting
  void setPlaceForTesting(GeoPlace? place, {String error = ''}) {
    _place = place;
    // Settled, not in flight. Without this the page keeps rendering
    // "Working out where this is…" over a place that has already arrived,
    // because `resolve()` left the flag set while it was waiting on a
    // MethodChannel the test has no handler for.
    _resolving = false;
    _lastError = error;
    notifyListeners();
  }

  Future<GeoPlace?> resolve({bool askPermission = true}) async {
    if (_resolving) return _place;
    _resolving = true;
    notifyListeners();
    try {
      // A pinned location always wins. It was set deliberately.
      final pinned = await _pinnedPlace();
      if (pinned != null) {
        _place = pinned;
        _lastError = '';
        return _place;
      }

      final cached = _cachedPlace();
      if (cached != null) {
        _place = cached;
        return _place;
      }

      final device = await _devicePlace(askPermission: askPermission);
      debugPrint('SNLOC device place -> $device (ask=$askPermission)');
      if (device != null) {
        await _cache(device);
        _place = device;
        _lastError = '';
        return _place;
      }

      debugPrint('SNLOC no device place; falling back to IP');
      final ip = await _ipPlace();
      debugPrint('SNLOC ip place -> $ip');
      if (ip != null) {
        await _cache(ip);
        _place = ip;
        _lastError = '';
        return _place;
      }

      _lastError = 'Could not work out where this is.';
      return null;
    } finally {
      _resolving = false;
      notifyListeners();
    }
  }

  /// A location the user pinned by hand.
  Future<GeoPlace?> _pinnedPlace() async {
    // A build-time pin wins over everything.
    if (pinnedLatitude != null && pinnedLongitude != null) {
      return GeoPlace(
        latitude: pinnedLatitude!,
        longitude: pinnedLongitude!,
        name: pinnedName,
        source: 'manual',
      );
    }
    final lat = _settings.get(SettingKeys.latitude);
    final lon = _settings.get(SettingKeys.longitude);
    if (lat == null || lon == null) return null;
    final la = double.tryParse(lat);
    final lo = double.tryParse(lon);
    if (la == null || lo == null) return null;
    return GeoPlace(
      latitude: la,
      longitude: lo,
      name: _settings.get(SettingKeys.placeName) ?? '',
      source: 'manual',
    );
  }

  GeoPlace? _cachedPlace() {
    final raw = _settings.get(SettingKeys.resolvedPlace);
    if (raw == null || raw.isEmpty) return null;
    try {
      return GeoPlace.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _cache(GeoPlace place) =>
      _settings.put(SettingKeys.resolvedPlace, jsonEncode(place.toJson()));

  /// The device's own fix.
  Future<GeoPlace?> _devicePlace({required bool askPermission}) async {
    try {
      var reply = await _bridge.getLocation();
      if (reply == null) return null;

      // The platform reports "permission" when it has not been granted.
      if (reply['ok'] != true) {
        if (reply['reason'] != 'permission' || !askPermission) return null;
        final granted =
            await _bridge.requestPermission('location') ?? false;
        if (!granted) return null;
        reply = await _bridge.getLocation();
        if (reply == null || reply['ok'] != true) return null;
      }

      final lat = (reply['lat'] as num?)?.toDouble();
      final lon = (reply['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;

      return GeoPlace(
        latitude: lat,
        longitude: lon,
        source: reply['source'] == 'fresh' ? 'gps' : 'wifi',
      );
    } catch (_) {
      return null;
    }
  }

  /// An IP-based fallback. City level, and only a fallback.
  ///
  /// Deliberately the last resort: it is the least accurate and the only one
  /// that tells a third party where you are. It exists so that declining the
  /// location permission costs the weather, not the app.
  Future<GeoPlace?> _ipPlace() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client.getUrl(Uri.parse('https://ipwho.is/'));
        request.headers.set('User-Agent', 'SN-Launcher');
        final response = await request.close();
        if (response.statusCode != 200) return null;
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is! Map || decoded['success'] != true) {
          debugPrint('SNLOC ipwho.is declined: '
              '${body.substring(0, body.length < 200 ? body.length : 200)}');
          return null;
        }
        final lat = (decoded['latitude'] as num?)?.toDouble();
        final lon = (decoded['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) return null;
        final city = decoded['city'] is String ? decoded['city'] as String : '';
        final country =
            decoded['country'] is String ? decoded['country'] as String : '';
        return GeoPlace(
          latitude: lat,
          longitude: lon,
          name: [city, country].where((s) => s.isNotEmpty).join(', '),
          source: 'ip',
        );
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }
}
