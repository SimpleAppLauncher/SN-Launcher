import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/services/app_catalog.dart';
import 'package:sn_launcher/src/services/platform_bridge.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/widgets/app_drawer.dart';
import 'package:sn_launcher/src/widgets/nest_glyphs.dart';

/// A 144x144 PNG with a red rounded square and a white bar. Small enough to
/// keep in the test, large enough to be a real image rather than a glyph.
final Uint8List _redIcon = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAJAAAACQCAYAAADnRuK4AAACiklEQVR4nO3cS3LaQBRAUXBlJ9EA738xZqCsxakMnPIHjMQVlJHOmSMNuLxuqBb73R2Nh8PrPe+3VcPxuL/XvW56I8GsP6jFLyyabcW02MWEs82Q8kWEs+2QnsqLxfP46nt4VX3CWafhimk0ewKJZ73GK6bRrIDEs37jzIgmBySe7RhnRDQpIPFszzgxoosBiWe7xgkRfRuQeBgvRHQ2IPEwpYX0QyKcDMj0YWoTXwISD+ecasMSRvIhINOHSz43YgKR/A/I9GGq962YQCQCogdk+WKut2ZMIBIBkQiIZG//Q2ECkQiIREAkAiIREImASAREIiASAZEIiOTX7sH9fnnZPbo/z8+7R2UCkQiIREAkAiIREImASAREIiASAZEIiERAJAIiERCJgEgERCIgEgGRCIhEQCQCIhEQiYBIBEQiIBIBkQiIREAkAiIREImASAREIiASAZEIiERAJAIiERCJgEgERCIgEgGRCIhEQCQCIhEQiYBIBEQiIBIBkQiIREAkAiIREImASAREIiASAZEIiERAJAIiERCJgEgERCIgEgGRCIhEQCQCItmPh8NruwRbZgKRCIhEQCQCIhEQiYBIBEQiIBIBkTwNx+O+XYKt+teOCUQiIBIB0QOyD2Kut2ZMIBIBsUxAljGmet+KCUTyISBTiEs+N2ICkXwJyBTinFNtnJxAImJqE5YwkrMBmUJMaeHbCSQihgvHfS4uYSLarmHCWbFJeyARbc8w8aDh5E20iLZjmHFKdda3MBGt3zDziPPsr/EiWq/hivPx6UC9v4ZZhzIU0g+JptHjq+/hYo/0mEaPZakP/+LPhAnpZ1t61bjpQ4Vi+hluudW461OpgtrdxT33pn8BVRqgFvL1WfYAAAAASUVORK5CYII=',
);

class _FakePlatformBridge extends PlatformBridge {
  _FakePlatformBridge(this.apps);

  final List<InstalledApp> apps;

  @override
  Future<List<InstalledApp>> listInstalledApps() async => apps;
}

void main() {
  test('the catalog adopts real packages, labels and icon bytes', () async {
    final catalog = AppCatalog(
      supported: true,
      platform: _FakePlatformBridge([
        InstalledApp(
          packageName: 'com.example.maps',
          label: 'Maps',
          iconBytes: _redIcon,
        ),
        InstalledApp(packageName: 'com.example.alarm', label: 'Alarm'),
      ]),
    );

    await catalog.load();

    expect(catalog.loaded, isTrue);
    expect(catalog.installed.map((a) => a.label), ['Alarm', 'Maps']);
    final maps = catalog.installed.last;
    expect(maps.isInstalledApp, isTrue);
    expect(maps.intentPackage, 'com.example.maps');
    expect(maps.iconBytes, _redIcon);
    expect(maps.id, 'app:com.example.maps');
    expect(catalog.installed.first.iconBytes, isNull);
  });

  testWidgets('the badge paints the platform icon, not a substitute glyph', (
    tester,
  ) async {
    final action = NestAction.installed(
      packageName: 'com.example.red',
      label: 'Red',
      iconBytes: _redIcon,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('badge'),
            child: NestAppBadge(action: action, size: 80),
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(NestAppBadge));
    await tester.runAsync(() async {
      await precacheImage(MemoryImage(_redIcon), context);
    });
    await tester.pump();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('badge')),
    );
    late ui.Image image;
    late ByteData pixels;
    await tester.runAsync(() async {
      image = await boundary.toImage(pixelRatio: 1);
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    addTearDown(image.dispose);

    // Sample inside the badge but outside the white bar. A fallback badge
    // would be grey/blue and would fail this; the point is that these pixels
    // came from the byte array.
    final offset = (20 * 80 + 20) * 4;
    final r = pixels.getUint8(offset);
    final g = pixels.getUint8(offset + 1);
    final b = pixels.getUint8(offset + 2);
    expect(r, greaterThan(150));
    expect(g, lessThan(100));
    expect(b, lessThan(100));
  });

  testWidgets('the drawer filters installed apps by label', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final metrics = NestMetrics.forSize(const Size(1280, 800));
    final apps = [
      NestAction.installed(packageName: 'com.example.alarm', label: 'Alarm'),
      NestAction.installed(
        packageName: 'com.example.maps',
        label: 'Maps',
        iconBytes: _redIcon,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: AppDrawer(
            metrics: metrics,
            palette: AmbientPalette.at(9.75),
            actions: apps,
            reveal: 1,
            onActionTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Alarm'), findsOneWidget);
    expect(find.text('Maps'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'map');
    await tester.pump();

    expect(find.text('Maps'), findsOneWidget);
    expect(find.text('Alarm'), findsNothing);
  });
}
