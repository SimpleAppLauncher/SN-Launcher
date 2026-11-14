# In-app updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An installed SN-Launcher finds, verifies and installs its own newer build, without a computer.

**Architecture:** A Dart `UpdateService` owns the state machine and talks to three injected pieces — a `UpdateFeed` (the GitHub releases list), an `UpdateDownloader` (HTTP to a file) and an `UpdateInstaller` (the sideload path, which asks the native side to verify the APK's signing certificate and hand it to Android's installer). All three are interfaces, so the whole thing is unit-testable without a network and without a device. The native side gains four channel methods and the manifest gains `REQUEST_INSTALL_PACKAGES` plus a `FileProvider`.

**Tech Stack:** Flutter (Dart), `dart:io` `HttpClient`, Kotlin `MethodChannel` (`dev.snlauncher/platform`), Flutter test.

**Spec:** `docs/superpowers/specs/2026-11-14-in-app-updates-design.md`

## Global Constraints

- Never claim a state the app did not reach: "up to date" only after a successful check; a failed check is `failed` with the reason.
- Never offer an APK that is not signed by the same certificate as the running app.
- Never offer a file whose package name is not the installed package name.
- Compare **version names**, never version codes: Flutter's per-ABI offsets make a universal APK (9001) look older than an installed arm64 build (11001) at the same version.
- Canonical asset names, and nothing else is matched:
  `SN-Launcher-<version>-<abi>.apk`, `SN-Launcher-ef-<version>-<abi>.apk`, `SN-Launcher-perf-<version>-<abi>.apk`, where `<abi>` is `arm64-v8a` | `armeabi-v7a` | `x86_64`. The historical `arm64`, `armv7` and `-beta-` tokens are never matched.
- The variant is matched by **exact applicationId**: `dev.snlauncher.snlauncher` → `SN-Launcher-`, `.ef` → `SN-Launcher-ef-`, `.perf` → `SN-Launcher-perf-`.
- The feed is `GET https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases` (the **list**, not `/releases/latest`, which returns v0.1.3).
- The downloaded APK goes in the app's **files** directory, not the cache directory.
- At most one check every 24 hours, and it is silent unless an update exists.
- No telemetry of any kind.
- Copy style in this repo: state what happened, never what was wished for. "Could not check: GitHub is unreachable", not "You are up to date".
- The project's licence is BSD 2-Clause; a fork must keep the notice.

## Review Focus

Five inputs the spec implies that no task's own test would obviously catch:

1. **The device is on a metered connection** — a 10 MB download with no confirmation is rude and expensive. → pinned in Task 2 by a test that the download only starts on an explicit call.
2. **The user's storage is nearly full** — the download fails part-way and must leave nothing behind and must not delete the installed app. → Task 2 test: a failed download leaves no `.part` file and reports the reason.
3. **The device is offline when the app starts** — the startup check must not block the launcher or throw. → Task 2 test: a failing feed during startup produces `failed` and no exception.
4. **The GitHub payload is malformed or the rate limit is hit** — the app must say so, not crash and not claim to be up to date. → Task 1 test: a body that is not JSON yields no releases; Task 2 test: a feed that throws produces `failed`.
5. **The user is on the `.perf` variant and no `SN-Launcher-perf-*` asset was ever published** — the app must say "there is no build for this device yet" and offer nothing. → Task 1 test.

---

### Task 1: The feed — parsing, versions and asset selection

**Files:**
- Create: `lib/src/services/update_feed.dart`
- Test: `test/update_feed_test.dart`

