import 'licence_filter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/photo_credit.dart';
import 'photo_album.dart';
import 'settings_store.dart';

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

  /// Below this the image would have to be upscaled on the target panel,
  /// which is exactly what makes a photograph look soft. The T20 is 2000px
  /// wide in landscape; 1200px candidates were accepted here before and were
  /// visibly blurry when stretched across it.
  static const int _minWidth = 2000;

  /// How many downloaded images to keep on disk.
  static const int _cacheLimit = 6;

  /// The panel is 2000px wide at most on the target hardware. Request 2400 so
  /// the image is downscaled rather than upscaled, with a little margin for
  /// `BoxFit.cover` cropping. A 2400px landscape is still well under the 4 MB
  /// download guard, and six of them fit comfortably in the persistent cache.
  static const int _maxWidth = 2400;

  /// Bump when the requested image size changes, or when a bug could have
  /// filed a photograph in the wrong album's folder. Cached files are derived
  /// content, so an old cache is safe to drop rather than leave the first
  /// picture after an upgrade looking soft — or showing one album's
  /// photographer's name under another album's title.
  static const int _cacheVersion = 3;

  /// The photographs this album may show.
  ///
  /// The pool is not a live search. Every entry is a specific Wikimedia
  /// Commons file that has been looked at and judged: public domain, CC0 or
  /// CC-BY, and shaped so that a 16:9 wall display does not have to crop a
  /// person's face off.
  ///
  /// This is a deliberate choice over "fetch something random from the
  /// internet". A photo frame on a wall display is a thing people look at
  /// constantly; a random image search will eventually put a portrait, a
  /// chart, or a screenshot of someone's desktop on it. A curated pool
  /// guarantees the thing is always pleasant and always lawfully
  /// redistributable, which a random fetch can never promise.
  List<AlbumPhoto> get pool => album.pool;

  /// Which album the background is showing.
  PhotoAlbum _album = PhotoAlbum.landscape;
  PhotoAlbum get album => _album;

  /// The bundled photograph that paints before anything is downloaded.
  String get heroAsset => album.heroAsset;

  /// The licence that goes with the bundled photograph.
  PhotoCredit get heroCredit => PhotoCredit.loadFor(album);

  /// Switch to a different album.
  ///
  /// The current file and credit are cleared immediately, so the new album's
  /// hero paints straight away and the previous album's photographer's name
  /// cannot be left on screen next to the new album's title.
  Future<void> setAlbum(PhotoAlbum next) async {
    if (next == _album) return;
    _album = next;
    _current = null;
    _credit = null;
    _lastTitle = null;
    if (_docsRoot != null) {
      _albumDir(next);
      _dropOldResolutionCache(next);
      _adoptNewestCached(next);
    }
    notifyListeners();
    // Before [start] has run there is no cache directory to write into and no
    // timer to reschedule — the real one is set up in [start], which reads
    // [_album] and so already points at the right folder. Fetching here would
    // download a photograph into a temporary directory that [start] is about to
    // walk away from.
    if (!_started) return;
    _schedule();
    // If a fetch is already running it belongs to the album we just left, so
    // its result is thrown away; [prefetchNext] remembers the request and
    // runs it as soon as that fetch is done.
    if (_enabled) unawaited(prefetchNext());
  }


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

  /// True when a prefetch was asked for while another fetch was running.
  ///
  /// The running fetch may be for the album that has just been switched away
  /// from, so its result is thrown away. This flag makes sure the album that
  /// is now current still gets its own photograph, promptly.
  bool _pendingPrefetch = false;

  Timer? _timer;
  bool _disposed = false;

  /// True once [start] has set the cache directory up.
  bool _started = false;

  /// The last file we showed, so the next pick cannot repeat it.
  String? _lastTitle;

  /// The documents directory, once [start] has found it.
  Directory? _docsRoot;

  /// Points the cache somewhere else. Tests use this; the app never calls it.
  @visibleForTesting
  set documentsRoot(Directory root) => _docsRoot = root;

  /// The cache directory for one album.
  ///
  /// One directory per album, so switching albums cannot show the previous
  /// album's photograph — or, worse, the previous album's photographer's name
  /// next to the new album's title.
  Directory _albumDir(PhotoAlbum which) {
    final root = _docsRoot ?? Directory.systemTemp;
    final d = Directory('${root.path}/sn_launcher_photos/${which.name}');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Restore settings, show whatever is already cached, then start rotating.
  Future<void> start() async {
    await _settings.load();
    // Initialize persistent cache directory.
    final docs = await getApplicationDocumentsDirectory();
    _docsRoot = docs;
    _albumDir(_album);
    _dropOldResolutionCache(_album);

    _enabled = _settings.read(SettingKeys.rotatePhotos, true, (v) => v == 'true');
    final mins = _settings.read(SettingKeys.rotateMinutes, 10, (v) => int.tryParse(v) ?? 10);
    _interval = Duration(minutes: mins.clamp(1, 1440));

    _adoptNewestCached(_album);
    _schedule();
    if (_enabled) unawaited(prefetchNext());
    _started = true;
    notifyListeners();
  }

  /// Drops cached photographs from an older requested resolution.
  ///
  /// The cache is persistent, so without this an upgrade would keep showing
  /// the old 1600px file until it happened to rotate — and the first thing the
  /// user sees after installing a sharpness fix should not be the blurry
  /// version. These files are downloads, not user data, so replacing them is
  /// safe.
  void _dropOldResolutionCache(PhotoAlbum which) {
    final dir = _albumDir(which);
    try {
      final marker = File('${dir.path}/.cache_version');
      if (marker.existsSync() &&
          marker.readAsStringSync().trim() == '$_cacheVersion') {
        return;
      }
      for (final entry in dir.listSync()) {
        try {
          entry.deleteSync(recursive: true);
        } catch (_) {
          // A file being written can wait for the next start.
        }
      }
      marker.writeAsStringSync('$_cacheVersion');
    } catch (_) {
      // A cache-cleanup failure must never stop the launcher from starting.
    }
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
    adopt(got.album, got.file, got.credit);
  }

  /// Puts a downloaded photograph on screen — unless the album changed while
  /// it was downloading.
  ///
  /// The album may change mid-fetch: the settings are restored from disk at
  /// start-up, and the album is restored the same way. A photograph that was
  /// fetched for the album we just left must not be shown under the new
  /// album's title, because then one photographer's name sits under another
  /// photographer's picture. That is exactly what happened once already.
  ///
  /// Returns true when the photograph was adopted.
  @visibleForTesting
  bool adopt(PhotoAlbum fetchedAlbum, File file, PhotoCredit credit) {
    if (fetchedAlbum != _album) return false;
    _current = file;
    _credit = credit;
    _lastTitle = credit.title;
    notifyListeners();
    return true;
  }

  /// Download the next picture ahead of time so the swap is instant.
  ///
  /// If a fetch is already running, remember that another one was asked for
  /// and run it as soon as this one finishes. Otherwise an album switch that
  /// lands mid-fetch would sit on its bundled photograph until the next
  /// ten-minute rotation.
  Future<void> prefetchNext() async {
    if (_busy) {
      _pendingPrefetch = true;
      return;
    }
    await next();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _schedule() {
    _timer?.cancel();
    if (!_enabled || _disposed) return;
    _timer = Timer.periodic(_interval, (_) => prefetchNext());
  }

  void _adoptNewestCached(PhotoAlbum which) {
    try {
      final files = _cachedImages(which)
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.isEmpty) return;
      _current = files.first;
      _credit = _readSidecar(files.first);
    } catch (_) {
      // No cache yet; the bundled asset covers it.
    }
  }

  /// The photographs cached for one album.
  ///
  /// Takes the album rather than reading the live cache directory, so a
  /// download that is still running for one album cannot be confused with
  /// another album's folder.
  List<File> _cachedImages(PhotoAlbum which) => _albumDir(which)
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

  void _prune(PhotoAlbum which) {
    final files = _cachedImages(which)
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
    //
    // Commons appends tracking parameters to the URL — `?utm_source=…&utm_content=original`
    // — so the query string has to come off before the extension is looked
    // at. Testing the raw URL refused every single discovered photograph.
    final original = info['url'];
    if (original is! String) return null;
    final path = original.split('?').first.toLowerCase();
    if (!(path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png'))) {
      return null;
    }
    final thumb = info['thumburl'];

    final title =
        (page['title'] as String? ?? '').replaceFirst('File:', '').replaceAll('_', ' ');
    if (title.isEmpty) return null;

    return PhotoCredit(
      title: title,
      author: _tidyAuthor(_metaText(meta['Artist'])),
      license: licence,
      licenseUrl: _metaText(meta['LicenseUrl']),
      sourceUrl:
          'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(title)}',
      imageUrl: thumb is String && thumb.isNotEmpty ? thumb : original,
    );
  }

  /// Commons writes the photographer's name twice: once as plain text and once
  /// as the link text of their user page — "David Marcu davidmarcu". This is
  /// rendered on the wall, so it has to read like a person's name.
  ///
  /// The plain name wins when there is one. When the whole field is a link,
  /// the link's text is the name.
  static String _tidyAuthor(String html) {
    final anchor = RegExp(r'<a\b[^>]*>(.*?)</a>', dotAll: true);
    final outside = _stripHtml(html.replaceAll(anchor, ' ')).trim();
    if (outside.isNotEmpty) return outside;
    final link = anchor.firstMatch(html)?.group(1);
    return link == null ? '' : _stripHtml(link);
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
  Future<({File file, PhotoCredit credit, PhotoAlbum album})?> _discoverOne(
    HttpClient client,
    PhotoAlbum which,
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
        AlbumPhoto(pick.title ?? '', pick.author ?? ''),
        album: which,
        preResolved: pick,
      );
      if (got != null) return got;
    }
    return null;
  }

  Future<({File file, PhotoCredit credit, PhotoAlbum album})?> _fetchIntoCache() async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    // The album this fetch belongs to, captured once.
    //
    // The album can change while the download is in flight — the settings are
    // restored from disk at start-up, and the album is restored the same way.
    // Reading the live album further down meant a Landscape discovery could be
    // written into the Alonso folder, and the Alonso caption then went with a
    // jellyfish and the wrong photographer's name. Every step below now uses
    // this captured album, and the result is discarded if the album changed.
    final album = _album;
    try {
      // Try each pool entry in turn. A pool entry can fail (file renamed on
      // Commons, licence changed, network blip) and that must not take the
      // whole rotation down with it.
      if (discover && album.usesDiscovery) {
        final client =
            HttpClient()..connectionTimeout = const Duration(seconds: 20);
        try {
          final got = await _discoverOne(client, album);
          if (got != null) {
            _prune(album);
            return got;
          }
        } catch (e) {
          debugPrint('PhotoFrameService: discovery failed — $e');
        } finally {
          client.close(force: true);
        }
      }

      for (var attempt = 0; attempt < 4; attempt++) {
        final pick = _pickSource(album);
        final got = await _fetchOne(pick, album: album);
        if (got != null) {
          _prune(album);
          return got;
        }
      }
      debugPrint('PhotoFrameService: no pool entry could be fetched');
      return null;
    } finally {
      _busy = false;
      // A prefetch asked for while this one was running still has to happen —
      // it is probably for the album that is now current.
      if (_pendingPrefetch) {
        _pendingPrefetch = false;
        unawaited(prefetchNext());
      }
      if (!_disposed) notifyListeners();
    }
  }

  /// Random, but never the picture we are currently showing.
  AlbumPhoto _pickSource(PhotoAlbum which) {
    final candidates =
        which.pool.where((s) => s.title != _lastTitle).toList(growable: false);
    final from = candidates.isEmpty ? which.pool : candidates;
    return from[DateTime.now().microsecondsSinceEpoch % from.length];
  }

  Future<({File file, PhotoCredit credit, PhotoAlbum album})?> _fetchOne(
    AlbumPhoto src, {
    required PhotoAlbum album,
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

      final saved = await _write(bytes, meta, album);
      return (file: saved, credit: meta, album: album);
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
        // 4 MB is far above any 2400px JPEG we want; anything larger is a
        // mis-picked URL and is not worth the user's data.
        if (bytes.length > 4 * 1024 * 1024) return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Writes a downloaded photograph into the cache folder of the album it
  /// belongs to.
  ///
  /// The album is passed in rather than read from the live field, because the
  /// album can change while the download is running — and a photograph must
  /// never be filed under an album it does not belong to.
  Future<File> _write(List<int> bytes, PhotoCredit credit, PhotoAlbum album) async {
    final dir = _albumDir(album);
    final tmp = File('${dir.path}/dl.tmp');
    await tmp.writeAsBytes(bytes, flush: true);

    final out = File(
      '${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    // Stored verbatim. Commons was asked for a 2400px-wide thumbnail, which is
    // already slightly larger than the panel — re-encoding would only be a way
    // to turn a ~600 KB JPEG into a 2 MB PNG, because dart:ui has no JPEG
    // encoder.
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

  /// Writes a photograph into an album's cache folder. Tests use this to check
  /// that a photograph ends up in the folder of the album it belongs to.
  @visibleForTesting
  Future<File> writeForTest(
    List<int> bytes,
    PhotoCredit credit,
    PhotoAlbum album,
  ) =>
      _write(bytes, credit, album);


  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}