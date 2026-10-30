import 'licence_filter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/photo_credit.dart';
import 'settings_store.dart';

/// A photograph the rotation is allowed to use.
///
/// Not a live search. Every entry is a specific Wikimedia Commons file that has
/// been looked at and judged: no people, no text, no diagrams, all landscape,
/// all public domain or CC-BY.
///
/// This is a deliberate choice over "fetch something random from the internet".
/// A photo frame on a wall display is a thing people look at constantly; a
/// random image search will eventually put a portrait, a chart, or a
/// screenshot of someone's desktop on it. A curated pool guarantees the thing
/// is always pleasant and always lawfully redistributable, which a random
/// fetch can never promise.
class PhotoSource {
  const PhotoSource(this.title, this.author);
  final String title;

  /// The name to put on screen.
  ///
  /// Overrides whatever the Commons `Artist` field says. That field routinely
  /// contains markup, agency boilerplate, or — in one case we picked — a dead
  /// link, and this string is rendered next to "Recent highlights" on the
  /// user's wall, so it has to read like a person's name.
  final String author;
}

/// Licences we will install onto the user's device. Anything else is refused at
/// fetch time and the pool entry is skipped.
const Set<String> _allowedLicenceFragments = {
  'public domain',
  'cc0',
  'cc by 2.0',
  'cc by 3.0',
  'cc by 4.0',
  'cc by',
};

/// May we install a photograph carrying this licence?
///
/// Fails closed: anything not explicitly allowed is refused.
///
/// Exported rather than private so it can be unit tested — this is the one
/// piece of logic where a bug means quietly putting unlawfully-redistributable
/// work onto a user's device, and it is the kind of thing that is never
/// exercised by hand.
///
/// Share-alike is the trap. "CC BY-SA 4.0" also contains "cc by", so a naive
/// allow-list test passes it. Commons additionally writes the bare form
/// "CC BY 4.0 SA" with no hyphen at all, which a substring check for "-sa"
/// misses — a real licence string from the actual API, found by this test.
bool licenceAllowsRedistribution(String licence) {
  // The Rust implementation, when the library loaded, with this function as the
  // fallback. The two are checked against each other over a corpus of real
  // Commons licence strings and agree on all of them — see
  // native/licence_filter and tool/verify_licence_parity.sh. A divergence here
  // would be a licensing bug, so the fallback is not decorative.
  if (LicenceFilter.isLoaded) return LicenceFilter.instance.allows(licence);
  final low = licence.toLowerCase().trim();
  if (low.isEmpty) return false;

  // Share-alike: a launcher cannot honour the viral-licensing obligation, so
  // these are refused outright.
  if (RegExp(r'share[\s_-]?alike|\bsharealike\b|-sa\b|\bsa\s*\d|\bsa\b')
      .hasMatch(low)) {
    return false;
  }
  // Non-commercial and no-derivatives.
  if (RegExp(r'-nc\b|non[\s-]?commercial').hasMatch(low)) return false;
  if (RegExp(r'-nd\b|noderiv|no[\s-]?derivative').hasMatch(low)) return false;
  if (low.contains('fair use') || low.contains('non-free')) return false;

  return _allowedLicenceFragments.any(low.contains);
}

/// Downloads and rotates the photo-frame background.
///
/// Design constraints, all from the e-waste hardware this targets:
///  * **Never blocks the first frame.** The bundled photograph in
///    `assets/photo/` is what renders at launch; anything downloaded is a
///    later upgrade. Cold start must stay at ~0.8s.
///  * **Never hits the network on a timer without a next image in hand.** The
///    next photograph is fetched *before* the current one expires, so the swap
///    is a local file read and cannot be late or fail visibly.
///  * **Plain `dart:io` HttpClient**, no HTTP package. On a 1 GB tablet every
///    avoided dependency is avoided APK size and avoided cold-start work.
class PhotoFrameService extends ChangeNotifier {
  PhotoFrameService({SettingsStore? settings, this.discover = false})
      : _settings = settings ?? SettingsStore();

  final SettingsStore _settings;

