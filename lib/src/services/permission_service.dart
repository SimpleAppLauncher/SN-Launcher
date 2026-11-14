import 'package:flutter/foundation.dart';

import 'feature_flags.dart';
import 'platform_bridge.dart';
import 'settings_store.dart';

/// The runtime permissions this launcher can ask the platform for.
///
/// The list is deliberately short. A permission is only here if some feature
/// in this app genuinely needs it, and each one is switched on by a feature
/// flag — so a build that does not have the feature does not have the
/// permission, and a build that has the feature but not the permission is a
/// build bug the settings page will say out loud.
enum AppPermission {
  /// Android 13+ notification posting: the media player's lock-screen
  /// controls. Below API 33 this exists but is always allowed.
  notifications('notifications', 'POST_NOTIFICATIONS'),

  /// The calendar behind the digest page's calendar card.
  calendar('calendar', 'READ_CALENDAR'),

  /// The device's own position, so the weather can be for where it is.
  location('location', 'ACCESS_COARSE_LOCATION'),

  /// The microphone behind the voice command.
  microphone('microphone', 'RECORD_AUDIO');

  const AppPermission(this.key, this.androidName);

  /// The name the native side knows this permission by.
  final String key;

  /// The Android permission this maps to, without the `android.permission.`
  /// prefix — the form the manifest, the build script and the permission
  /// check all use.
  final String androidName;
}

/// What the app knows about one permission.
enum PermissionState {
  /// Not asked about yet.
  unknown,

  /// The user has granted it.
  allowed,

  /// It is in this build's manifest and the user has not granted it.
  denied,

  /// The user refused and the system will not ask again, so only the app's
  /// own settings screen can change it.
  blocked,

  /// This build's manifest does not contain it, so asking is pointless.
  notInThisBuild,

  /// The platform has no such permission at all (desktop).
  notApplicable,
}

/// One permission, the feature that wants it, and why it is wanted.
@immutable
class PermissionRequirement {
  const PermissionRequirement({
    required this.permission,
    required this.feature,
    required this.title,
    required this.reason,
  });

  final AppPermission permission;

  /// The feature flag that switches this permission on. Nothing else may.
  final String feature;

  /// The name shown in the settings page.
  final String title;

  /// Why the app wants it, in words a person can weigh.
  final String reason;
}

/// Every permission this app has, and the feature behind each one.
///
/// This list is the whole of the app's appetite for private data. A
/// permission that is not in it is not requested, not declared in the
/// manifest, and not mentioned anywhere.
const kPermissionRequirements = <PermissionRequirement>[
  PermissionRequirement(
    permission: AppPermission.calendar,
    feature: 'calendar',
    title: 'Calendar',
    reason:
        'The digest card shows what is on today. Nothing is read until you '
        'allow this.',
  ),
  PermissionRequirement(
    permission: AppPermission.location,
    feature: 'weather',
    title: 'Location',
    reason:
        'So the weather can be for where this device actually is. Without it '
        'the place falls back to a rough network lookup.',
  ),
  PermissionRequirement(
    permission: AppPermission.microphone,
    feature: 'voiceCommand',
    title: 'Microphone',
    reason:
        'So the voice command can hear what you say. It listens only while '
        'you are holding the microphone button.',
  ),
  PermissionRequirement(
    permission: AppPermission.notifications,
    feature: 'music',
    title: 'Notifications',
    reason:
        'So the music player can show lock-screen controls. Android drops the '
        'media notification without it.',
  ),
];

/// The one place that knows what the app has been allowed to do.
///
/// Every other service asks the platform for a permission directly, and every
/// one of them can get the same answer for the same permission and then
/// disagree about what it means. This service exists so that the settings
/// page can tell the truth about all of them at once, and so that "not in
/// this build" is a state the app is able to say out loud.
class PermissionService extends ChangeNotifier {
  PermissionService({PlatformBridge? bridge, this.settings})
    : _bridge = bridge ?? const PlatformBridge();

  final PlatformBridge _bridge;

  /// Where the "we already asked" flag is kept.
  ///
  /// Public because a test needs to load it before asking; the service does
  /// the loading itself in the app.
  final SettingsStore? settings;

  final Map<AppPermission, PermissionState> _states = {};

  /// Permissions asked for during this run of the app.
  ///
  /// Kept in memory as well as on disk because the answer "the system will
  /// not ask again" only means "blocked" once we know we asked — and in the
  /// middle of the request we know that for certain.
  final Set<AppPermission> _askedThisRun = {};

  /// The last known state of a permission.
  PermissionState state(AppPermission permission) =>
      _states[permission] ?? PermissionState.unknown;

  /// Ask the platform about every permission, without prompting the user.
  ///
  /// Safe to call often: it does not show a dialog, it only reads what the
  /// system already knows.
  Future<void> refresh() async {
    for (final permission in AppPermission.values) {
      final probe = await _bridge.probePermission(permission.key);
      _states[permission] = _stateOf(permission, probe);
    }
    notifyListeners();
  }

  PermissionState _stateOf(AppPermission permission, PermissionProbe? probe) {
    if (probe == null) return PermissionState.notApplicable;
    if (!probe.declared) return PermissionState.notInThisBuild;
    if (probe.granted) return PermissionState.allowed;
    // The system refusing to show a dialog only means "blocked" if we have
    // asked before. Before the first ask the same signal means the opposite.
    if (!probe.canShowRationale && _hasAsked(permission)) {
      return PermissionState.blocked;
    }
    return PermissionState.denied;
  }

  /// Ask the user for one permission.
  ///
  /// Returns whether it was granted. A permission this build does not declare
  /// is never asked for: the request would come back denied with no dialog,
  /// which looks exactly like the user refusing.
  Future<bool> request(AppPermission permission) async {
    final probe = await _bridge.probePermission(permission.key);
    if (probe == null || !probe.declared) {
      _states[permission] = _stateOf(permission, probe);
      notifyListeners();
      return false;
    }

    final answer = await _bridge.requestPermission(permission.key);
    _askedThisRun.add(permission);
    await _markAsked(permission);

    final after = await _bridge.probePermission(permission.key);
    _states[permission] = _stateOf(permission, after);
    notifyListeners();
    return answer ?? false;
  }

  /// Open the app's own settings page.
  ///
  /// The only way to change a permission the user refused for good: Android
  /// will not show the dialog again, and the setting lives in the system
  /// settings screen from then on.
  Future<bool> openSettings() => _bridge.openAppSettings();

  /// The permissions the enabled features need.
  ///
  /// A feature that is switched off needs nothing, so its permission is
  /// neither requested nor mentioned.
  static List<AppPermission> requiredFor(FeatureFlags flags) => [
    for (final requirement in kPermissionRequirements)
      if (flags.isOn(requirement.feature)) requirement.permission,
  ];

  String _askedKey(AppPermission permission) => 'perm.asked.${permission.key}';

  bool _hasAsked(AppPermission permission) =>
      _askedThisRun.contains(permission) ||
      settings?.get(_askedKey(permission)) == '1';

  Future<void> _markAsked(AppPermission permission) async {
    final store = settings;
    if (store == null) return;
    if (store.get(_askedKey(permission)) == '1') return;
    await store.put(_askedKey(permission), '1');
  }
}
