import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/widgets/snow_overlay.dart';

/// Where does a flake actually go?
///
/// The snow is painted by one painter that puts every flake on a lane and
/// advances it by a phase. Nothing about that code says which way is down, and
/// a snowflake that drifts up looks like a perfectly working animation until
/// you watch it for a second — the picture keeps changing either way.
///
/// So this measures it. One flake, painted on a transparent canvas, and the
/// vertical centre of mass of the pixels tells us which way it travelled.
/// There is no `fall` variable to be wrong about; the flake's painted position
/// is the whole truth.
///
/// A flake that wrapped around the edge is not a failure — it reappears at the
/// other end — so the assertion allows a wrap and says so.
void main() {
  /// The alpha-weighted centre of the painted flake, in pixels from the top.
  ///
  /// Weighted by alpha rather than "the brightest pixel" because the flake is
  /// an anti-aliased disc: its top and bottom edges have the same peak alpha
  /// as each other, and the centre is what actually matters.
  Future<double> flakeCentre(WidgetTester tester, GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // Everything that touches the engine has to happen inside runAsync: the
    // test's fake clock does not drive the raster thread, so a future awaited
    // outside this closure never completes.
    final centre = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      var weight = 0.0;
      var moment = 0.0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final a = bytes[(y * width + x) * 4 + 3];
          if (a == 0) continue;
          weight += a;
          moment += a * y;
        }
      }
      return weight == 0 ? -1.0 : moment / weight;
    });
    return centre!;
  }

  testWidgets('a flake travels downward', (tester) async {
    final key = GlobalKey();

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 300,
          child: RepaintBoundary(
            key: key,
            child: const SnowOverlay(animate: true, flakeCount: 1),
          ),
        ),
      ),
    ));
    await tester.pump();

    final first = await flakeCentre(tester, key);

    // 1.2 s of a 12 s cycle is a tenth of the fall — enough to be obvious,
    // short enough that the flake has not reached either edge.
    await tester.pump(const Duration(milliseconds: 1200));

    final second = await flakeCentre(tester, key);

    // Take the overlay off the tree so its ticker stops before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());

    // ignore: avoid_print
    print('SNOW: first centre y=$first, second centre y=$second');

    expect(first, greaterThan(0), reason: 'the flake was painted at all');
    expect(second, greaterThan(0), reason: 'the flake was painted at all');

    // Down means the centre of mass moved to a larger y. A wrap is the one
    // legitimate exception: the flake left the bottom and reappeared at the
    // top, so its centre jumped back up.
    final fell = second > first;
    final wrapped =
        second < first && first > 300 * 0.9 && second < 300 * 0.2;
    expect(
      fell || wrapped,
      isTrue,
      reason: 'the flake moved UP (from y=$first to y=$second) instead of down',
    );
  });
}