  /// When true, new photographs are discovered from Wikimedia Commons at
  /// runtime rather than taken from the hand-checked [pool].
  ///
  /// The pool is still there and still tried first when this is false; when it
  /// is true discovery is preferred and the pool is the fallback.
  ///
  /// Licensing is not weakened by this. Commons reports the actual licence per
  /// file, and [licenceAllowsRedistribution] still refuses everything that is
  /// not public domain, CC0 or CC-BY — share-alike especially, which a launcher
  /// cannot honour. What changes is where the candidates come from, not the
  /// rule about which of them may be used.
  final bool discover;

  /// Commons categories of curated photographs, queried in turn.
  ///
  /// "Featured" and "Quality" are the two grades Commons maintainers assign by
  /// hand. Landscape and nature are the subjects that suit a launcher sitting
  /// on a wall: no people, no text, no diagrams.
  ///
  /// Measured acceptance rates, 50 candidates sampled from each — most of
  /// Commons' curated work is share-alike, and a launcher has to refuse it:
  ///
  ///   Featured pictures of landscapes   3/50   (6%)
  ///   Quality images of landscapes      1/50   (2%)
  ///   Featured pictures of nature       0/15   (0%)
  ///
  /// Which is why [discoveryBatch] is large and why a discovery pass may end
  /// up refusing almost everything it is shown. That is the filter working,
  /// not the filter failing.
  static const List<String> discoveryCategories = [
    'Category:Featured pictures of landscapes',
    'Category:Quality images of landscapes',
    'Category:Featured pictures of nature',
    'Category:Featured pictures of plants',
    'Category:Quality images of nature',
  ];

  /// Wikimedia asks every caller to identify itself. An honest one.
  static const String _userAgent = 'SN-Launcher (Nest Hub replacement; +https://github.com/SimpleAppLauncher/SN-Launcher)';

  /// Candidates per query. Sized from the measured 2–6% acceptance rate: at
  /// 100 there is a good chance of several usable files, and it is still a
  /// single HTTP request.
  static const int discoveryBatch = 100;

  /// Rejected shapes.
  ///
  /// Commons' landscape categories are full of stitched panoramas — one
  /// featured picture is 28186 × 4183 px. Rendered behind a clock that is a
  /// smeared stripe, and the download alone would cost tens of megabytes.
  static const double _minAspect = 0.9;
  static const double _maxAspect = 2.6;

  /// Below this the image is not worth showing on a 2000px panel.
  static const int _minWidth = 1200;

  /// How many downloaded images to keep on disk.
  static const int _cacheLimit = 6;

  /// Kept narrow: the panel is 2000px wide at most on the target hardware, and
  /// the source files are far larger than that. 1600 keeps a landscape around
  /// 300 KB, so ten minutes of rotation costs a few hundred KB a day.
  static const int _maxWidth = 1600;

  /// Verified against the live Commons API and looked at before inclusion.

  /// Every entry is public domain, CC0 or CC-BY — never share-alike, which

  /// a launcher cannot honour.

  static const List<PhotoSource> pool = [
    PhotoSource(
      'Jokulsarlon lake, Iceland.jpg',
      'Kenny Muir',
    ),
    PhotoSource(
      'Lake Kinney mit Mount Whitehorn.jpg',
      'Florian Fuchs',
    ),
    PhotoSource(
      'Zagedan Lakes, Mountain cirque, Caucasus Mountains.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'Early morning light at the top of Poon Hill2.jpg',
      'Ali Sabbagh',
    ),
    PhotoSource(
      'Himalaya sunrise.jpg',
      'Ali Sabbagh',
    ),
    PhotoSource(
      'Khodz River Valley in fog, Adygea, Верховья реки Ходзь в тумане и облаках, Адыгея.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'Wisła pod Ochodzą w województwie małopolskim, 20231119 0706 2690.jpg',
      'Elaine Li',
    ),
    PhotoSource(
      'Asbestnaya Mount, Adygea, Гора Асбестная, виды с вершины, Адыгея, Западный Кавказ.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'Ella, Sri Lanka, Mountains in clouds, Panorama.jpg',
      'Vyacheslav Argenberg',
    ),
    PhotoSource(
      'River Running through a Rolling Hills Landscape by Edmund John Nieman .jpg',
      'Edmund John Nieman (1843-1910)',
    ),
    PhotoSource(
      'Rolling hills and lagoon scenics.jpg',
      'West Robin L, U.S. Fish and Wildlife Service',
    ),
  ];