**Interfaces:**
- Consumes: nothing. Pure Dart, no Flutter platform channels.
- Produces:
  ```dart
  @immutable
  class UpdateRelease {
    const UpdateRelease({required this.tag, required this.version,
      required this.prerelease, required this.notes, required this.assets});
    final String tag;        // 'v0.4.0'
    final String version;     // '0.4.0'
    final bool prerelease;
    final String notes;       // the release body, plain text
    final List<UpdateAsset> assets;
  }

  @immutable
  class UpdateAsset {
    const UpdateAsset({required this.name, required this.url,
      required this.sha256, required this.size});
    final String name;   // 'SN-Launcher-0.4.0-arm64-v8a.apk'
    final String url;
    final String sha256; // '' when GitHub supplied no digest
    final int size;      // bytes, 0 when unknown
  }

  List<UpdateRelease> parseReleases(String body);

  bool isNewerVersion(String candidate, String installed);

  bool isPreReleaseVersion(String version);

  String expectedAssetName(String applicationId, String version, String abi);

  UpdateAsset? assetFor(UpdateRelease release,
      {required String applicationId, required String abi});
  ```

- [ ] **Step 1: Write the failing tests** in `test/update_feed_test.dart`:

  - `parseReleases` on a captured real GitHub payload (two releases, one pre-release, three assets) returns both, newest first, with the tag, version, notes and assets filled in.
  - `parseReleases` on `'not json at all'` returns an empty list and does not throw.
  - `parseReleases` on `'{"message":"API rate limit exceeded"}'` returns an empty list.
  - `parseReleases` on a release whose body is `null` yields `notes` of `''`.
  - `isNewerVersion('0.4.0', '0.3.0')` is true; `isNewerVersion('0.3.10', '0.3.9')` is true; `isNewerVersion('0.3.0', '0.3.0')` is false; `isNewerVersion('0.3.0', '0.4.0')` is false.
  - `isNewerVersion('garbage', '0.3.0')` is false, and `isNewerVersion('0.4.0', 'garbage')` is false — an unparseable version is not evidence of a newer build.
  - `isPreReleaseVersion('0.4.0-rc2')` is true; `isPreReleaseVersion('0.4.0')` is false; `isNewerVersion('0.4.0-rc2', '0.3.0')` is true — the numeric triple is what compares.
  - `expectedAssetName('dev.snlauncher.snlauncher', '0.4.0', 'arm64-v8a')` is `'SN-Launcher-0.4.0-arm64-v8a.apk'`.
  - `expectedAssetName('dev.snlauncher.snlauncher.ef', '0.4.0', 'arm64-v8a')` is `'SN-Launcher-ef-0.4.0-arm64-v8a.apk'`.
  - `expectedAssetName('dev.snlauncher.snlauncher.perf', '0.4.0', 'arm64-v8a')` is `'SN-Launcher-perf-0.4.0-arm64-v8a.apk'`.
  - `expectedAssetName('com.example.other', '0.4.0', 'arm64-v8a')` is `''` — an unknown applicationId has no asset name.
  - `assetFor` picks the exact match out of a release's assets and returns null when the release has no asset for this ABI.
  - `assetFor` returns null for a release whose assets use the historical `arm64` token, even for an arm64 device.
  - `assetFor` returns null when the applicationId is not one of the three known ones.

- [ ] **Step 2: Run the test to verify it fails**

  Run: `~/flutter/bin/flutter test test/update_feed_test.dart`
  Expected: FAIL — `package:sn_launcher/src/services/update_feed.dart` does not exist.

- [ ] **Step 3: Implement `lib/src/services/update_feed.dart`**

  - `parseReleases(String body)`: `jsonDecode` inside a `try`; on any error return `const []`. Accept either a JSON array (the releases list) or a JSON object with a `releases` array. For each element read `tag_name`, `name`, `prerelease`, `body`, and `assets[]` (`name`, `browser_download_url`, `size`, `digest` where `digest` is `"sha256:<hex>"` — take the part after the colon, `''` when absent). The version is the tag with a leading `v` removed; when the tag has no `v`, the tag itself. Keep the order GitHub returned.
  - `isNewerVersion`: split on `.`, take the leading numeric part of each component (so `0.4.0-rc2` yields `0`, `4`, `0`), compare component-wise; a component that does not parse makes the whole comparison false.
  - `isPreReleaseVersion`: the version contains a `-` after the numeric part.
  - `expectedAssetName`: look the applicationId up in a `const Map<String, String>` of the three prefixes; unknown → `''`.
  - `assetFor`: build the expected name and return the asset with that exact name, or null.

