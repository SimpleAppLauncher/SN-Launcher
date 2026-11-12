import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/photo_album.dart';

/// Licence metadata for the bundled background photograph.
///
/// Every photograph that ships with software needs its licence to travel with
/// it, and a CC-BY photo legally requires the author's name to be displayed.
/// So this is not decoration: `tool/fetch_photo.py` writes
/// `assets/photo/landscape.json`, and the shell renders [author] next to the
/// album title on screen.
///
/// Fails soft. A missing or malformed file leaves [author] null and the UI
/// simply omits the credit — which would be a licence violation, so the file is
/// committed and the loader logs loudly if it ever goes missing.
class PhotoCredit {
  const PhotoCredit({
    this.title,
    this.author,
    this.license,
    this.licenseUrl,
    this.sourceUrl,
    this.imageUrl,
  });

  final String? title;
  final String? author;
  final String? license;
  final String? licenseUrl;
  final String? sourceUrl;

  /// Where to fetch the full-size image. Null for the bundled photograph, which
  /// is already in the APK.
  final String? imageUrl;

  static const PhotoCredit empty = PhotoCredit();

  /// The photographer's name — what sits next to the album title.
  String? get displayCredit {
    final a = author?.trim();
    if (a == null || a.isEmpty) return null;
    return a;
  }

  /// Populated by [preload], which `main()` awaits **before** `runApp`. That
  /// ordering matters: the shell caches this in a `late final`, so a load that
  /// lands after the first frame would never be picked up and the credit would
  /// silently not render.
  /// One entry per album, so each bundled photograph keeps its own licence.
  static final Map<String, String> _assetCacheByAlbum = {};
  static final Map<String, PhotoCredit> _parsedByAlbum = {};

  /// Synchronous. Returns [empty] if [preload] has not run or the asset is
  /// missing.
  static PhotoCredit load() => loadFor(PhotoAlbum.landscape);

  /// Synchronous. The licence metadata for one album's bundled photograph.
  static PhotoCredit loadFor(PhotoAlbum album) {
    final key = album.heroCreditAsset;
    final cached = _parsedByAlbum[key];
    if (cached != null) return cached;
    final raw = _assetCacheByAlbum[key];
    if (raw == null) return empty;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return empty;
      return _parsedByAlbum[key] = PhotoCredit(
        title: map['title']?.toString(),
        author: map['author']?.toString(),
        license: map['license']?.toString(),
        licenseUrl: map['licenseUrl']?.toString(),
        sourceUrl: map['sourceUrl']?.toString(),
      );
    } catch (e) {
      debugPrint('PhotoCredit: $key is malformed: $e');
      return empty;
    }
  }

  static Future<void> preload() async {
    for (final album in PhotoAlbum.values) {
      final asset = album.heroCreditAsset;
      try {
        _assetCacheByAlbum[asset] = await rootBundle.loadString(asset);
      } catch (_) {
        _assetCacheByAlbum.remove(asset);
        debugPrint(
          'PhotoCredit: $asset missing — the bundled photo will show no author '
          'credit, which its licence may require.',
        );
      }
    }
    // The landscape sidecar is also the historical fallback.
    _parsedByAlbum.clear();
    load();
  }
}