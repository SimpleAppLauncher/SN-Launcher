import 'package:flutter/foundation.dart';

import '../models/nest_action.dart';
import 'platform_bridge.dart';

/// The installed-app registry behind the launcher.
///
/// The built-in [kNestActions] list is a faithful copy of a Nest Hub's
/// "Actions on Google" screen, not an inventory of what is installed on this
/// tablet. Showing it as the app drawer was the lie: those tiles open deep
/// links or do nothing, and their badges are lookalikes. This catalog asks the
/// platform for the real launcher activities and their real icons.
///
/// On a platform with no Android package manager the list stays empty and the
/// shell deliberately falls back to the built-in action set.
class AppCatalog extends ChangeNotifier {
  AppCatalog({this.platform = const PlatformBridge(), bool? supported})
    : supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final PlatformBridge platform;

  /// Whether this platform has an installed-app registry at all.
  ///
  /// Android does. Linux/macOS/Tizen do not, so the shell is allowed to fall
  /// back to the built-in action set there. On Android an empty successful
  /// query must stay empty: showing the lookalike set would be exactly the
  /// lie this catalog exists to remove.
  final bool supported;

  List<NestAction> _installed = const [];
  bool _loading = false;
  bool _loaded = false;

  /// Installed launcher apps, alphabetically. Empty until [load] completes,
  /// and permanently empty on platforms that cannot enumerate apps.
  List<NestAction> get installed => _installed;

  bool get isLoading => _loading;
  bool get loaded => _loaded;

  Future<void> refresh() async {
    if (_loading) return;
    await _reload();
  }

  Future<void> load() async {
    if (_loading || _loaded) return;
    await _reload();
  }

  Future<void> _reload() async {
    _loading = true;
    notifyListeners();
    try {
      final apps = await platform.listInstalledApps();
      final mapped = <NestAction>[
        for (final app in apps)
          NestAction.installed(
            packageName: app.packageName,
            label: app.label,
            iconBytes: app.iconBytes,
          ),
      ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      _installed = List.unmodifiable(mapped);
    } finally {
      _loading = false;
      // Refresh keeps the previous list visible until the new one arrives. Only
      // the first load leaves `loaded` false, so the shell does not flash fake
      // icons while Android is still answering.
      _loaded = true;
      notifyListeners();
    }
  }

  /// Test seam: lets the render harness exercise the real-icon layout without
  /// an Android package manager.
  @visibleForTesting
  void setForTesting(List<NestAction> apps) {
    _installed = List.unmodifiable(apps);
    _loading = false;
    _loaded = true;
    notifyListeners();
  }
}