- [ ] **Step 4: Run the test to verify it passes**

  Run: `~/flutter/bin/flutter test test/update_feed_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/src/services/update_feed.dart test/update_feed_test.dart
  git commit -m "Parse the release feed, compare versions and match assets by name"
  ```

---

### Task 2: The service — the state machine, the download and the install

**Files:**
- Create: `lib/src/services/update_service.dart`
- Modify: `lib/src/services/platform_bridge.dart` (add `appInfo`, `verifyUpdate`, `installUpdate`)
- Modify: `lib/src/services/settings_store.dart` (add `SettingKeys.updatePreReleases`, `SettingKeys.lastUpdateCheck`)
- Test: `test/update_service_test.dart`

**Interfaces:**
- Consumes: Task 1's `UpdateRelease`, `UpdateAsset`, `parseReleases`, `isNewerVersion`, `isPreReleaseVersion`, `assetFor`, `expectedAssetName`.
- Produces:
  ```dart
  enum UpdateStatus { idle, checking, upToDate, publishedReleaseIsOlder,
    available, downloading, readyToInstall, installing, failed, notFromHere }

  @immutable
  class AppInfo {
    const AppInfo({required this.versionName, required this.versionCode,
      required this.applicationId, required this.abi,
      required this.installer, required this.canInstallPackages});
    final String versionName;
    final int versionCode;
    final String applicationId;
    final String abi;          // 'arm64-v8a'
    final String installer;     // 'com.android.vending' or ''
    final bool canInstallPackages;
  }

  @immutable
  class UpdateVerification {
    const UpdateVerification({required this.ok, required this.reason});
    final bool ok;
    final String reason;   // '' when ok
  }

  abstract interface class UpdateFeed {
    Future<String> fetch();
  }

  abstract interface class UpdateDownloader {
    Future<void> download(String url, File target,
        {required void Function(int received, int total) onProgress});
  }

  abstract interface class UpdateInstaller {
    Future<InstallOutcome> install(File apk);
  }

  @immutable
  class InstallOutcome {
    const InstallOutcome({required this.started, required this.reason});
    final bool started;
    final String reason;
  }

  class UpdateService extends ChangeNotifier {
    UpdateService({PlatformBridge? platform, UpdateFeed? feed,
      UpdateDownloader? downloader, UpdateInstaller? installer,
      SettingsStore? settings});

    UpdateStatus get status;
    String get message;            // the sentence to show the user
    UpdateRelease? get release;    // the release on offer
    double get progress;           // 0..1 while downloading
    File? get downloaded;          // the verified APK, when ready

    Future<void> check();
    Future<void> download();
    Future<void> install();
  }
  ```

  On `PlatformBridge`:
  ```dart
  Future<AppInfo?> appInfo();
  Future<UpdateVerification> verifyUpdate(String path);
  Future<bool> installUpdate(String path);
  ```

- [ ] **Step 1: Write the failing tests** in `test/update_service_test.dart`:

  A `_FakePlatform extends PlatformBridge` overrides `appInfo`, `verifyUpdate`
  and `installUpdate`. A `_FakeFeed implements UpdateFeed` returns a fixed
  body or throws. A `_FakeDownloader implements UpdateDownloader` writes
  bytes to the target and calls `onProgress`. A `_FakeInstaller implements
  UpdateInstaller` records the file it was given.

  - `check` on a feed whose newest release is newer than the installed
    version offers it: status is `available`, `release.version` is
    `0.4.0`, and `message` contains the version.
  - `check` on a feed whose newest release is the same version leaves the
    status `upToDate` and the message says which version is latest.
  - `check` on a feed whose newest release is **older** than the installed
    version leaves the status `publishedReleaseIsOlder`, and the message
    names both versions. It must not say "up to date".
  - `check` on a feed that throws leaves the status `failed` and the
    message carries the reason. It must not say "up to date".
  - `check` on a feed whose newest release is a pre-release, with
    pre-releases not enabled, leaves the status `upToDate` but the message
    mentions that a pre-release exists. With pre-releases enabled, the
    status is `available` and the message says it is a pre-release.
  - `check` on a release with no asset for this device leaves the status
    `failed` with a message that says there is no build for this device.
  - `check` does not download anything: the downloader is never called.
  - `download` moves the status to `downloading`, ends at `readyToInstall`,
    and the progress ends at 1.
  - `download` on a downloader that throws leaves the status `failed` and
    leaves no file behind.
  - `install` calls the installer with the downloaded file and leaves the
    status `installing`.
  - `install` when the platform says the app was installed by the Play
    Store leaves the status `notFromHere`.
  - `check` respects the 24-hour stamp: with a stamp written moments ago,
    the feed is not called at all.

