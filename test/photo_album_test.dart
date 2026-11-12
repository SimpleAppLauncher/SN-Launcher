import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/photo_album.dart';

/// The pools are the part of this app that a person cannot undo.
///
/// Every photograph in here ends up on someone's wall, and every one of them
/// carries a licence that the app has to be allowed to redistribute. So the
/// pool is checked mechanically rather than by reading it: a duplicate title,
/// an empty author or a file type the renderer cannot use are all failures a
/// human eye would miss while scrolling.
void main() {
  group('PhotoAlbum', () {
    test('every album has photographs', () {
      for (final album in PhotoAlbum.values) {
        expect(album.pool, isNotEmpty, reason: '${album.name} has no photos');
      }
    });

    test('every album has a caption', () {
      for (final album in PhotoAlbum.values) {
        expect(album.caption.trim(), isNotEmpty);
      }
    });

    test('the landscape caption is the measured one', () {
      // "Recent highlights" was read off a photograph of a real Nest Hub.
      // Changing it changes a measured constant, which is not a small thing.
      expect(PhotoAlbum.landscape.caption, 'Recent highlights');
    });

    test('the new albums name themselves', () {
      expect(PhotoAlbum.racing.caption, 'Racing cars');
      expect(PhotoAlbum.alonso.caption, 'Fernando Alonso');
    });

    test('every photograph names a photographer', () {
      // The author is rendered next to the album title, on the wall.
      for (final album in PhotoAlbum.values) {
        for (final photo in album.pool) {
          expect(photo.author.trim(), isNotEmpty,
              reason: '${photo.title} has no author');
        }
      }
    });

    test('every photograph is a format the renderer can use', () {
      const allowed = {'.jpg', '.jpeg', '.png'};
      for (final album in PhotoAlbum.values) {
        for (final photo in album.pool) {
          final lower = photo.title.toLowerCase();
          expect(
            allowed.any(lower.endsWith),
            isTrue,
            reason: '${photo.title} is not a jpg, jpeg or png',
          );
        }
      }
    });

    test('no album lists the same photograph twice', () {
      for (final album in PhotoAlbum.values) {
        final titles = album.pool.map((p) => p.title).toList();
        expect(titles.toSet().length, titles.length,
            reason: '${album.name} has a duplicate title');
      }
    });

    test('the Alonso album is half car and half driver', () {
      final car = PhotoAlbum.alonso.poolCar;
      final subject = PhotoAlbum.alonso.poolSubject;
      expect(car, isNotEmpty);
      expect(subject, isNotEmpty);
      final smaller = car.length < subject.length ? car.length : subject.length;
      final larger = car.length > subject.length ? car.length : subject.length;
      expect(smaller / larger, greaterThanOrEqualTo(0.6),
          reason: 'the two halves are ${car.length} and ${subject.length}');
    });

    test('the Alonso album covers the whole career', () {
      final titles = PhotoAlbum.alonso.pool.map((p) => p.title).join(' | ');
      expect(titles, contains('Renault'));
      expect(titles, contains('McLaren'));
      expect(titles, contains('Ferrari'));
      expect(titles, contains('Imola'));
    });

    test('only the landscape album discovers new photographs', () {
      expect(PhotoAlbum.landscape.usesDiscovery, isTrue);
      expect(PhotoAlbum.racing.usesDiscovery, isFalse);
      expect(PhotoAlbum.alonso.usesDiscovery, isFalse);
    });

    test('an album survives a round trip through its stored name', () {
      for (final album in PhotoAlbum.values) {
        expect(PhotoAlbum.fromName(album.storageName), album);
      }
      expect(PhotoAlbum.fromName(null), PhotoAlbum.landscape);
      expect(PhotoAlbum.fromName('nonsense'), PhotoAlbum.landscape);
    });

    test('each album has its own hero photograph and licence', () {
      final assets = PhotoAlbum.values.map((a) => a.heroAsset).toSet();
      final credits = PhotoAlbum.values.map((a) => a.heroCreditAsset).toSet();
      expect(assets.length, PhotoAlbum.values.length);
      expect(credits.length, PhotoAlbum.values.length);
    });
  });
}
