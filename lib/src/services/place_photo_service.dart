import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'licence_filter.dart';
import 'location_service.dart';
import '../models/photo_credit.dart';

/// A photograph of the place the weather is about.
///
/// The idea: a tablet on a wall showing "12° and raining" is a weather widget.
/// The same tablet showing a photograph of *that* weather, over that place, is
/// a picture of the world outside. It is the difference between a dashboard and
/// a window.
///
/// **Where the pictures come from.** Wikimedia Commons, by coordinate. The
/// `geosearch` generator returns files that are geotagged near a point, with
/// their licence attached, and the same licence rules this project already
/// applies to the background photo pool apply here: public domain, CC0 and
/// CC-BY only. Share-alike is refused, because a launcher cannot honour the
/// viral-licensing obligation — that is 80-odd percent of what Commons holds,
/// so the filter does a great deal of work here.
///
/// **The `ggsnamespace=6` is not optional.** Without it the generator returns
/// Wikipedia *articles* about places, with no image information at all, and
/// the call looks like it worked and returned nothing usable.
///
/// **Commons's search cluster fails often.** It answers HTTP 200 with an
/// `error` object in the body — `cirrussearch-too-busy-error` — often enough
/// to need retries with a backoff. A caller that only checks the status code
/// sees a success and gets nothing.
class PlacePhotoService extends ChangeNotifier {
  PlacePhotoService({this.radiusMetres = 6000});

  /// How far from the place to look.
  ///
  /// Commons caps a geosearch at 10 km. 6 km finds the town and its
  /// surroundings without wandering into the next county.
  final int radiusMetres;

  /// Where the pictures are kept.
  ///
  /// The app's own cache directory, which is on device storage and survives a
  /// reboot. The OS may clear it under storage pressure, which is correct
  /// behaviour for a cache and not a bug: the next refresh refills it.
  static const String dirName = 'sn_launcher_place_photos';

  /// Commons categories queried, in order.
  ///
  /// Landscape and nature first, because a city centre is full of photographs
  /// of office interiors and car parks, and a picture of a car park is not a
  /// picture of anywhere.
  static const List<String> categories = [
    'Category:Featured pictures of landscapes',
    'Category:Quality images of landscapes',
    'Category:Featured pictures of nature',
    'Category:Quality images of nature',
  ];

  /// How long a picture is considered "recently used" and is avoided.
  ///
  /// The requirement was that the picture is not the same within an hour of
  /// the last change, so an hour is the floor. Two hours gives a bigger pool
  /// to choose from without the picture changing too often to notice.
  static const Duration repeatWindow = Duration(hours: 2);

  File? _file;
  PhotoCredit? _credit;
  String _placeLabel = '';
  bool _busy = false;
  String _lastError = '';

  File? get currentFile => _file;
  PhotoCredit? get credit => _credit;

  /// The place the picture is of, e.g. "Reykjavík".
  String get placeLabel => _placeLabel;

  String get lastError => _lastError;

  bool get hasPhoto => _file != null;

  /// The file the widget should paint.
  ///
  /// Kept separate from [_file] so a failed refresh does not blank the
  /// picture that is already on screen. A background that goes empty because a
  /// network call failed is worse than a slightly stale picture.
  File? get displayFile => _file;

  // ── The picked-image history ──────────────────────────────────────────────

  /// Recently used pictures, so the next one is different.
  ///
  /// A list of `{title, at}` in the cache directory. It is what makes "not the
  /// same image within the hour" true rather than hoped for.
  List<Map<String, Object?>> _recent = [];