- [ ] **Step 2: Run the test to verify it fails**

  Run: `~/flutter/bin/flutter test test/update_service_test.dart`
  Expected: FAIL — the service does not exist.

- [ ] **Step 3: Implement `lib/src/services/update_service.dart`**

  - The constructor takes the four injected pieces and defaults them to the
    real ones: the platform bridge, a feed that fetches
    `https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases` with
    a `User-Agent` header, a downloader built on `HttpClient`, and an
    installer built on the platform bridge.
  - `check()`: skip entirely when the stored `lastUpdateCheck` stamp is less
    than 24 hours old, and set the status to `failed` with the reason when
    the platform has no app info (desktop). Otherwise set `checking`, read
    the feed, parse it, and pick the first release that is newer than the
    installed version, preferring a stable release over a pre-release. If
    there is no such release, compare the newest release with the installed
    version: equal or newer means `upToDate`, older means
    `publishedReleaseIsOlder`. A release with no asset for this
    applicationId and ABI means `failed` with "There is no build for this
    device yet." Every path writes the `message` string the UI shows and
    stamps `lastUpdateCheck`.
  - `download()`: set `downloading`, download to `<files dir>/update.apk.part`,
    rename to `update.apk`, verify it with `platform.verifyUpdate(path)`,
    and on a failed verification delete the file and set `failed` with the
    reason. On success set `readyToInstall`.
  - `install()`: refuse when the status is not `readyToInstall`; hand the
    file to the installer and set `installing`, or `failed` with the
    installer's reason.

- [ ] **Step 4: Add the native-facing methods to `PlatformBridge`**

  `appInfo()` calls the channel method `appInfo` and returns null when the
  platform answers with nothing. `verifyUpdate(path)` calls `verifyUpdate`
  with `{'path': path}` and returns `UpdateVerification(ok: false, reason:
  'Could not check the download.')` when the platform does not answer.
  `installUpdate(path)` calls `installUpdate` with `{'path': path}` and
  returns false when the platform does not answer.

- [ ] **Step 5: Add the settings keys**

  In `SettingKeys`: `static const updatePreReleases = 'updatePreReleases';`
  and `static const lastUpdateCheck = 'lastUpdateCheck';`

- [ ] **Step 6: Run the test to verify it passes**

  Run: `~/flutter/bin/flutter test test/update_service_test.dart`
  Expected: PASS.

- [ ] **Step 7: Run the whole suite**

  Run: `~/flutter/bin/flutter test`
  Expected: all tests pass, none skipped.

- [ ] **Step 8: Commit**

  ```bash
  git add lib/src/services/update_service.dart lib/src/services/platform_bridge.dart lib/src/services/settings_store.dart test/update_service_test.dart
  git commit -m "Add the update service, its states and the download it verifies"
  ```

---

### Task 3: The native side — the signature check and the installer

**Files:**
- Modify: `android/app/src/main/kotlin/dev/snlauncher/snlauncher/PlatformBridge.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/res/xml/file_paths.xml`
- Create: `android/app/src/main/kotlin/dev/snlauncher/snlauncher/UpdateInstaller.kt`

**Interfaces:**
- Consumes: Task 2's channel method names `appInfo`, `verifyUpdate`,
  `installUpdate` and their argument maps.
- Produces: the native answers to those three methods.

