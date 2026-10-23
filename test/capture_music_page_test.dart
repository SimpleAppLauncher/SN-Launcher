import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/ncs_client.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/ncs_music_page.dart';

import 'ncs_client_test.dart' show FakePlayer;

/// Renders the music page to the PNGs in `docs/shots`.
///
///     SN_CAPTURE=1 flutter test test/capture_music_page_test.dart
///
/// Skipped by default. This writes screenshots; it does not assert them. A
/// golden that has to match byte for byte would fail here on the elapsed time
/// alone — the clock ticks between two runs, which is the one thing this page
/// is meant to do — and a test that cries wolf is a test people learn to
/// ignore.
///
/// Not a `matchesGoldenFile` on purpose: that comparator has no tolerance, and
/// the three pixels that moved between runs are the progress bar doing its job.
void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    // Without these the capture is a page of placeholder boxes: text in a test
    // renders in a fallback face, and the icons are a font this launcher
    // subsets and ships itself.
    final sans = FontLoader('GoogleSans');
    for (final weight in ['400', '500', '600', '700']) {
      sans.addFont(rootBundle.load('assets/fonts/GoogleSans-$weight.ttf'));
    }
    await sans.load();
    final icons = FontLoader('MaterialSymbolsRounded');
    icons.addFont(rootBundle.load('assets/fonts/MaterialSymbolsRounded.ttf'));
    await icons.load();
  });

  late FakePlayer player;
  setUp(() async => player = await FakePlayer.start());
  tearDown(() async => player.stop());

  final capture = Platform.environment['SN_CAPTURE'] == '1';

  testWidgets('the music page', skip: !capture, (tester) async {
    tester.view.physicalSize = const Size(800, 1340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = NcsClient(baseUrl: player.url);
    await tester.runAsync(() async => client.refresh());
    final metrics = NestMetrics.forSize(const Size(800, 1340));
    final key = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          home: NcsMusicPage(
            client: client,
            metrics: metrics,
            type: NestType(metrics),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() => _write(tester, key, 'docs/shots/music.png'));

    // And the full player, which is the other half of the design.
    await tester.tap(find.text('Everything In Its Right Place'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.runAsync(
      () => _write(tester, key, 'docs/shots/music-player.png'),
    );

    client.stop();
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
}

Future<void> _write(WidgetTester tester, GlobalKey key, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = await boundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('  wrote $path (${image.width}x${image.height})');
}
