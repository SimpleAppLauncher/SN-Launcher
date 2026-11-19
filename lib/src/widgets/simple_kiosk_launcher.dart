import 'dart:io';

import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../services/weather_service.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';
import 'clock_block.dart';
import 'launcher_sheet.dart';
import 'nest_glyphs.dart';
import 'photo_frame.dart';

/// SimpleKioskLauncher — the barebone kiosk page.
///
/// Same visual language as the home page (photograph, scrim, clock) and the
/// app grid uses the same cells the drawer uses, so it feels like the old
/// launcher. What is gone: quick settings, suggestions, the sheet, search,
/// voice, weather artwork beyond the clock's temperature. A kiosk shows the
/// time and launches apps. That is all.
class SimpleKioskLauncher extends StatelessWidget {
  const SimpleKioskLauncher({
    super.key,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.now,
    required this.weather,
    required this.actions,
    required this.onActionTap,
    this.photoFile,
    this.heroAsset = 'assets/photo/landscape.jpg',
    this.photoCredit,
    this.albumTitle,
    this.loading = false,
    this.use24Hour = true,
    this.showSeconds = false,
    this.zoom = 1.0,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final DateTime now;
  final WeatherNow weather;
  final List<NestAction> actions;
  final ValueChanged<NestAction> onActionTap;

  /// A downloaded photograph, when rotation has one.
  final File? photoFile;

  /// Fallback photograph, used until rotation has one.
  final String heroAsset;

  /// Photographer's name. Required by the bundled photograph's licence.
  final String? photoCredit;

  /// Album caption, shown next to the credit.
  final String? albumTitle;

  /// True while the platform is still enumerating installed apps.
  final bool loading;

  final bool use24Hour;
  final bool showSeconds;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final m = metrics;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The same photo background the home page uses: picture, scrim.
        PhotoFrameBackground(
          metrics: m,
          palette: palette,
          file: photoFile,
          asset: heroAsset,
        ),
        Row(
          children: [
            // Clock, left of the grid — the home page's anchor, in the left half.
            Expanded(
              flex: 5,
              child: RepaintBoundary(
                child: ClockBlock(
                  metrics: m,
                  type: type,
                  palette: palette,
                  weather: weather,
                  now: now,
                  use24Hour: use24Hour,
                  showSeconds: showSeconds,
                  zoom: zoom,
                  animateWeather: false,
                  forceLightText: true,
                  albumTitle: albumTitle,
                  photoCredit: photoCredit,
                ),
              ),
            ),
            // The kiosk's whole reason to exist: the apps. Same cells, same
            // sizes, same look as the drawer — minus the search field and the
            // chrome, because a kiosk does not need chrome.
            Expanded(
              flex: 6,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.42),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    m.px(20),
                    m.px(48),
                    m.px(20),
                    m.px(20),
                  ),
                  child: actions.isEmpty
                      ? _KioskEmptyState(
                          metrics: m,
                          type: type,
                          palette: palette,
                          loading: loading,
                        )
                      : GridView.builder(
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: m.appGridColumns,
                            mainAxisSpacing: m.px(4),
                            crossAxisSpacing: m.px(4),
                            mainAxisExtent: m.px(NestMetrics.gridCellHeight),
                          ),
                          itemCount: actions.length,
                          addAutomaticKeepAlives: false,
                          // Same measured fix as the drawer: each cell is its own
                          // boundary, so scrolling only repaints what moved.
                          addRepaintBoundaries: true,
                          itemBuilder: (context, i) {
                            final action = actions[i];
                            return _KioskCell(
                              action: action,
                              metrics: m,
                              type: type,
                              onTap: () => onActionTap(action),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KioskCell extends StatelessWidget {
  const _KioskCell({
    required this.action,
    required this.metrics,
    required this.type,
    required this.onTap,
  });

  final NestAction action;
  final NestMetrics metrics;
  final NestType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = metrics.px(NestMetrics.gridIconSize);
    return Semantics(
      button: true,
      label: action.label,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.92,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            NestAppBadge(action: action, size: icon),
            SizedBox(height: icon * 0.14),
            Text(
              action.label,
              style: type.appLabel(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _KioskEmptyState extends StatelessWidget {
  const _KioskEmptyState({
    required this.metrics,
    required this.type,
    required this.palette,
    required this.loading,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: SizedBox.square(
          dimension: metrics.px(28),
          child: CircularProgressIndicator(
            strokeWidth: metrics.px(3),
            color: Colors.white.withValues(alpha: 0.62),
          ),
        ),
      );
    }
    // An empty answer is an answer. Do not invent rows of lookalike icons to
    // fill the grid.
    return Center(
      child: Padding(
        padding: EdgeInsets.all(metrics.px(32)),
        child: Text(
          'No apps available',
          textAlign: TextAlign.center,
          style: type.body(color: Colors.white.withValues(alpha: 0.62)),
        ),
      ),
    );
  }
}