- [ ] **Step 1: Implement `appInfo` in `PlatformBridge.kt`**

  Read the package info with
  `packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)`:
  `versionName`, `versionCode`, `applicationId` (from `context.packageName`),
  `abi` from `Build.SUPPORTED_ABIS[0]`, `installer` from
  `packageManager.getInstallSourceInfo(packageName).installingPackageName`
  (empty string when there is none), and `canInstallPackages` from
  `packageManager.canRequestPackageInstalls()` on API 26+ and true below it.

- [ ] **Step 2: Implement `verifyUpdate` in `PlatformBridge.kt`**

  Three checks, each returning `{"ok": false, "reason": "..."}`:
  1. the candidate's package name is the installed package name;
  2. the candidate's signing certificate digest equals the installed app's
     (`PackageManager.GET_SIGNING_CERTIFICATES`, comparing the SHA-256 of the
     signer) — the reason names the mismatch rather than saying "corrupt";
  3. the candidate's `versionName` is newer than the installed one.
  On success return `{"ok": true, "reason": ""}`.

- [ ] **Step 3: Implement `installUpdate` in `PlatformBridge.kt`**

  Build an `Intent(Intent.ACTION_INSTALL_PACKAGE)` with the file URI from
  the `FileProvider` for the app's files directory and
  `FLAG_GRANT_READ_URI_PERMISSION`, and start it. When
  `packageManager.canRequestPackageInstalls()` is false, return
  `{"started": false, "reason": "SN-Launcher needs permission to install updates"}`
  and do not start anything.

- [ ] **Step 4: Declare the permission and the FileProvider**

  In `AndroidManifest.xml`, add
  `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>`
  and a `<provider>` with
  `android:name="androidx.core.content.FileProvider"`,
  `android:authorities="${applicationId}.updates"`,
  `android:exported="false"`,
  `android:grantUriPermissions="true"` and a `meta-data` pointing at
  `@xml/file_paths`. Create `res/xml/file_paths.xml` with a `files-path` for
  `update.apk`.

- [ ] **Step 5: Build the APK and confirm it compiles**

  Run: `tool/build_variants.sh reduced`
  Expected: the APK builds, and `tool/verify_permissions.sh` reports the
  reduced build declaring exactly `READ_CALENDAR,RECORD_AUDIO` — the new
  permission is not a runtime permission and is not in that set.

- [ ] **Step 6: Commit**

  ```bash
  git add android/app/src/main/kotlin/dev/snlauncher/snlauncher/PlatformBridge.kt android/app/src/main/AndroidManifest.xml android/app/src/main/res/xml/file_paths.xml
  git commit -m "Verify the downloaded APK's signature and hand it to the installer"
  ```

---

### Task 4: The Settings section the user reads

**Files:**
- Create: `lib/src/widgets/update_section.dart`
- Modify: `lib/src/widgets/settings_page.dart`
- Test: `test/update_section_test.dart`

**Interfaces:**
- Consumes: Task 2's `UpdateService` and its `UpdateStatus` values.
- Produces: `UpdateSection({required UpdateService updates, required NestMetrics metrics, required NestType type, required AmbientPalette palette})`, a widget that renders one `_Section` in the house style.

- [ ] **Step 1: Write the failing widget test** in `test/update_section_test.dart`:

  Render the section against a service in each status and assert the text:
  - `idle` → "Never checked."
  - `checking` → "Checking…"
  - `upToDate` → the installed version and the word "latest"
  - `publishedReleaseIsOlder` → both version numbers, and **not** "latest"
  - `available` → the new version and a "Download and install" button
  - `downloading` → a progress indication
  - `readyToInstall` → an "Install" button
  - `failed` → the service's `message`
  - `notFromHere` → a message naming the Play Store
  In every state, the text must not contain "up to date" unless the status
  is `upToDate`.

- [ ] **Step 2: Run the test to verify it fails**

  Run: `~/flutter/bin/flutter test test/update_section_test.dart`
  Expected: FAIL — the widget does not exist.

