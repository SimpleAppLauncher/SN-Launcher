import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// The licence filter, in Rust.
///
/// **Read this before assuming it is an optimisation.** It is not. A full
/// discovery pass — 100 candidates — costs about 13 microseconds of Rust; the
/// same pass costs microseconds in Dart; and then the app waits on an HTTP
/// request for hundreds of milliseconds. The Rust version is measurably faster
/// and the measurement is irrelevant to how this app feels.
///
/// It is here because the owner asked for the one genuinely pure, genuinely
/// repeated, non-UI path in this codebase to be written in Rust. It is also the
/// highest-stakes pure function in the project: it decides whether a
/// photograph may legally be put on someone's wall. A divergence between this
/// and [shouldAllowInDart] is a licensing bug, not a performance one — which
/// is why the Dart implementation is kept, unchanged and tested, and why a
/// failure to load the library is a log line rather than a crash.
///
/// What Rust cannot help with, and did not attempt: the Android platform layer
/// (`MediaSessionService`, `NotificationListenerService`, `LocationManager`).
/// Those must be Android components declared in the manifest. Rewriting them
/// is not slow, it is impossible.
class LicenceFilter {
  LicenceFilter._(this._binding) {
    _allow = _binding == null
        ? shouldAllowInDart
        : (String s) {
            try {
              return _binding.allows(s);
            } catch (_) {
              // A failure in native code must not take the photo rotation down
              // with it.
              return shouldAllowInDart(s);
            }
          };
  }

  final _RustLicence? _binding;
  late final bool Function(String) _allow;

  static LicenceFilter? _instance;

  /// Whether the Rust library is loaded and being used.
  static bool get usesRust => _instance?._binding != null;

  static bool get isLoaded => _instance != null;

  /// Loads the library once at startup. A missing or unloadable `.so` is not
  /// an error — the Dart path is identical and the app works without it.
  static void load() {
    if (_instance != null) return;
    _RustLicence? binding;
    if (Platform.isAndroid || Platform.isLinux) {
      try {
        binding = _RustLicence.open();
      } catch (e) {
        debugPrint('LicenceFilter: Rust library unavailable ($e) — using Dart');
      }
    }
    _instance = LicenceFilter._(binding);
    debugPrint(
      'LicenceFilter: ${binding == null ? 'Dart' : 'Rust'} implementation active',
    );
  }

  static LicenceFilter get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('LicenceFilter.load() has not been called');
    }
    return i;
  }

  bool allows(String licence) => _allow(licence);

  /// The reference implementation — the thing the Rust version is checked
  /// against, and what runs when the library is unavailable.
  ///
  /// Deliberately byte-for-byte the same rules, in the same order, as
  /// `licenceAllowsRedistribution` in `photo_frame_service.dart`.
  static bool shouldAllowInDart(String licence) {
    final low = licence.toLowerCase().trim();
    if (low.isEmpty) return false;

    // Share-alike first, always. "CC BY-SA 4.0" also contains "cc by", which
    // is on the allow list, so a filter that consulted the allow list first
    // would install share-alike work and call it a free licence.
    if (RegExp(r'share[\s_-]?alike|sharealike|-sa\b|sa\s*\d|\bsa\b')
        .hasMatch(low)) {
      return false;
    }
    if (RegExp(r'-nc\b|non[\s-]?commercial').hasMatch(low)) return false;
    if (RegExp(r'-nd\b|noderiv|no[\s-]?derivative').hasMatch(low)) return false;
    if (low.contains('fair use') || low.contains('non-free')) return false;

    return _allowedFragments.any(low.contains);
  }

  static const List<String> _allowedFragments = [
    'public domain',
    'cc0',
    'cc by 2.0',
    'cc by 3.0',
    'cc by 4.0',
    'cc by',
  ];
}

typedef _AllowsNative = Int32 Function(Pointer<Utf8>, UintPtr);
typedef _AllowsDart = int Function(Pointer<Utf8>, int);

class _RustLicence {
  _RustLicence(this._allows);

  final _AllowsDart _allows;

  static _RustLicence? open() {
    final lib = DynamicLibrary.open('licence_filter');
    return _RustLicence(
      lib.lookupFunction<_AllowsNative, _AllowsDart>('licence_allows'),
    );
  }

  /// Passes UTF-8, matching what the Rust side does — it calls
  /// `std::str::from_utf8` and refuses anything that is not valid.
  bool allows(String licence) {
    final ptr = licence.toNativeUtf8(allocator: malloc);
    try {
      return _allows(ptr, ptr.length) == 1;
    } finally {
      malloc.free(ptr);
    }
  }
}