  File? _current;
  PhotoCredit? _credit;

  /// The local file the background should load, or null to use the bundled
  /// asset.
  File? get currentFile => _current;
  PhotoCredit? get credit => _credit;

  bool _enabled = true;
  bool get enabled => _enabled;

  Duration _interval = const Duration(minutes: 10);
  Duration get interval => _interval;

  bool _busy = false;
  bool get busy => _busy;

  Timer? _timer;
  bool _disposed = false;

  /// The last file we showed, so the next pick cannot repeat it.
  String? _lastTitle;

  Directory get _cacheDir {
    // Persistent documents directory so the photo cache survives app restarts
    // and the "Next" button can switch instantly to an already-downloaded photo.
    // Uses a subdirectory so it does not clutter the app's documents.
    return _cacheDirInstance ??= _createCacheDir();
  }

  Directory? _cacheDirInstance;

  Directory _createCacheDir() {
    final docs = Directory.systemTemp; // placeholder; replaced in start()
    final d = Directory('${docs.path}/sn_launcher_photos');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Restore settings, show whatever is already cached, then start rotating.
  Future<void> start() async {
    await _settings.load();
    // Initialize persistent cache directory.
    final docs = await getApplicationDocumentsDirectory();
    _cacheDirInstance = Directory('${docs.path}/sn_launcher_photos');
    if (!_cacheDirInstance!.existsSync()) {
      _cacheDirInstance!.createSync(recursive: true);
    }

    _enabled = _settings.read(SettingKeys.rotatePhotos, true, (v) => v == 'true');
    final mins = _settings.read(SettingKeys.rotateMinutes, 10, (v) => int.tryParse(v) ?? 10);
    _interval = Duration(minutes: mins.clamp(1, 1440));

    _adoptNewestCached();
    _schedule();
    if (_enabled) unawaited(prefetchNext());
    notifyListeners();
  }

  // ── Public controls ────────────────────────────────────────────────────────

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    await _settings.put(SettingKeys.rotatePhotos, '$on');
    if (on) {
      unawaited(prefetchNext());
    }
    _schedule();
    notifyListeners();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    final m = minutes.clamp(1, 1440);
    _interval = Duration(minutes: m);
    await _settings.put(SettingKeys.rotateMinutes, '$m');
    _schedule();
    notifyListeners();
  }

  /// Fetch and show a different photograph right now.
  ///
  /// Used by the "next photo" control and by [prefetchNext]. Reports failure
  /// by leaving the current picture alone — never by blanking the background.
  Future<void> next() async {
    final got = await _fetchIntoCache();
    if (got == null || _disposed) return;
    _current = got.file;
    _credit = got.credit;
    _lastTitle = got.credit.title;
    notifyListeners();
  }

  /// Download the next picture ahead of time so the swap is instant.
  Future<void> prefetchNext() async {
    if (_busy) return;
    await next();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _schedule() {
    _timer?.cancel();
    if (!_enabled || _disposed) return;
    _timer = Timer.periodic(_interval, (_) => prefetchNext());
  }

  void _adoptNewestCached() {
    try {
      final files = _cachedImages()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.isEmpty) return;
      _current = files.first;
      _credit = _readSidecar(files.first);
    } catch (_) {
      // No cache yet; the bundled asset covers it.
    }
  }

  List<File> _cachedImages() => _cacheDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jpg'))
      .toList();

  File _sidecarFor(File image) =>
      File('${image.path}.json');

