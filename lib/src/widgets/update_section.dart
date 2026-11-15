import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_icons.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';

/// The update card in Settings.
///
/// This is the only place the user finds out what the updater did, so what it
/// says is the feature. Two rules, and both are load-bearing:
///
///  * It never says the launcher is up to date unless the updater really
///    found that out. A failed check says why it failed.
///  * It never says an update is available unless one was found, and it never
///    says one was installed unless Android took it.
class UpdateSection extends StatelessWidget {
  const UpdateSection({
    super.key,
    required this.updates,
    required this.metrics,
    required this.type,
    required this.palette,
  });

  final UpdateService updates;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    // The service is the state. Listening to it here means the card is
    // correct wherever it is mounted, without whoever mounts it having to
    // remember to rebuild it.
    return AnimatedBuilder(
      animation: updates,
      builder: (context, _) {
        final status = updates.status;
        return Container(
          padding: EdgeInsets.all(m.px(20)),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(m.px(20)),
            // Hairline so the card still reads on a background close to its
            // own colour.
            border: Border.all(
              color: palette.onSurfaceVariant.withValues(alpha: 0.16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    NestIcons.Update,
                    size: m.px(22),
                    color: palette.onSurfaceStrong,
                  ),
                  SizedBox(width: m.px(10)),
                  Text(
                    'Updates',
                    style: type.sheetTitle(color: palette.onSurfaceStrong),
                  ),
                ],
              ),
              SizedBox(height: m.px(14)),
              // The service's own sentence. It says what happened, and the
              // service only says true things.
              Text(
                updates.message,
                style: type.body(color: palette.onSurfaceStrong),
              ),
              if (status == UpdateStatus.downloading) ...[
                SizedBox(height: m.px(12)),
                LinearProgressIndicator(
                  value: updates.progress > 0 ? updates.progress : null,
                ),
              ],
              SizedBox(height: m.px(12)),
              Wrap(
                spacing: m.px(8),
                runSpacing: m.px(8),
                children: _buttons(status),
              ),
              SizedBox(height: m.px(12)),
              _preReleaseRow(),
            ],
          ),
        );
      },
    );
  }

  /// The buttons that make sense in this state, and no others.
  ///
  /// A check is always offered: it is the one action that is never wrong. The
  /// others appear only when there is something for them to do.
  List<Widget> _buttons(UpdateStatus status) {
    final buttons = <Widget>[];

    if (status == UpdateStatus.available) {
      buttons.add(_button(
        'Download and install',
        () => updates.download(),
      ));
    }
    if (status == UpdateStatus.readyToInstall) {
      buttons.add(_button('Install', () => updates.install()));
    }

    // The check always forces: the once-a-day rule is for the startup path,
    // and a button that does nothing for a day is a broken button.
    buttons.add(_button('Check for updates', () => updates.check(force: true)));

    return buttons;
  }

  Widget _button(String label, VoidCallback onPressed) {
    final m = metrics;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: EdgeInsets.symmetric(horizontal: m.px(16)),
      ),
      child: Text(
        label,
        style: type.caption(color: palette.onSurfaceStrong),
      ),
    );
  }

  Widget _preReleaseRow() {
    final m = metrics;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pre-release builds',
                style: type.body(color: palette.onSurfaceStrong),
              ),
              SizedBox(height: m.px(2)),
              Text(
                'Offer the release candidates. They are the builds this '
                'project tests on real devices, and they are rougher.',
                style: type.caption(color: palette.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SizedBox(width: m.px(12)),
        Switch(
          value: updates.preReleasesEnabled,
          onChanged: updates.setPreReleasesEnabled,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}
