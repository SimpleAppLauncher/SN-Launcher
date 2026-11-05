# Changelog

## Unreleased

### Performance

- **Removed per-frame rebuilds during sheet and drawer drags.** The launcher
  sheet's badge row, divider and quick settings are now built once and cached
  as an `AnimatedBuilder.child`; the drag only moves the cached layer. The
  installed-app drawer grid is cached the same way. Previously both surfaces
  were reconstructed on every pointer move, which is the likely cause of the
  delayed, laggy feel on lower-end tablets.
- **Reset the carousel drag distance at gesture start and cancel**, so a
  cancelled or interrupted drag cannot leave a stale offset behind.
- **Use `DragStartBehavior.down` for the carousel gesture**, so once Android's
  touch slop is crossed the page catches up to the finger instead of starting
  from the post-slop position.

This is an automated-test-only fix for now: `flutter analyze` is clean and the
full suite passes (287 passed, 1 skipped). ADB was offline, so it has not been
smoke-tested on the T20 in this pass.

## 0.3.0 — 2026-11-02

The first release-signed build. `versionName` is 0.3.0; the base
`versionCode` is 9001. Six per-ABI APKs are built from the same Dart source:
the shipping `reduced` build and the all-features `ef` build, each for
arm64-v8a, armeabi-v7a and x86_64. The Android ABI split offsets make the
installed codes 11001, 10001 and 13001 respectively; see
[`docs/BUILDS.md`](docs/BUILDS.md).

### Added

- **Time-based themes.** When the theme is set to Dynamic, Settings →
  Appearance can add windows such as “Night from 22:00 until 06:00”. Windows
  can wrap past midnight. Malformed stored entries are dropped, and the
  schedule survives a restart. The editor is hidden while a theme is pinned.
- **Real installed-app dock and drawer.** The launcher reads launcher
  activities from Android's `PackageManager`, paints the package's own icon
  bytes, and opens the package by name. The built-in action set remains the
  fallback where no package manager is available.
- **Android now-playing strip and external transport.** With Notification
  access granted, the strip shows the active media session and exposes only
  the transport actions the session advertises. Play/pause/next and live track
  replacement were exercised with Spotify on the Nokia T20.
- **Rotating photo frame.** A licence-filtered pool of Wikimedia Commons
  photographs with a local cache, so the frame keeps working without a fresh
  download every time.
- **Release pipeline.** `android/app/build.gradle.kts` reads a local,
  gitignored `android/key.properties` and signs release builds with the
  project keystore. Without that file it falls back to debug signing so a
  clean clone still builds; that fallback is not upgrade-compatible with the
  published release.
- **Release artifacts.** Six versioned APKs and a `SHA256SUMS` file are built
  into `dist/` (gitignored). They are signed by
  `CN=SN-Launcher, OU=Android, O=SimpleAppLauncher, C=US`, SHA-256
  `94d75bcb19143281e16a98393b81f2467c3bd528632c696ffde8b3bdf4951804`.

### Changed

- The two build variants now share one release-signing path while keeping
  their separate application IDs (`dev.snlauncher.snlauncher` and
  `dev.snlauncher.snlauncher.ef`).
- README, `INFO.md`, `docs/BUILDS.md` and `docs/STATUS.md` now record the
  0.3.0 version, per-ABI offsets, release certificate and the real
  verification state instead of the old debug-signing warnings.
- `docs/STATUS.md` now separates the exact 0.3.0 build from earlier
  hardware evidence.

### Verification

- `flutter analyze`: no issues.
- `flutter test`: 287 passed, 1 skipped.
- Release APKs: built for both variants and all three ABIs; application IDs,
  `versionName`, version codes and release signatures verified from the files
  with `aapt2` and `apksigner`.
- Hardware evidence carried forward: the now-playing strip, transport and live
  track replacement were observed on the Nokia T20 with Spotify and
  Notification access; the real installed-app dock/drawer and live photo were
  used in the T20 promo captures. Earlier hardware checks cover the clock,
  calendar, to-do list, themes, settings, carousel and weather conditions.

### Not verified / not done

- The exact 0.3.0 APK set was **not installed on hardware** in this release
  pass: ADB was offline. The theme schedule is covered by widget/unit tests
  only and has not been checked on the T20.
- Package launch from the installed-app drawer was not re-run in this release
  pass.
- The voice assistant and the real NCS-SMLauncher are not verified end to end.
- The weather place name still does not resolve on the T20, so the place photo
  is absent there.
- EF-only remote control is not implemented; the `ef` build only turns on
  existing features.
- Store submission, the privacy policy/data-safety review, and a hardware
  smoke run are still pending.

Older tags are documented in the repository history (`v0.1.0` through
`v0.3.0-rc3`); they were debug-signed and are not upgrade-compatible with this
release key.