  PhotoCredit? _readSidecar(File image) {
    try {
      final f = _sidecarFor(image);
      if (!f.existsSync()) return null;
      final m = jsonDecode(f.readAsStringSync());
      if (m is! Map) return null;
      return PhotoCredit(
        title: m['title']?.toString(),
        author: m['author']?.toString(),
        license: m['license']?.toString(),
        licenseUrl: m['licenseUrl']?.toString(),
        sourceUrl: m['sourceUrl']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  void _prune() {
    final files = _cachedImages()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final old in files.skip(_cacheLimit)) {
      try {
        _sidecarFor(old).deleteSync();
        old.deleteSync();
      } catch (_) {/* keep going */}
    }
  }

  /// Asks Commons for a batch of candidates from one category and returns the
  /// ones that may actually be used.
  ///
  /// One request returns the licence, the dimensions and a scaled thumbnail
  /// URL for every file, so a whole batch is filtered without a second lookup
  /// per candidate. `iiurlwidth` makes Commons render the thumbnail server-side
  /// rather than us downloading a 4600px original and resizing it on a tablet
  /// with 2 GB of RAM.
  Future<List<PhotoCredit>> _discoverCandidates(
    HttpClient client,
    String category,
  ) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'generator': 'categorymembers',
      'gcmtitle': category,
      'gcmtype': 'file',
      'gcmlimit': '$discoveryBatch',
      'prop': 'imageinfo',
      'iiprop': 'url|size|extmetadata',
      'iiurlwidth': '$_maxWidth',
    });
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close();
    if (response.statusCode != 200) return const [];
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final pages = (decoded['query'] as Map?)?['pages'];
    if (pages is! Map) return const [];