- [ ] **Step 3: Implement `lib/src/widgets/update_section.dart`**

  A `_Section` in the same shape as the settings page's own: a container with
  `palette.surface`, a 20 px radius, a hairline border, an icon
  (`NestIcons.SystemUpdateAlt` if it exists, otherwise `NestIcons.Refresh`)
  and the title "Updates". Inside it: the current version, the status text,
  a "Check for updates" `OutlinedButton` with a `StadiumBorder` and
  `EdgeInsets.symmetric(horizontal: m.px(16))`, a pre-release `_ToggleRow`,
  and — only in `available` — the release notes and a "Download and install"
  button.

- [ ] **Step 4: Wire it into `settings_page.dart`**

  Add `final UpdateService? updates;` to `SettingsPage`, include it in the
  `Listenable.merge` in `build()`, and add the section to the scroll column
  after `_assistant`. The section renders only when `updates != null`, and
  on a desktop build it is hidden entirely (the service reports
  `notApplicable` there).

- [ ] **Step 5: Run the test to verify it passes**

  Run: `~/flutter/bin/flutter test test/update_section_test.dart`
  Expected: PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/src/widgets/update_section.dart lib/src/widgets/settings_page.dart test/update_section_test.dart
  git commit -m "Show the update state in Settings, and say what actually happened"
  ```

---

### Task 5: Wiring — the startup check, the toast and the service's life

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/src/screens/nest_shell.dart`
- Modify: `lib/src/widgets/settings_page.dart`

**Interfaces:**
- Consumes: Task 2's `UpdateService` and Task 4's `UpdateSection`.
- Produces: `NestShell` gains an `updates` parameter; `main.dart` creates the
  service, passes it to the shell, and runs the check off the critical path.

- [ ] **Step 1: Create the service in `main.dart`**

  Build an `UpdateService` with the app's `SettingsStore` and pass it to
  `NestShell(updates: …)` and to `SettingsPage(updates: …)`.

- [ ] **Step 2: Run the check off the critical path**

  After the first frame, `unawaited(_updates.check())`. The check writes its
  own 24-hour stamp, so it runs at most once a day.

- [ ] **Step 3: Say something when there is an update**

  When the service reports `available`, the shell shows a toast with the new
  version's number. Nothing is shown for any other status — in particular,
  nothing at all when there is no update.

