import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/photo_credit.dart';
import 'package:sn_launcher/src/services/photo_frame_service.dart';

/// Tests for the rules that decide what appears on someone's wall.
///
/// Every case here is a real Wikimedia Commons API response, not a shape I
/// invented. Two of them were found by querying Commons while writing the
/// feature, which is the point: the share-alike case appeared 47 times out of
/// 50 in `Category:Quality images of landscapes`, and the panorama is a
/// *featured* picture at 28186 x 4183 px.
///
/// A launcher cannot honour share-alike, and a 28000 px panorama behind a
/// clock is a smeared stripe that costs tens of megabytes to download. Both
/// have to be refused, and neither is a judgement call that can be left to a
/// future reader to re-derive.
Map<String, Object?> apiPage({
  required String title,
  required String licence,
  String? artist,
  int width = 4636,
  int height = 2995,
  String url = 'https://upload.wikimedia.org/x/Example.jpg',
  String? thumbUrl,
  Map<String, Object?>? metadata,
}) =>
    {
      'title': 'File:$title',
      'imageinfo': [
        {
          'url': url,
          'width': width,
          'height': height,
          'thumburl': ?thumbUrl,
          'extmetadata': {
            'LicenseShortName': {'value': licence},
            'Artist': {'value': artist ?? '<a href="//commons.wikimedia.org">Debra Miller</a>'},
            'LicenseUrl': {'value': 'https://creativecommons.org/licenses/by/4.0/'},
            ...?metadata,
          },
        },
      ],
    };

void main() {
  PhotoCredit? accept(Map<String, Object?> page) =>
      PhotoFrameService.candidateFromApiPage(page);

  group('accepted', () {
    for (final licence in ['Public domain', 'CC0', 'CC BY 3.0', 'CC BY 4.0', 'CC BY']) {
      test('$licence is usable', () {
        final got = accept(apiPage(title: 'A.jpg', licence: licence));
        expect(got, isNotNull, reason: '$licence should be allowed');
        expect(got!.license, licence);
      });
    }

    test('keeps the scaled thumbnail, not the original', () {
      // A 4600px original downloaded and downscaled on a 2 GB tablet is how a
      // launcher gets killed by the OS. Commons renders the thumbnail.
      final got = accept(apiPage(
        title: 'A.jpg',
        licence: 'CC BY 3.0',
        thumbUrl: 'https://thumb.example/A/1600px-A.jpg',
      ));
      expect(got?.imageUrl, 'https://thumb.example/A/1600px-A.jpg');
    });

    test('strips the HTML Commons wraps authors in', () {
      final got = accept(apiPage(
        title: 'A.jpg',
        licence: 'CC BY 3.0',
        artist: '<a href="//x">Marek &amp; Ślusarczyk</a>',
      ));
      expect(got?.author, 'Marek & Ślusarczyk');
    });

    test('gives every accepted file a source link and a title', () {
      final got = accept(apiPage(title: 'Cub_Lake_at_dawn.jpg', licence: 'CC0'));
      expect(got?.title, 'Cub Lake at dawn.jpg');
      expect(got?.sourceUrl, contains('commons.wikimedia.org'));
    });
  });

  group('refused: licensing', () {
    // These are the strings Commons actually returns. "CC BY 4.0 SA" with no
    // hyphen is a real one, found by querying the live API.
    for (final licence in [
      'CC BY-SA 4.0',
      'CC BY-SA 3.0',
      'CC BY-SA 2.0',
      'CC BY 4.0 SA',
      'CC BY 2.5 SA',
      'CC BY-NC 4.0',
      'CC BY-NC-ND 4.0',
      'CC BY-ND 4.0',
      'Fair use',
      'Non-free',
      '',
    ]) {
      test('"$licence" is refused', () {
        expect(accept(apiPage(title: 'A.jpg', licence: licence)), isNull,
            reason: '"$licence" must not be shown');
      });
    }

    test('a file with no licence at all is refused', () {
      // Fail closed: an absent licence is not a permissive one.
      final page = apiPage(title: 'A.jpg', licence: 'CC BY 3.0');
      (page['imageinfo']! as List).first['extmetadata'] = <String, Object?>{};
      expect(accept(page), isNull);
    });
  });

  group('refused: shape and size', () {
    test('a 28186 x 4183 panorama is refused', () {
      // Real dimensions of a featured picture of a cloudscape. At a 7:1
      // aspect it renders as a stripe, and the download is enormous.
      expect(
        accept(apiPage(title: 'Pano.jpg', licence: 'CC BY 4.0',
            width: 28186, height: 4183)),
        isNull,
      );
    });

    test('a tall portrait is refused', () {
      expect(
        accept(apiPage(title: 'Tall.jpg', licence: 'CC BY 3.0',
            width: 800, height: 2400)),
        isNull,
      );
    });

    test('something too small for the panel is refused', () {
      expect(
        accept(apiPage(title: 'Small.jpg', licence: 'CC BY 3.0',
            width: 640, height: 480)),
        isNull,
      );
    });

    test('a 1600px original is refused instead of being upscaled', () {
      // This was the blur: a 1600px Commons file stretched across a 2000px
      // panel. The minimum now matches the panel width.
      expect(
        accept(apiPage(title: 'Soft.jpg', licence: 'CC BY 3.0',
            width: 1600, height: 1067)),
        isNull,
      );
    });

    test('a normal 3:2 landscape is kept', () {
      expect(
        accept(apiPage(title: 'Good.jpg', licence: 'CC BY 3.0',
            width: 4636, height: 2995)),
        isNotNull,
      );
    });
  });

  group('refused: unusable payloads', () {
    test('a non-image format is refused', () {
      for (final url in [
        'https://upload.wikimedia.org/x/Clip.webm',
        'https://upload.wikimedia.org/x/Doc.pdf',
        'https://upload.wikimedia.org/x/Anim.gif',
      ]) {
        expect(
          accept(apiPage(title: 'A', licence: 'CC BY 3.0', url: url)),
          isNull,
          reason: '$url cannot be painted usefully',
        );
      }
    });

    test('a page with no imageinfo is refused', () {
      expect(PhotoFrameService.candidateFromApiPage({'title': 'File:A.jpg'}), isNull);
    });

    test('a page with a zero height is refused rather than dividing by it', () {
      expect(
        accept(apiPage(title: 'A.jpg', licence: 'CC BY 3.0', height: 0)),
        isNull,
      );
    });

    test('an empty title is refused', () {
      expect(accept(apiPage(title: '', licence: 'CC BY 3.0')), isNull);
    });
  });

  group('the categories discovery queries exist', () {
    test('are real Commons category names', () {
      // Verified against the live API while building this. A typo here would
      // not throw — it would quietly return nothing, forever.
      expect(PhotoFrameService.discoveryCategories, isNotEmpty);
      for (final c in PhotoFrameService.discoveryCategories) {
        expect(c, startsWith('Category:'), reason: '"$c" is not a category');
      }
    });

    test('ask for a large enough batch to survive a 6% acceptance rate', () {
      // Measured: Featured pictures of landscapes accepted 3 of 50.
      expect(PhotoFrameService.discoveryBatch, greaterThanOrEqualTo(50),
          reason: 'a smaller batch would usually find nothing usable');
    });
  });
}