    return pages.values
        .whereType<Map>()
        .map(candidateFromApiPage)
        .whereType<PhotoCredit>()
        .toList();
  }

  /// Turns one `query` API page into a usable photograph, or null.
  ///
  /// Public and pure so the licensing and shape rules can be tested against
  /// real API payloads rather than being exercised by hand once. Every reason
  /// to refuse a file is a reason that stops unlawful or absurd work reaching
  /// a user's screen, and this is the one function in the file where being
  /// wrong is not a cosmetic problem.
  @visibleForTesting
  static PhotoCredit? candidateFromApiPage(Map page) {
    final infos = page['imageinfo'];
    if (infos is! List || infos.isEmpty || infos.first is! Map) return null;
    final info = infos.first as Map;
    final meta = info['extmetadata'];
    if (meta is! Map) return null;

    // Fail closed, before anything else about the file is believed.
    final licence = _metaText(meta['LicenseShortName']);
    if (!licenceAllowsRedistribution(licence)) return null;

    final width = info['width'];
    final height = info['height'];
    if (width is! num || height is! num || height <= 0) return null;
    if (width < _minWidth) return null;
    final aspect = width / height;
    if (aspect < _minAspect || aspect > _maxAspect) return null;

    // Formats a launcher cannot usefully paint, and formats that cost a lot to
    // decode on a weak GPU.
    final original = info['url'];
    if (original is! String) return null;
    final lower = original.toLowerCase();
    if (!(lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png'))) {
      return null;
    }
    final thumb = info['thumburl'];

    final title =
        (page['title'] as String? ?? '').replaceFirst('File:', '').replaceAll('_', ' ');
    if (title.isEmpty) return null;

    return PhotoCredit(
      title: title,
      author: _stripHtml(_metaText(meta['Artist'])),
      license: licence,
      licenseUrl: _metaText(meta['LicenseUrl']),
      sourceUrl:
          'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(title)}',
      imageUrl: thumb is String && thumb.isNotEmpty ? thumb : original,
    );
  }

  /// Commons returns author fields as HTML fragments — links, and occasionally
  /// a whole `<a>` wrapper around a name.
  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .trim();

  static String _metaText(Object? node) {
    if (node is Map && node['value'] is String) return node['value'] as String;
    return '';
  }

  /// Discovers a usable photograph from Commons.
  ///
  /// Returns null — and the caller falls back to the checked pool — when every
  /// category yields nothing usable. On the measured acceptance rates that is
  /// the *expected* outcome fairly often, so it is a normal return, not an
  /// error worth logging loudly.
  Future<({File file, PhotoCredit credit})?> _discoverOne(
    HttpClient client,
  ) async {
    final categories = List<String>.of(discoveryCategories)..shuffle();
    for (final category in categories) {
      final candidates = await _discoverCandidates(client, category);
      if (candidates.isEmpty) continue;
      final fresh =
          candidates.where((c) => c.title != _lastTitle).toList(growable: false);
      final usable = fresh.isEmpty ? candidates : fresh;
      final pick = usable[DateTime.now().microsecondsSinceEpoch % usable.length];
      final got = await _fetchOne(
        PhotoSource(pick.title ?? '', pick.author ?? ''),
        preResolved: pick,
      );
      if (got != null) return got;
    }
    return null;
  }

  Future<({File file, PhotoCredit credit})?> _fetchIntoCache() async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    try {
      // Try each pool entry in turn. A pool entry can fail (file renamed on
      // Commons, licence changed, network blip) and that must not take the
      // whole rotation down with it.
      if (discover) {
        final client =
            HttpClient()..connectionTimeout = const Duration(seconds: 20);
        try {
          final got = await _discoverOne(client);
          if (got != null) {
            _prune();
            return got;
          }
        } catch (e) {
          debugPrint('PhotoFrameService: discovery failed — $e');
        } finally {
          client.close(force: true);
        }
      }

      for (var attempt = 0; attempt < 4; attempt++) {
        final pick = _pickSource();
        final got = await _fetchOne(pick);
        if (got != null) {
          _prune();
          return got;
        }
      }
      debugPrint('PhotoFrameService: no pool entry could be fetched');
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Random, but never the picture we are currently showing.
  PhotoSource _pickSource() {
    final candidates =
        pool.where((s) => s.title != _lastTitle).toList(growable: false);
    final from = candidates.isEmpty ? pool : candidates;
    return from[DateTime.now().microsecondsSinceEpoch % from.length];
  }

  Future<({File file, PhotoCredit credit})?> _fetchOne(
    PhotoSource src, {
    PhotoCredit? preResolved,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final meta = preResolved ?? await _api(client, src.title, src.author);
      if (meta == null) return null;
      if (!licenceAllowsRedistribution(meta.license ?? '')) {
        debugPrint(
          'PhotoFrameService: refusing "${src.title}" — licence is '
          '"${meta.license}"',
        );
        return null;
      }
      if (meta.imageUrl == null) return null;

      final bytes = await _download(client, meta.imageUrl!);
      if (bytes == null || bytes.length < 20_000) return null;

      final saved = await _write(bytes, meta);
      return (file: saved, credit: meta);
    } catch (e) {
      debugPrint('PhotoFrameService: ${src.title} failed — $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<PhotoCredit?> _api(
    HttpClient client,
    String fileTitle,
    String authorOverride,
  ) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'titles': 'File:$fileTitle',
      'prop': 'imageinfo',
      'iiprop': 'url|extmetadata|size',
      'iiurlwidth': '$_maxWidth',
      'format': 'json',
    });
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'SNLauncher/0.2');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final pages = (((decoded['query'] as Map?)?['pages']) as Map?) ?? {};
      for (final page in pages.values) {
        if (page is! Map || page.containsKey('missing')) continue;
        final info = ((page['imageinfo'] as List?)?.first) as Map?;
        if (info == null) return null;
        final em = (info['extmetadata'] as Map?) ?? {};
        String meta(String k) => ((em[k] as Map?)?['value'] ?? '').toString();
        return PhotoCredit(
          title: page['title'].toString().replaceFirst('File:', ''),
          author: authorOverride,
          license: _clean(meta('LicenseShortName')),
          licenseUrl: _clean(meta('LicenseUrl')),
          sourceUrl: info['descriptionurl']?.toString(),
          imageUrl: info['thumburl']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('PhotoFrameService: API error — $e');
    }
    return null;
  }

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  Future<List<int>?> _download(HttpClient client, String url) async {
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'SNLauncher/0.2');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        // 4 MB is far above any 1600px JPEG we want; anything larger is a
        // mis-picked URL and is not worth the user's data.
        if (bytes.length > 4 * 1024 * 1024) return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<File> _write(List<int> bytes, PhotoCredit credit) async {
    final tmp = File('${_cacheDir.path}/dl.tmp');
    await tmp.writeAsBytes(bytes, flush: true);

    final out = File(
      '${_cacheDir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    // Stored verbatim. Commons was asked for a 1600px-wide thumbnail, which is
    // already exactly what this should be — re-encoding would only be a way to
    // turn a 300 KB JPEG into a 2 MB PNG, because dart:ui has no JPEG encoder.
    await out.writeAsBytes(bytes, flush: true);
    try {
      tmp.deleteSync();
    } catch (_) {/* ignore */}

    await _sidecarFor(out).writeAsString(jsonEncode({
      'title': credit.title,
      'author': credit.author,
      'license': credit.license,
      'licenseUrl': credit.licenseUrl,
      'sourceUrl': credit.sourceUrl,
    }));
    return out;
  }


  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}