- [ ] **Step 4: Run the whole suite and the analyzer**

  Run: `~/flutter/bin/flutter test && ~/flutter/bin/flutter analyze`
  Expected: all tests pass; no issues found.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/main.dart lib/src/screens/nest_shell.dart lib/src/widgets/settings_page.dart
  git commit -m "Check for an update at startup, and say so only when there is one"
  ```

---

### Task 6: The release process, and the two false claims in the docs

**Files:**
- Create: `tool/publish_release.sh`
- Modify: `README.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/BUILDS.md`

**Interfaces:**
- Consumes: Task 1's canonical asset names.
- Produces: a script that publishes a stable release whose assets the
  updater can match.

- [ ] **Step 1: Write `tool/publish_release.sh`**

  It builds both variants with `tool/build_variants.sh`, runs
  `tool/verify_permissions.sh` on every APK and **stops** if one fails,
  copies each APK to the canonical name
  (`SN-Launcher-<version>-<abi>.apk`, `SN-Launcher-ef-<version>-<abi>.apk`),
  writes `SHA256SUMS`, and creates a **stable** release (not a pre-release)
  with `gh release create`. It refuses to publish a release whose tag is
  already taken.

- [ ] **Step 2: Correct the README's download section**

  The table currently advertises `SN-Launcher-0.3.0-arm64-v8a.apk` and
  friends, which exist in no release. Replace it with the files that
  actually exist, and correct the claim "These APKs are signed with the
  project's release key" — every published APK is signed with the **debug**
  key (`CN=Android Debug`), and the release key starts signing with the
  first release-key-signed release, which means a one-time uninstall and
  reinstall.

- [ ] **Step 3: Correct `docs/STATUS.md`**

  The line saying ADB is offline is false: a Nokia T20 is attached. Replace
  it with what is true, and add the update system's built/verified/not
  verified rows.

- [ ] **Step 4: Check the script parses**

  Run: `bash -n tool/publish_release.sh`
  Expected: no output.

- [ ] **Step 5: Commit**

  ```bash
  git add tool/publish_release.sh README.md docs/STATUS.md docs/BUILDS.md
  git commit -m "Publish releases the updater can find, and correct the download section"
  ```

---

### Task 7: On the device — the whole thing, verified for real

**Files:**
- Modify: `docs/STATUS.md` (the verification table only)

**Interfaces:**
- Consumes: everything above.
- Produces: evidence in `docs/STATUS.md` that says what was seen on the T20.

- [ ] **Step 1: Install the release-key-signed build**

  Uninstall the debug-signed `dev.snlauncher.snlauncher` from the T20
  (this wipes that install's settings, which is the documented one-time
  cost), then install the APK built in Task 3. Confirm with
  `adb shell dumpsys package dev.snlauncher.snlauncher` that the installed
  version is the new one.

- [ ] **Step 2: Publish a release the device can find**

  Run `tool/publish_release.sh` for a test tag, and confirm the release
  appears in the GitHub releases list as a **stable** release with the
  canonical asset names.

- [ ] **Step 3: Watch the app find it**

  Open Settings → Updates on the T20, press "Check for updates", and
  confirm the section shows the new version and a download button.

- [ ] **Step 4: Download and install it**

  Press the download button, watch the progress, and confirm the app
  reports the APK's signature matched. Grant "install unknown apps" when
  Android asks, and confirm the installer's confirmation appears and the
  device ends up on the new version.

- [ ] **Step 5: Check the failure path for real**

  Install a candidate APK signed with a different key and confirm the app
  refuses it and says which check failed, rather than offering the install.

- [ ] **Step 6: Verify the work shipped earlier in the same round**

  On the same device: the microphone permission dialog and the voice
  command, the calendar card with its permission granted, the countdown
  timer, the Permissions section, and the music player's notification.

- [ ] **Step 7: Record what was seen**

  Update `docs/STATUS.md` so every row says either "seen on the T20" with
  what was seen, or "not verified" — and nothing else.

- [ ] **Step 8: Commit**

  ```bash
  git add docs/STATUS.md
  git commit -m "Record what the update system did on the T20"
  ```

---

## Self-review

**Spec coverage:** §7.1 feed → Task 1 and Task 2. §7.2 asset contract → Task 1
and Task 6. §7.3 version comparison → Task 1. §7.4 download → Task 2. §7.5
verification → Task 2 and Task 3. §7.6 install → Task 3. §7.7 Play install →
Task 2 and Task 4. §7.8 the wording → Task 4. §7.9 the seam → Task 2's
`UpdateInstaller` interface. §8 the release process → Task 6. §9 testing →
Tasks 1, 2, 4 and 7. §10 risks → Task 3 and Task 6. The two owner decisions
(release key now, both builds) → Task 3's manifest and Task 6's publish
script. §5's "the published release is older than this build" state → Task 2.

**Gaps found and closed:** the spec's "pre-releases opt-in" needed a stored
setting — Task 2 adds `SettingKeys.updatePreReleases` and Task 4 adds the
toggle. The spec's 24-hour silence needed a stored stamp — Task 2 adds
`SettingKeys.lastUpdateCheck`. The spec's `notApplicable` on desktop was not
a listed status; Task 2 handles a missing `appInfo` by reporting `failed`
with a reason, and Task 4 hides the section when the service is absent.

**Type consistency:** `UpdateStatus`, `AppInfo`, `UpdateVerification`,
`UpdateFeed`, `UpdateDownloader`, `UpdateInstaller`, `InstallOutcome` are
defined once, in Task 2, and used by that name in Tasks 4 and 5. Task 1's
`UpdateRelease` and `UpdateAsset` are the only types Task 2 consumes.

**Review Focus:** all five lines are pinned by a named test in Task 1 or
Task 2, as written in the steps above.

**Proportion:** the plan is about a third the length of the code it
describes, and no step contains a function body.
