import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/models/photo_credit.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/assistant_service.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/photo_album.dart';
import 'package:sn_launcher/src/services/photo_frame_service.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/settings_page.dart';

/// A photo service that only ever shows the bundled hero.
///
/// The real service reaches for the filesystem and the network on `start()`,
/// neither of which exists in a test binding. Overriding the three getters
/// the shell reads is enough to put a specific album's photograph on screen.
class FakePhotos extends PhotoFrameService {
  FakePhotos(this.which);

  final PhotoAlbum which;

  @override
  PhotoAlbum get album => which;

  @override
  File? get currentFile => null;

  @override
  PhotoCredit? get credit => null;

  @override
  String get heroAsset => which.heroAsset;

  @override
  PhotoCredit get heroCredit => PhotoCredit.loadFor(which);
}

/// Renders the new backgrounds to the PNGs in `build/shots`.
///
///     flutter test test/capture_backgrounds_test.dart
///
/// Written to `build/shots` rather than `docs/shots`: the photographs here are
/// the bundled heroes, not the device's own gallery, and the device's
/// photographs are what the docs show. These are a layout harness for working
/// without the tablet — they exist so the albums and the snow can be *looked
/// at* before anyone installs a build.
///
/// They run with the rest of the suite rather than behind a flag: a test that
/// only runs when somebody remembers an environment variable is a test that
/// quietly stops being run, and this one is the only way to see the albums
/// without a device.
///
/// Not a golden: a golden that has to match byte for byte fails here on the
/// clock alone, and a test that cries wolf is a test people learn to ignore.
void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    final sans = FontLoader('GoogleSans');
    for (final weight in ['400', '500', '600', '700']) {
      sans.addFont(rootBundle.load('assets/fonts/GoogleSans-$weight.ttf'));
    }
    await sans.load();
    final poppins = FontLoader('Poppins');
    for (final weight in ['Light', 'Regular', 'Medium']) {
      poppins.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await poppins.load();
    final icons = FontLoader('MaterialSymbolsRounded');
    icons.addFont(rootBundle.load('assets/fonts/MaterialSymbolsRounded.ttf'));
    await icons.load();
  });

  final out = Directory('build/shots');

  /// The boundary that wraps the whole app.
  ///
  /// Not `find.byType(RepaintBoundary).first`: the photo frame is itself a
  /// RepaintBoundary, and the first one in the tree is not necessarily the
  /// screen. The key is explicit, so the capture is the whole app.
  final rootKey = GlobalKey();

  Future<void> write(WidgetTester tester, String name) async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    out.createSync(recursive: true);
    File('${out.path}/$name').writeAsBytesSync(bytes!);
  }

  /// A photo service that only ever shows the bundled hero.
  ///
  /// The real service reaches for the filesystem and the network on `start()`,
  /// neither of which exists in a test binding. Overriding the three getters
  /// the shell reads is enough to put a specific album's photograph on screen.
  Future<ShellController> pumpHome(
    WidgetTester tester, {
    required Size size,
    PhotoAlbum album = PhotoAlbum.landscape,
    bool christmas = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final controller = ShellController(
      metrics: NestMetrics.forSize(size),
      vsync: const TestVSync(),
    );
    addTearDown(controller.dispose);
    controller.setPaletteForTest(AmbientPalette.at(12));
    if (christmas) controller.toggleChristmasMode();

    final clock = ClockService(showSeconds: true, autoTick: false)
      ..overrideForTesting(DateTime(2026, 12, 24, 19, 42, 0));
    addTearDown(clock.dispose);

    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'GoogleSans'),
          home: Material(
            color: const Color(0xFF000000),
            child: NestShell(
              controller: controller,
              clock: clock,
              weather: WeatherService(),
              assistant: AssistantService(),
              photos: FakePhotos(album),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return controller;
  }

  for (final (album, label) in [
    (PhotoAlbum.racing, 'racing'),
    (PhotoAlbum.alonso, 'alonso'),
  ]) {
    testWidgets('the $label album on the wall', (tester) async {
      await pumpHome(tester, size: const Size(1280, 800), album: album);
      await write(tester, 'home-$label-16x9.png');
    });
  }

  testWidgets('the racing album on a 4:3 panel', (tester) async {
    await pumpHome(tester, size: const Size(1365, 1024), album: PhotoAlbum.racing);
    await write(tester, 'home-racing-4x3.png');
  });

  testWidgets('Christmas mode with snow', (tester) async {
    await pumpHome(
      tester,
      size: const Size(1280, 800),
      album: PhotoAlbum.landscape,
      christmas: true,
    );
    await write(tester, 'home-christmas-16x9.png');
  });

  testWidgets('the Background section', (tester) async {
    FeatureFlags.forTesting = FeatureFlags.parse(
      '{"features":{"settings":true,"themePicker":true}}',
      'capture',
    );
    addTearDown(() => FeatureFlags.forTesting = FeatureFlags.empty);

    const size = Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final controller = ShellController(
      metrics: NestMetrics.forSize(size),
      vsync: const TestVSync(),
    );
    addTearDown(controller.dispose);
    controller.setPaletteForTest(AmbientPalette.at(12));

    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'GoogleSans'),
          home: Scaffold(
            body: SettingsPage(
              metrics: controller.metrics,
              type: NestType(controller.metrics),
              palette: controller.palette,
              controller: controller,
              assistant: const AssistantSettings(
                enabled: false,
                backend: AssistantBackend.localOnly,
                geminiKey: '',
                homeAssistantUrl: '',
                homeAssistantToken: '',
                voiceEnabled: false,
                busy: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Background'), 120);
    await tester.pump();
    await write(tester, 'settings-background-16x9.png');

    await tester.scrollUntilVisible(find.text('Christmas mode'), 120);
    await tester.pump();
    await write(tester, 'settings-christmas-16x9.png');
  });
}
