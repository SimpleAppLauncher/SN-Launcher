# 0.3.0 hardware smoke checklist

Status: **not run for this exact build.** ADB was offline during the 0.3.0
release pass. The automated suite and APK signature/version checks passed, but
that is not a substitute for this list.

Use a real Android tablet. Record the device model, Android version, build
number, and a screenshot for every pass/fail.

## Install and identity

- [ ] `adb devices -l` shows the target device.
- [ ] If an older debug-signed SN-Launcher is installed, uninstall it once
      before installing this release. Android will not upgrade across keys.
- [ ] Install `dist/SN-Launcher-0.3.0-<abi>.apk` matching the device ABI.
- [ ] `adb shell dumpsys package dev.snlauncher.snlauncher | grep -E
      'versionName|versionCode'` reports versionName `0.3.0` and a split
      versionCode (10001 / 11001 / 13001).
- [ ] `apksigner verify --print-certs` reports
      `CN=SN-Launcher, OU=Android, O=SimpleAppLauncher, C=US`.
- [ ] Set SN-Launcher as the default home app; press Home and confirm it opens.

## Home and basic shell

- [ ] Clock, date line, and weather render at the current time.
- [ ] Photo frame shows a licensed image and rotates after the configured
      interval.
- [ ] Tap the grabber / swipe up opens the launcher sheet.
- [ ] Page carousel reaches every page enabled in the build:
      reduced = home + digest; ef = home + digest + weather + music.
- [ ] Rotate the device; the manifest pins landscape and the layout stays
      usable.
- [ ] Brightness and volume controls change the device state.
- [ ] No crash or ANR after two minutes of idle use.

## Installed-app drawer

- [ ] The drawer lists installed apps with Android's real icons and labels.
- [ ] Search filters the list.
- [ ] Tapping a package launches it.
- [ ] Back/Home returns to SN-Launcher.
- [ ] A device with no package manager falls back to the built-in action set.

## Android now-playing

- [ ] Grant Notification access in Android settings.
- [ ] Start Spotify (or another media app) and play a track.
- [ ] The now-playing strip shows title, artist, and artwork.
- [ ] Play/pause and next are sent back to the media app.
- [ ] Change track in the media app; the strip updates without a restart.
- [ ] Controls the media app does not advertise are absent.
- [ ] Revoke Notification access; the strip disappears without a crash.

## Time-based theme schedule

- [ ] Set Appearance → theme to Dynamic.
- [ ] Add a window whose start/end covers the current hour and choose a theme
      different from the current time-of-day palette.
- [ ] Confirm the palette changes immediately.
- [ ] A window that wraps past midnight (for example 22:00 → 06:00) applies on
      both sides of midnight.
- [ ] A window with equal start and end is shown as never applying.
- [ ] Remove the window; the palette returns to the time-of-day theme.
- [ ] Pin a non-Dynamic theme; the schedule editor is hidden and the pinned
      theme wins.
- [ ] Force-stop and relaunch; the schedule persists.
- [ ] Corrupt/clear the saved schedule; the app starts with the plain
      time-of-day theme and does not crash.

## Settings and known rough edges

- [ ] Settings opens; theme, 24-hour, seconds, brightness, and quick-settings
      toggles survive a relaunch.
- [ ] Weather page loads conditions and does not hang.
- [ ] Known issue: the weather place name/photo may be absent on the T20; record
      whether it appears.
- [ ] Voice assistant is not verified in 0.3.0; do not check it as working.
- [ ] Real NCS-SMLauncher is not verified end to end; the music page is tested
      against the mock only.
- [ ] EF-only remote control is not implemented; do not test or claim it.

## Performance (record, do not assume)

- [ ] Cold start after first install with `am start -W`.
- [ ] Home idle CPU over 60 seconds screen-on.
- [ ] PSS with `dumpsys meminfo`.
- [ ] RAM is expected to be higher than the stock launcher; do not present it
      as a win.

## Release close-out

- [ ] Screenshots attached to the release notes.
- [ ] SHA-256 matches `dist/SHA256SUMS`.
- [ ] Keystore and `android/key.properties` backed up outside the repository.
- [ ] `git log --format='%an <%ae>' | sort -u` shows only the owner's approved
      identities.