  File get _historyFile {
    final d = Directory('${Directory.systemTemp.path}/$dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    return File('${d.path}/recent.json');
  }

  void _loadHistory() {
    try {
      final f = _historyFile;
      if (!f.existsSync()) {
        _recent = [];
        return;
      }
      final decoded = jsonDecode(f.readAsStringSync());
      _recent = decoded is List
          ? decoded.whereType<Map>().map((m) => Map<String, Object?>.from(m)).toList()
          : [];
    } catch (_) {
      _recent = [];
    }
  }

  void _saveHistory() {
    try {
      _historyFile.writeAsStringSync(jsonEncode(_recent));
    } catch (_) {
      // A history that cannot be saved means the next refresh might repeat a
      // picture. Not worth failing over.
    }
  }

  /// Titles used within [repeatWindow], which the next pick must avoid.
  Set<String> get _recentlyUsedTitles {
    final cutoff = DateTime.now().millisecondsSinceEpoch - repeatWindow.inMilliseconds;
    return _recent
        .where((e) => (e['at'] as int? ?? 0) >= cutoff)
        .map((e) => e['title'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  // ── Fetching ──────────────────────────────────────────────────────────────

  /// Finds and installs a photograph of [place].
  ///
  /// Does nothing if the place has not moved, so a caller can call it on every
  /// weather refresh without churning the picture.
  Future<void> update(GeoPlace? place) async {
    if (place == null) return;
    if (_busy) return;
    final key = '${place.latitude.toStringAsFixed(2)},'
        '${place.longitude.toStringAsFixed(2)}';
    if (key == _placeLabel && _file != null) return;

    _busy = true;
    _lastError = '';
    notifyListeners();
    try {
      _loadHistory();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final credit = await _findPhoto(client, place);
        if (credit == null) {
          _lastError = 'No freely-licensed photograph of this place was found';
          return;
        }
        final bytes = await _download(client, credit.imageUrl!);
        if (bytes == null || bytes.length < 8000) {
          _lastError = 'That photograph could not be downloaded';
          return;
        }
        final saved = _save(bytes, credit);
        _file = saved;
        _credit = credit;
        _placeLabel = key;
        _remember(credit.title ?? '');
      } catch (e) {
        _lastError = 'Could not look up a photograph of this place';
        debugPrint('PlacePhotoService: $e');
      } finally {
        client.close(force: true);
      }
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _remember(String title) {
    _recent.add({'title': title, 'at': DateTime.now().millisecondsSinceEpoch});
    // Keep the history bounded; a week of hourly refreshes is plenty.
    final cutoff = DateTime.now().millisecondsSinceEpoch -
        const Duration(days: 7).inMilliseconds;
    _recent.removeWhere((e) => (e['at'] as int? ?? 0) < cutoff);
    _saveHistory();
  }

  /// Searches Commons for a usable photograph near the place.
  Future<PhotoCredit?> _findPhoto(HttpClient client, GeoPlace place) async {
    final avoid = _recentlyUsedTitles;
    // The coordinates are offset around the place so repeated searches do not
    // keep returning the same handful of files from the centre.
    final offsets = <List<double>>[
      [0, 0],
      [0.02, 0.02],
      [-0.02, 0.02],
      [0.02, -0.02],
      [-0.02, -0.02],
    ];

    for (final category in categories) {
      for (final offset in offsets) {
        final credit = await _search(client, place, category, offset, avoid);
        if (credit != null) return credit;
      }
    }
    return null;
  }

  /// One geosearch query, with the retries Commons's cluster needs.
  Future<PhotoCredit?> _search(
    HttpClient client,
    GeoPlace place,
    String category,
    List<double> offset,
    Set<String> avoid,
  ) async {
    final lat = place.latitude + offset[0];
    final lon = place.longitude + offset[1];
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'generator': 'geosearch',
      'ggscoord': '$lat|$lon',
      'ggsradius': '$radiusMetres',
      'ggslimit': '50',
      // WITHOUT THIS the generator returns Wikipedia articles about places
      // rather than files, and the response has no image information at all.
      'ggsnamespace': '6',
      'prop': 'imageinfo',
      'iiprop': 'url|size|extmetadata',
      'iiurlwidth': '1600',
    });

    Map<dynamic, dynamic>? decoded;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        final response = await request.close();
        if (response.statusCode != 200) continue;
        final body = await response.transform(utf8.decoder).join();
        final parsed = jsonDecode(body);
        if (parsed is! Map) continue;
        // HTTP 200 with an error in the body. Commons's search cluster returns
        // `cirrussearch-too-busy-error` this way, often enough that checking
        // only the status code means silently finding nothing.
        if (parsed['error'] != null) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        decoded = parsed;
        break;
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    if (decoded == null) return null;

    final query = decoded['query'];
    if (query is! Map) return null;
    final pages = query['pages'];
    if (pages is! Map) return null;

    final candidates = <PhotoCredit>[];
    for (final page in pages.values) {
      if (page is! Map) continue;
      final credit = _creditFrom(page);
      if (credit == null) continue;
      if (credit.title != null && avoid.contains(credit.title)) continue;
      candidates.add(credit);
    }
    if (candidates.isEmpty) return null;

    // Prefer the biggest, which is usually the best photograph, but keep it
    // random enough that the same file is not always the winner.
    candidates.shuffle();
    return candidates.first;
  }

  /// Turns one API page into a credit, or null if it may not be used.
  ///
  /// The licence check is the same one the background photo pool uses, and the
  /// same Rust implementation, so there is one rule about what may legally be
  /// shown rather than two that could disagree.
  PhotoCredit? _creditFrom(Map page) {
    final infos = page['imageinfo'];
    if (infos is! List || infos.isEmpty || infos.first is! Map) return null;
    final info = infos.first as Map;
    final meta = info['extmetadata'];
    if (meta is! Map) return null;

    final licence = _metaText(meta['LicenseShortName']);
    if (!licenceAllowsRedistribution(licence)) return null;

    final width = info['width'];
    final height = info['height'];
    if (width is! num || height is! num || height <= 0) return null;
    if (width < 1200) return null;
    final aspect = width / height;
    if (aspect < 1.1 || aspect > 2.8) return null;

    final url = info['thumburl'] ?? info['url'];
    if (url is! String || url.isEmpty) return null;

    return PhotoCredit(
      title: (page['title'] as String? ?? '').replaceFirst('File:', ''),
      author: _stripHtml(_metaText(meta['Artist'])),
      license: licence,
      licenseUrl: _metaText(meta['LicenseUrl']),
      sourceUrl: 'https://commons.wikimedia.org/wiki/'
          '${Uri.encodeComponent(page['title'] as String? ?? '')}',
      imageUrl: url,
    );
  }

  bool licenceAllowsRedistribution(String licence) =>
      LicenceFilter.isLoaded
          ? LicenceFilter.instance.allows(licence)
          : _licenceFallback(licence);

  /// The same rules, in Dart, for when the Rust library is not loaded.
  static bool _licenceFallback(String licence) {
    final low = licence.toLowerCase().trim();
    if (low.isEmpty) return false;
    if (RegExp(r'share[\s_-]?alike|sharealike|-sa\b|sa\s*\d|\bsa\b')
        .hasMatch(low)) {
      return false;
    }
    if (RegExp(r'-nc\b|non[\s-]?commercial').hasMatch(low)) return false;
    if (RegExp(r'-nd\b|noderiv|no[\s-]?derivative').hasMatch(low)) return false;
    if (low.contains('fair use') || low.contains('non-free')) return false;
    return const [
      'public domain',
      'cc0',
      'cc by 2.0',
      'cc by 3.0',
      'cc by 4.0',
      'cc by',
    ].any(low.contains);
  }

  Future<Uint8List?> _download(HttpClient client, String url) async {
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final chunks = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (chunks.isEmpty) return null;
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    }
  }

  File _save(Uint8List bytes, PhotoCredit credit) {
    final d = Directory('${Directory.systemTemp.path}/$dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    final name = (credit.title ?? 'photo').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${d.path}/$name.jpg');
    file.writeAsBytesSync(bytes);
    // The credit, next to the picture, so it survives the app being killed.
    File('${file.path}.json').writeAsStringSync(jsonEncode({
      'title': credit.title,
      'author': credit.author,
      'license': credit.license,
      'licenseUrl': credit.licenseUrl,
      'sourceUrl': credit.sourceUrl,
    }));
    return file;
  }

  /// The credit for whatever picture is on screen, read from disk.
  ///
  /// So the attribution survives the app being restarted, rather than only
  /// being right for as long as the process lives.
  static PhotoCredit? creditForFile(File file) {
    try {
      final sidecar = File('${file.path}.json');
      if (!sidecar.existsSync()) return null;
      final decoded = jsonDecode(sidecar.readAsStringSync());
      if (decoded is! Map) return null;
      return PhotoCredit(
        title: decoded['title'] as String?,
        author: decoded['author'] as String?,
        license: decoded['license'] as String?,
        licenseUrl: decoded['licenseUrl'] as String?,
        sourceUrl: decoded['sourceUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Any picture left over from a previous run.
  ///
  /// So the weather page has a photograph immediately on launch rather than a
  /// blank gradient until the first fetch completes.
  static File? anyCachedPhoto() {
    try {
      final d = Directory('${Directory.systemTemp.path}/$dirName');
      if (!d.existsSync()) return null;
      final files = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList();
      if (files.isEmpty) return null;
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files.first;
    } catch (_) {
      return null;
    }
  }

  static String _metaText(Object? node) {
    if (node is Map && node['value'] is String) return node['value'] as String;
    return '';
  }

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .trim();

  /// Wikimedia asks every caller to identify itself, and blocks generic ones.
  static const String _userAgent =
      'SN-Launcher/0.3 (Nest Hub replacement; https://github.com/SimpleAppLauncher/SN-Launcher)';

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
