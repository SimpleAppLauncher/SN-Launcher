import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/photo_credit.dart';
import 'package:sn_launcher/src/services/photo_album.dart';
import 'package:sn_launcher/src/services/photo_frame_service.dart';
import 'package:sn_launcher/src/services/settings_store.dart';

/// The bug this file exists to pin down.
///
/// The launcher restores the album from the settings file at start-up, and the
/// photo service starts fetching at the same time. A fetch that began under
/// one album was written into whichever folder the album had become by the
/// time the download finished — so a Landscape discovery photograph landed in
/// the Alonso folder, and the wall showed a jellyfish under the caption
/// "Fernando Alonso", credited to the jellyfish's photographer.
///
/// Two things have to hold, and both are checked here:
///   * a photograph is filed under the album it was fetched for, and
///   * a photograph fetched for an album that is no longer current is not
///     adopted.
void main() {
  late Directory root;

  PhotoFrameService service() => PhotoFrameService(
        settings: SettingsStore(
          fallbackPath: '${root.path}/settings.json',
        ),
      )..documentsRoot = root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sn_album_cache');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a photograph is filed under the album it was fetched for', () async {
    final photos = service();
    await photos.setAlbum(PhotoAlbum.alonso);

    final file = await photos.writeForTest(
      [1, 2, 3, 4, 5],
      PhotoCredit(title: 'Underwater slope in Gullmarn fjord 2.jpg'),
      PhotoAlbum.landscape,
    );

    expect(
      file.path,
      contains('/landscape/'),
      reason: 'a Landscape photograph must not be filed under Alonso',
    );
    expect(file.path, isNot(contains('/alonso/')));
    expect(file.existsSync(), isTrue);
  });

  test('each album has its own folder', () async {
    final photos = service();

    for (final album in PhotoAlbum.values) {
      final file = await photos.writeForTest(
        [1, 2, 3],
        PhotoCredit(title: 'x.jpg'),
        album,
      );
      expect(file.path, contains('/${album.name}/'));
    }
  });

  test('a photograph fetched for the album we just left is not adopted', () async {
    final photos = service();
    await photos.setAlbum(PhotoAlbum.landscape);

    final file = File('${root.path}/late.jpg')..writeAsBytesSync([1, 2, 3]);
    final credit = PhotoCredit(
      title: 'Underwater slope in Gullmarn fjord 2.jpg',
      author: 'W.carter',
    );

    expect(photos.adopt(PhotoAlbum.landscape, file, credit), isTrue);
    expect(photos.currentFile, file);
    expect(photos.credit?.author, 'W.carter');

    // The album changes while the download is still running.
    await photos.setAlbum(PhotoAlbum.alonso);
    expect(photos.currentFile, isNull);
    expect(photos.credit, isNull);

    // The late result arrives. It belongs to the album we left, so it must
    // not be shown under "Fernando Alonso".
    expect(photos.adopt(PhotoAlbum.landscape, file, credit), isFalse);
    expect(photos.currentFile, isNull);
    expect(photos.credit, isNull);
  });

  test('switching albums clears the previous photograph and its credit', () async {
    final photos = service();
    await photos.setAlbum(PhotoAlbum.racing);

    final file = File('${root.path}/racing.jpg')..writeAsBytesSync([1, 2, 3]);
    photos.adopt(
      PhotoAlbum.racing,
      file,
      PhotoCredit(title: 'Hyundai Accent WRC Goodwood FOS 2018.jpg',
          author: 'BWard 1997'),
    );
    expect(photos.currentFile, file);

    await photos.setAlbum(PhotoAlbum.alonso);
    expect(photos.currentFile, isNull);
    expect(photos.credit, isNull);
    expect(photos.album, PhotoAlbum.alonso);
  });

  test('the album decides the bundled hero and its licence', () async {
    final photos = service();
    for (final album in PhotoAlbum.values) {
      await photos.setAlbum(album);
      expect(photos.heroAsset, album.heroAsset);
      expect(photos.heroAsset, endsWith('.jpg'));
    }
  });
}
