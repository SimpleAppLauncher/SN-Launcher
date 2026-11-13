import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_motion.dart';
import 'package:sn_launcher/src/widgets/photo_frame.dart';

/// The photo frame is the whole idle screen, so its numbers are worth
/// pinning: how big the photograph is decoded, how much black lies over it,
/// and that the swap between two photographs is a dissolve and not a cut.
void main() {
  const size = Size(1280, 800);

  Future<void> pumpFrame(
    WidgetTester tester, {
    required AmbientPalette palette,
    String asset = 'assets/photo/landscape.jpg',
    File? file,
    Duration crossFade = const Duration(milliseconds: 420),
    Size panel = size,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoFrameBackground(
          metrics: NestMetrics.forSize(panel),
          palette: palette,
          asset: asset,
          file: file,
          crossFade: crossFade,
        ),
      ),
    );
    await tester.pump();
  }

  /// A real PNG on disk, so the crossfade has something real to decode.
  Future<File> writePng(int argb) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 16, 16),
      Paint()..color = Color(argb),
    );
    final image = await recorder.endRecording().toImage(16, 16);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory.systemTemp.createTempSync('sn_photo_frame_detail');
    final file = File('${dir.path}/shot.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    return file;
  }

  group('the decode size', () {
    testWidgets('is the panel width times the device pixel ratio',
        (tester) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(2560, 1600);
      addTearDown(tester.view.reset);

      await pumpFrame(tester, palette: AmbientPalette.day);

      final image = tester.widget<Image>(find.byType(Image));
      final resize = image.image as ResizeImage;
      // 1280 logical × 2.0 dpr = 2560, which is under the 4096 ceiling.
      expect(resize.width, 2560);
    });

    testWidgets('never asks for less than 640 pixels', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 200);
      addTearDown(tester.view.reset);

      // A 400-pixel panel at 1.0 would ask for 400 pixels, which is below the
      // floor: the decoder is told to bring 640 so the picture is never
      // upscaled into mush.
      await pumpFrame(tester,
          palette: AmbientPalette.day, panel: const Size(400, 800));

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).width, 640);
    });

    testWidgets('never asks for more than 4096 pixels', (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(3840, 2400);
      addTearDown(tester.view.reset);

      // A 2000-pixel panel at 3.0 would ask for 6000, which is past the
      // ceiling: no decoder is asked for a bitmap larger than this.
      await pumpFrame(tester,
          palette: AmbientPalette.day, panel: const Size(2000, 1200));

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).width, 4096);
    });

    testWidgets('is a ResizeImage, so Skia decodes straight to that size',
        (tester) async {
      await pumpFrame(tester, palette: AmbientPalette.day);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).allowUpscaling, isFalse);
    });
  });

  group('the picture', () {
    testWidgets('covers the frame, is centred, and does not flicker',
        (tester) async {
      await pumpFrame(tester, palette: AmbientPalette.day);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(image.alignment, Alignment.center);
      expect(image.gaplessPlayback, isTrue);
    });

    testWidgets('falls back to the ambient colour if it cannot be decoded',
        (tester) async {
      await pumpFrame(
        tester,
        palette: AmbientPalette.day,
        asset: 'assets/photo/does-not-exist.jpg',
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Nothing must throw, and the frame must still be there.
      expect(tester.takeException(), isNull);
      expect(find.byType(PhotoFrameBackground), findsOneWidget);
    });
  });

  group('the scrim', () {
    testWidgets('is a three-stop gradient, transparent to 0.42 black',
        (tester) async {
      await pumpFrame(tester, palette: AmbientPalette.day);

      LinearGradient? gradient;
      for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration && decoration.gradient is LinearGradient) {
          gradient = decoration.gradient as LinearGradient;
        }
      }
      expect(gradient, isNotNull);
      expect(gradient!.colors.length, 3);
      expect(gradient.stops, [0.0, 0.45, 1.0]);
      expect(gradient.colors[0].a, 0.0);
      expect(gradient.colors[1].a, closeTo(0.10, 0.001));
      expect(gradient.colors[2].a, closeTo(0.42, 0.001));
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
    });
  });

  group('the night dim', () {
    testWidgets('is laid over the picture at night', (tester) async {
      await pumpFrame(tester, palette: AmbientPalette.night);

      final dim = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).firstWhere(
        (box) => box.color == Colors.black.withValues(alpha: 0.16),
        orElse: () => throw StateError('the night dim is missing'),
      );
      expect(dim.color.a, closeTo(0.16, 0.001));
    });

    testWidgets('is not laid over the picture in the day', (tester) async {
      await pumpFrame(tester, palette: AmbientPalette.day);

      final dim = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where(
        (box) => box.color == Colors.black.withValues(alpha: 0.16),
      );
      expect(dim, isEmpty);
    });
  });

  group('the swap', () {
    testWidgets('is a dissolve with the requested duration',
        (tester) async {
      await pumpFrame(
        tester,
        palette: AmbientPalette.day,
        crossFade: const Duration(milliseconds: 700),
      );

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, const Duration(milliseconds: 700));
      expect(switcher.switchInCurve, kNestEase);
      expect(switcher.switchOutCurve, kNestDecelerate);
    });

    testWidgets('fades rather than cuts when the photograph changes',
        (tester) async {
      final first = await tester.runAsync(() => writePng(0xFFFF0000));
      final second = await tester.runAsync(() => writePng(0xFF0000FF));
      addTearDown(() {
        first?.deleteSync();
        second?.deleteSync();
      });

      await pumpFrame(tester, palette: AmbientPalette.day, file: first);
      expect(find.byType(Image), findsOneWidget);

      await pumpFrame(tester, palette: AmbientPalette.day, file: second);
      // The swap is gated on the new photograph being decoded first, so the
      // precache has to finish before the fade can begin. That is real file
      // I/O, so the test has to let it happen outside the fake clock — and
      // it is not quick: measured in this binding, the decode of a small PNG
      // can take half a second of real time.
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump();
        if (tester.widgetList(find.byType(Image)).length >= 2) break;
      }

      // Both the outgoing and the incoming picture are on screen while the
      // fade runs. A cut would show exactly one.
      expect(find.byType(Image), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(Image), findsNWidgets(2));

      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<FileImage>());
      expect(((image.image as ResizeImage).imageProvider as FileImage).file.path,
          second!.path);
    });
  });

  group('the swap does not start again by itself', () {
    // The bug this pins: `ImageProvider` does not override `operator ==`, so
    // two providers built for the same photograph compare unequal. Asking
    // "is this the same picture?" with the provider therefore answered "no"
    // on every rebuild, and every rebuild began another 420 ms crossfade —
    // two full-screen photographs dissolving continuously, for ever.
    //
    // On the T20 that measured as 16.5 ms of raster per frame on the home
    // page against 7.5 ms before the crossfade existed. Nothing about the
    // picture had changed; only the bookkeeping had.
    testWidgets('rebuilding with the same photograph keeps one picture on '
        'screen', (tester) async {
      final shot = await tester.runAsync(() => writePng(0xFF00AA55));
      addTearDown(() => shot?.deleteSync());

      await pumpFrame(tester, palette: AmbientPalette.day, file: shot);
      expect(find.byType(Image), findsOneWidget);

      // Rebuild the widget with the SAME photograph, the way a clock tick
      // does: same file, new widget instance, new provider object.
      for (var i = 0; i < 5; i++) {
        await pumpFrame(tester, palette: AmbientPalette.day, file: shot);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump();
        // A second fade would put two pictures on screen at once.
        expect(find.byType(Image), findsOneWidget,
            reason: 'rebuild $i started another crossfade');
      }

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('the picture that is on screen does not change identity',
        (tester) async {
      final shot = await tester.runAsync(() => writePng(0xFF112233));
      addTearDown(() => shot?.deleteSync());

      await pumpFrame(tester, palette: AmbientPalette.day, file: shot);
      final before = tester.widget<Image>(find.byType(Image)).key;

      await pumpFrame(tester, palette: AmbientPalette.day, file: shot);
      await tester.pump();
      final after = tester.widget<Image>(find.byType(Image)).key;

      // The key is the picture's NAME, so it survives a rebuild. If it were
      // the provider object, the key would differ every time and the
      // AnimatedSwitcher would treat it as a new child.
      expect(after, before);
      expect(after, isA<ValueKey<String?>>());
    });
  });
}
