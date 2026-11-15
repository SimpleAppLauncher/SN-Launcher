import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/widgets/snow_overlay.dart';

/// Does the field of snow jump?
///
/// The snow is a wrap: a flake that falls off the bottom reappears at the
/// top, and that is fine — one flake at a time, staggered, is what snow looks
/// like. What is not fine is the *whole field* jumping at the same instant.
///
/// It did. The animation's phase ran from 0 to 1 over twelve seconds and
/// then started again, and because each flake's fall is a fraction of the
/// screen per phase, restarting the phase moved every flake at once — 97 of
/// the 120 in the default field, one of them by 94% of the screen height.
/// The field's centre of mass barely changed, which is exactly why this went
/// unnoticed: the flakes that leapt upwards and the flakes that dropped
/// slightly cancelled each other out.
///
/// So this measures what a viewer sees instead: how much of the picture
/// changes between one frame and the next. In steady motion a flake moves
/// about a pixel and a tenth, so almost nothing changes. When the field
/// teleports, most of it changes at once.
void main() {
  /// Which pixels have something painted on them, as 0/1 bytes.
  Future<Uint8List> paintedMask(WidgetTester tester, GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final mask = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      final out = Uint8List(width * height);
      for (var i = 0; i < out.length; i++) {
        out[i] = bytes[i * 4 + 3] > 0 ? 1 : 0;
      }
      return out;
    });
    return mask!;
  }

  testWidgets('the field never teleports', (tester) async {
    const width = 240.0;
    const height = 180.0;
    final key = GlobalKey();

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: RepaintBoundary(
            key: key,
            child: const SnowOverlay(animate: true),
          ),
        ),
      ),
    ));
    await tester.pump();

    // Fifteen seconds at a tenth of a second a step. Fifteen seconds is more
    // than one twelve-second cycle, so the old behaviour was guaranteed to
    // be inside the window; a tenth of a second is short enough that the
    // steady motion changes almost nothing.
    const step = Duration(milliseconds: 100);
    const samples = 150;
    var previous = await paintedMask(tester, key);
    var worst = 0.0;
    var worstAt = 0.0;
    final fractions = <double>[];

    for (var i = 1; i <= samples; i++) {
      await tester.pump(step);
      final now = await paintedMask(tester, key);
      var changed = 0;
      var painted = 0;
      for (var p = 0; p < now.length; p++) {
        final a = previous[p] == 1;
        final b = now[p] == 1;
        if (a || b) painted++;
        if (a != b) changed++;
      }
      final fraction = painted == 0 ? 0.0 : changed / painted;
      fractions.add(fraction);
      if (fraction > worst) {
        worst = fraction;
        worstAt = i * step.inMilliseconds / 1000.0;
      }
      previous = now;
    }

    // Take the overlay off the tree so its ticker stops before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());

    final sorted = [...fractions]..sort();
    final median = sorted[sorted.length ~/ 2];

    // ignore: avoid_print
    print('SNOW: worst frame-to-frame change ${(worst * 100).round()}% at '
        '${worstAt}s, median ${(median * 100).round()}%');

    // In steady motion the picture barely changes from one frame to the next,
    // and every step looks like every other. A teleport is one step that
    // changes most of the field while the rest of the run does not — so the
    // test is about the outlier, not about an absolute number that would
    // have to be re-tuned whenever the field changed.
    expect(
      worst,
      lessThan(median * 2.0),
      reason:
          'the field changed by ${(worst * 100).round()}% of the painted '
          'pixels in one frame at ${worstAt}s, against a median of '
          '${(median * 100).round()}% — the snow is resetting its position',
    );
    expect(
      worst,
      lessThan(0.60),
      reason:
          'the field changed by ${(worst * 100).round()}% of the painted '
          'pixels in one frame at ${worstAt}s',
    );
  });
}
