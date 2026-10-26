import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_icons.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';
import 'launcher_sheet.dart';
import 'nest_glyphs.dart';

/// The full app drawer reached from the See all pill.
///
/// The original Nest Hub lays this out as a six-column grid of Actions on
/// Google. This launcher keeps the visual language but changes the contents:
/// on Android the grid is the installed-app registry, and the column count
/// responds to the display instead of assuming a 1280-pixel TV panel.
///
/// The search field is not decoration. Once the drawer is a real app list it
/// can contain dozens of entries, and scrolling to find one is worse than
/// typing three letters.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.metrics,
    required this.palette,
    required this.actions,
    required this.reveal,
    required this.onActionTap,
    this.onClose,
    this.loading = false,
  });

  final NestMetrics metrics;
  final AmbientPalette palette;
  final List<NestAction> actions;

  /// 0..1 — the drawer's own entry animation, decoupled from the sheet.
  final double reveal;

  final ValueChanged<NestAction> onActionTap;

  /// Optional because the drawer is also rendered by the test harness, where
  /// there is no sheet to close.
  final VoidCallback? onClose;

  /// True while the platform is still enumerating installed apps. The drawer
  /// shows a progress indicator instead of an empty-state lie.
  final bool loading;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _controller = ScrollController();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final type = NestType(m);
    final fg = widget.palette.onSurface;

    final padding = m.px(NestMetrics.sheetPaddingX);
    final cellH = m.px(NestMetrics.gridCellHeight);
    final icon = m.px(NestMetrics.gridIconSize);
    final reveal = widget.reveal.clamp(0.0, 1.0);

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.actions
        : [
            for (final action in widget.actions)
              if (action.label.toLowerCase().contains(query)) action,
          ];

    return IgnorePointer(
      ignoring: reveal < 0.05,
      child: Opacity(
        opacity: reveal,
        child: Transform.translate(
          // A short lift on entry. The opacity alone made the drawer appear
          // rather than arrive; eight design pixels is enough to give the eye
          // a direction without turning it into a long transition.
          offset: Offset(0, (1 - reveal) * m.px(12)),
          child: ColoredBox(
            color: widget.palette.surface,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    m.px(16),
                    padding,
                    m.px(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchField(
                          controller: _search,
                          palette: widget.palette,
                          metrics: m,
                          style: type.body(color: fg),
                          onChanged: (value) => setState(() => _query = value),
                          onClear: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                      ),
                      if (widget.onClose != null) ...[
                        SizedBox(width: m.px(10)),
                        _CloseButton(
                          palette: widget.palette,
                          metrics: m,
                          onTap: widget.onClose!,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyDrawer(
                          palette: widget.palette,
                          metrics: m,
                          query: _query,
                          loading: widget.loading,
                        )
                      : GridView.builder(
                          controller: _controller,
                          padding: EdgeInsets.fromLTRB(
                            padding,
                            m.px(4),
                            padding,
                            padding,
                          ),
                          physics: const ClampingScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: m.appGridColumns,
                                mainAxisSpacing: m.px(4),
                                crossAxisSpacing: m.px(4),
                                mainAxisExtent: cellH,
                              ),
                          itemCount: filtered.length,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          itemBuilder: (context, i) {
                            final a = filtered[i];
                            return _GridCell(
                              action: a,
                              iconSize: icon,
                              label: a.label,
                              labelStyle: type.appLabel(
                                color: fg.withValues(alpha: 0.82),
                              ),
                              onTap: () => widget.onActionTap(a),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.palette,
    required this.metrics,
    required this.style,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final AmbientPalette palette;
  final NestMetrics metrics;
  final TextStyle style;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final fg = palette.onSurface;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: style,
      cursorColor: palette.onSurfaceStrong,
      decoration: InputDecoration(
        hintText: 'Search apps',
        hintStyle: style.copyWith(color: fg.withValues(alpha: 0.52)),
        prefixIcon: Icon(
          NestIcons.Search,
          size: metrics.px(24),
          color: fg.withValues(alpha: 0.70),
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: Icon(
                  NestIcons.Close,
                  size: metrics.px(22),
                  color: fg.withValues(alpha: 0.70),
                ),
              ),
        filled: true,
        fillColor: fg.withValues(alpha: 0.06),
        contentPadding: EdgeInsets.symmetric(
          horizontal: metrics.px(16),
          vertical: metrics.px(14),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(metrics.px(18)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({
    required this.palette,
    required this.metrics,
    required this.onTap,
  });

  final AmbientPalette palette;
  final NestMetrics metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close apps',
      child: Material(
        color: palette.onSurface.withValues(alpha: 0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: metrics.px(52),
            child: Icon(
              NestIcons.Close,
              size: metrics.px(24),
              color: palette.onSurfaceStrong,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDrawer extends StatelessWidget {
  const _EmptyDrawer({
    required this.palette,
    required this.metrics,
    required this.query,
    required this.loading,
  });

  final AmbientPalette palette;
  final NestMetrics metrics;
  final String query;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: SizedBox.square(
          dimension: metrics.px(28),
          child: CircularProgressIndicator(
            strokeWidth: metrics.px(3),
            color: palette.onSurface.withValues(alpha: 0.62),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: EdgeInsets.all(metrics.px(32)),
        child: Text(
          query.trim().isEmpty ? 'No apps available' : 'No apps match “$query”',
          textAlign: TextAlign.center,
          style: NestType(metrics)
              .body(color: palette.onSurface.withValues(alpha: 0.62)),
        ),
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.action,
    required this.iconSize,
    required this.label,
    required this.labelStyle,
    required this.onTap,
  });

  final NestAction action;
  final double iconSize;
  final String label;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.92,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            NestAppBadge(action: action, size: iconSize),
            SizedBox(height: iconSize * 0.14),
            Text(
              label,
              style: labelStyle,
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
