# In-app updates — design

**Date:** 14 November 2026
**Status:** approved design, ready for a plan
**Author:** written with OpenCode

**Decisions taken by the owner, 14 November 2026:**

1. **The release key starts signing today.** 0.4.0 is the first
   release-key-signed release. Every existing install uninstalls and
   reinstalls once, and loses its settings doing so. That break is
   unavoidable — Android refuses to upgrade across keys — and it is the
   price of the release key existing at all.
2. **Both builds get the updater**, reduced included, so the shipping APK
   carries `REQUEST_INSTALL_PACKAGES`.

---

## 1. Intent and the why

An installed SN-Launcher should be able to update itself without a computer.

Today the install path is: download an APK from the Releases page, copy it to
the tablet, tap it, and allow "install unknown apps". Every update since
0.1.0 has been that. It works, and it is the reason the project has one star.

Three things make it a problem rather than a quirk:

1. **Android is closing the door on it.** Since 30 September 2026 — live in
   Brazil, Indonesia, Singapore and Thailand, with a global rollout across
   2027 — an app installed on a certified Android device must come from a
   registered developer. Sideloading still works through ADB or through an
   "advanced flow" that takes 24 hours and a warning screen per install. The
   APK you host yourself stops being a normal install path.
2. **It is the wall in front of every non-technical user.** Somebody who
   wants a wall display for their kitchen is not going to run `adb install`,
   and is not going to do it again every eight weeks.
3. **It is the wall in front of money.** A café with six tablets cannot ask
   staff to sideload an APK when the release changes, and a refurbisher
   cannot ship six different versions. The commercial version of this product
   — a managed fleet of cheap tablets running a wall display — needs the
   device to fetch its own updates. This is the same gap the EF build's LAN
   remote control points at.

Google's own policy explicitly permits this: `REQUEST_INSTALL_PACKAGES` is
allowed for apps whose core functionality is self-update, and the Play
in-app updates API exists for the same reason.

## 2. Goals

| | |
|---|---|
| G1 | The app finds out a newer build exists, without the user going to a releases page |
| G2 | The app can fetch it and hand it to Android's installer, in the app, with the user's approval |
| G3 | It refuses to install anything not signed by the same key as the running app |
| G4 | It never claims something it did not do: "up to date" only after a check that actually succeeded |
| G5 | It picks the right asset for its own variant and ABI, in both builds |
| G6 | It costs nothing when there is no update: one small request, no polling, no telemetry |

## 3. Non-goals

- No automatic download on a metered connection, and no silent install.
  Ever.
- No delta or patch updates. A 10 MB APK over a café's wifi is fine.
- No rollout percentages, staged releases or A/B buckets.
- No remote push to a fleet. That is the commercial feature and it is a
  separate project with a server behind it.
- No update telemetry. The app will not report who updated, from where, or
  whether they did.

## 4. Anti-goals — what would make this a failure even if it worked

- Installing an APK that is not signed by the same key as the running app.
- Telling a user "you are up to date" when the check failed, was rate-limited,
  or never ran.
- Telling a 0.3.0 install that 0.1.3 is the latest build.
- Downloading 10 MB every launch to discover there is nothing new.
- Making the launcher unusable when GitHub is unreachable.
- Turning the shipping build into something Play will reject over a
  permission it does not need.

## 5. The state of the world this has to work in

Facts, verified on 14 November 2026, not assumptions:

| Fact | Consequence |
|---|---|
| **Every published APK is debug-signed.** `SN-Launcher-0.1.3-arm64.apk` verifies as `CN=Android Debug`, SHA-256 `8ab93dd4…` — the local debug keystore. The release key (`CN=SN-Launcher`, `94d75bcb…`) exists on the build machine and **has never signed anything published**. | 0.4.0 is the first release-key-signed release. Every existing install uninstalls once and loses its settings. The README's claim that the downloads are release-signed is false and gets fixed in the same change. |
| **There is no stable v0.3.0.** Only `v0.3.0-rc1`, `rc2`, `rc3`, all pre-releases, and `rc3` carries desktop tarballs only. `GET /releases/latest` returns **v0.1.3**. | The feed cannot be `/releases/latest`. A stable release has to be published, and until one exists the app must be able to say "the published release is older than this build" without lying. |
| **Three asset naming schemes are live.** Published: `SN-Launcher-0.3.0-rc2-arm64.apk`, `-armv7`, `-beta-arm64`, `-x86_64`, plus a universal. Build script: `sn-launcher.ef-arm64-v8a-release.apk`. README: `SN-Launcher-0.3.0-arm64-v8a.apk`. None is what the other expects. | One canonical scheme, chosen below. The publish script and the matcher must produce and read the same thing, and the README's table gets corrected to files that exist. |
| **Three applicationIds are installed on one device**: `dev.snlauncher.snlauncher`, `.ef` and `.perf`. | The variant must be matched by exact applicationId, never by a suffix heuristic — `.perf` would be mistaken for reduced. |
| **A Nokia T20 (Android 13, arm64-v8a) is attached.** All three variants installed, versionCode 11000, minSdk 24, targetSdk 36. | The signature check and the whole install path can be **verified on hardware**. This is no longer a "written but unverified" feature. |
| **Version codes carry Flutter's per-ABI offset**: base 9001 → armeabi-v7a 10001, arm64-v8a 11001, x86_64 13001, and a universal APK is the bare 9001. | Comparing version codes across builds is unreliable. The comparison is on **version name**, which is the same string before and after the download. |

## 6. Approaches considered

### A. In-app updater against the project's GitHub Releases (chosen)

The app asks GitHub for the latest release, compares the version with its
own, downloads the matching asset, checks the signature, and hands the file
to Android's installer.

*Pro:* the update path is the product, not a script the user has to run.
The release already exists and is already published where the app can reach
it. One feature, no server, no account.

*Con:* it needs `REQUEST_INSTALL_PACKAGES`, which Play scrutinises, and it
needs the user to grant "install unknown apps" to the launcher once.

### B. An external updater (Obtainium, F-Droid style)

Publish the APKs and let the user point Obtainium at the repository.

*Pro:* zero code in the launcher, no extra permission, and the verification
story is somebody else's problem.

*Con:* it adds a second app to the install path for people who do not know
what Obtainium is, and it is still "copy something from a releases page" —
the same manual step with a different UI. It does not make the product
self-sufficient, so it does not unlock the fleet case.

*This stays in the README as an alternative. It is the right answer for a
hobbyist and the wrong one for a customer.*

### C. Play in-app updates

The Play API handles the whole thing, with Google's download and install
machinery, and no permission to defend.

*Pro:* the least code and the least risk of a bad install.

*Con:* it only works if the app is on Play, and being on Play is a decision
that has not been made. Today the app is distributed from GitHub Releases,
and the Play route needs a developer account, a privacy policy, a data-safety
form, a notification-listener declaration and a store listing.

**Chosen: A**, with the Play path left as an explicit seam — the installer
step is an interface, so a Play implementation can replace the sideload one
without touching the feed, the comparison or the UI.

## 7. The how

### 7.1 Where the update comes from

`GET https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases`

— the full list, not `/releases/latest`, because every release this project
has published for 0.2.0 onwards is a pre-release and `/releases/latest`
returns v0.1.3.

*Why the API and not a hand-written `latest.json` file:* the release already
exists and is already published, so there is no second artefact to publish
and no way to forget to publish it. A static file would be cheaper (no rate
limit, works behind a shared NAT) but it is a thing that can silently fall
out of step with the release, and this project does not ship things that
silently fall out of step.

*Rate limit:* the unauthenticated API allows 60 requests an hour per IP. The
app checks at most once every 24 hours, so a hundred tablets behind one
café wifi use about four an hour. Documented where it is used.

*Which release the app looks at:*

| The release is | The app |
|---|---|
| a stable release, newer than the installed build | offer it |
| a stable release, older than or equal to the installed build | "the published release (X) is older than this build (Y)" — never "you are up to date" |
| a pre-release, and the user has not asked for pre-releases | "X-rcN is available as a pre-release" with a way to opt in |
| a pre-release, and the user has opted in | offer it, labelled as a pre-release |

### 7.2 The asset naming contract

One scheme, from now on, produced by the publish script and read by the
matcher:

```
SN-Launcher-<version>-<abi>.apk          # reduced
SN-Launcher-ef-<version>-<abi>.apk       # ef
SN-Launcher-perf-<version>-<abi>.apk      # the .perf variant, when it is published
SHA256SUMS
```

`<abi>` is the Android ABI name: `arm64-v8a`, `armeabi-v7a`, `x86_64`. These
are exactly `Build.SUPPORTED_ABIS[0]` on the device, which is what makes the
match exact rather than a guess. The old `arm64` / `armv7` / `-beta-` tokens
are historical and are not matched.

The variant is matched by **exact applicationId**, through one table:

| applicationId | asset prefix |
|---|---|
| `dev.snlauncher.snlauncher` | `SN-Launcher-` |
| `dev.snlauncher.snlauncher.ef` | `SN-Launcher-ef-` |
| `dev.snlauncher.snlauncher.perf` | `SN-Launcher-perf-` |

An applicationId that is not in the table — or a release with no asset for
this device's ABI — reports "there is no build for this device yet" and
offers nothing. It never offers a file that cannot run.

### 7.3 Is it newer

The release's version and the installed app's `versionName` are compared
component-wise as numbers: `0.4.0` > `0.3.10`, `0.3.0` is not newer than
`0.3.0`. A pre-release suffix (`0.4.0-rc2`) is compared on its numeric
triple and labelled as a pre-release.

A version that does not parse is not offered — an unparseable version is not
evidence of a newer build.

**Version name, not version code.** The two disagree: the tag is
`v0.3.0-rc2`, the asset says `0.3.0-rc2`, and the APK's own manifest says
`0.3.0`. The manifest is the one the running app reports, and it is the same
string before and after the download. Version codes are not compared,
because Flutter's per-ABI offsets make a universal APK (9001) look older
than an installed arm64 build (11001) at the same version.

### 7.4 Download

`dart:io`'s `HttpClient` to the app's own **files** directory — not the
cache directory, which Android may clear, and the installer replaces the
process — written to a `.part` file and renamed when complete, with a
progress callback for the UI. Abortable. A failed download leaves nothing
behind and reports the reason.

The asset's SHA-256 from the release's `digest` field is checked against the
downloaded bytes. That is a corruption check; the signature check below is
the one that establishes provenance.

### 7.5 Verification — the part that matters

Before the installer is ever shown, three checks run natively against the
downloaded file:

1. **The signing certificate is the installed app's.** This is the one that
   matters: it means the file came from whoever signed the app you are
   running, and a tampered download or a hostile mirror cannot get past it.
   It also means a debug-signed build refuses a release-signed update, which
   is correct — a debug build must not silently become a release one. After
   the key switch (0.4.0) this is always a release key, and the message for
   a mismatch says so plainly.
2. **The package name is the installed package name.** A reduced build must
   not be offered the ef build.
3. **The version name is newer.** The same comparison as 7.3, run against
   the downloaded APK's own manifest rather than the release tag, so a
   release that lies about its tag cannot downgrade an install.

A failure of any of them refuses the update and says which one failed. The
file is deleted.

### 7.6 Install

`FileProvider` hands the APK to `ACTION_INSTALL_PACKAGE`.

- On Android 8+ the app must also hold "install unknown apps", which is a
  special access, not a dialog. If it is missing, the app opens
  `ACTION_MANAGE_UNKNOWN_APP_SOURCES` for this package and says what it is
  asking for, then the install is retried.
- Below Android 8 the old global "unknown sources" setting applies and there
  is nothing to request.
- The manifest gains `REQUEST_INSTALL_PACKAGES` and a `FileProvider`.

### 7.7 If the app came from the Play Store

Android reports which package installed the app. If that is the Play Store,
the updater does not try to sideload over it: it says the update comes from
the Play Store and opens the listing. No fake, no dead button.

### 7.8 What the user sees

**Settings → Updates.** The current version, a "Check for updates" button,
when the last check happened, and the result:

| State | What it says |
|---|---|
| never checked | "Never checked." |
| checking | "Checking…" |
| up to date | "0.4.0 is the latest build." — only ever after a successful check |
| published release is older | "The published release is 0.1.3. This build is 0.4.0." |
| available | The new version, the release notes, and "Download and install" |
| downloading | A progress bar, and the bytes so far |
| ready | "Ready to install" and "Install" |
| installing | Handed to Android's installer |
| failed | The reason: no network, GitHub is down, the rate limit, the signature did not match, no build for this device |
| not from here | "This build was installed from the Play Store; updates come from there." |

**At startup:** one check, at most once every 24 hours, silently. If there
is an update it says so in a toast. If there is not, it says nothing at all
— a launcher that nags about updates is a launcher people turn off.

### 7.9 The seam for Play

```dart
abstract interface class UpdateInstaller {
  Future<InstallOutcome> install(File apk, {required String version});
}
```

`SideloadInstaller` is the implementation for a GitHub-distributed build.
A `PlayInstaller` would implement the same interface using the Play API.
Nothing above this line changes when that happens.

## 8. The release process, which this feature depends on

The updater is only as good as what is published. Three changes come with it:

1. **`tool/publish_release.sh`** — builds, verifies and uploads the assets
   under the canonical names in 7.2, writes `SHA256SUMS`, and publishes a
   **stable** release (not a pre-release) so `/releases` has something
   current in it. It refuses to publish if `tool/verify_permissions.sh`
   fails, so a release cannot ship the wrong permission set.
2. **The README's download table is corrected** to the files that actually
   exist, and the false claim that the published APKs are release-signed is
   corrected with the one-time reinstall instruction.
3. **`docs/STATUS.md` is corrected** where it says ADB is offline.

## 9. Testing

| What | How |
|---|---|
| Feed parsing | A captured real GitHub payload, in a unit test |
| Version comparison | `0.4.0` > `0.3.10`, `0.3.0` == `0.3.0`, `0.4.0-rc2` is a pre-release of `0.4.0`, garbage is not newer |
| Asset selection | The applicationId × ABI matrix, including "no asset for this device" and the `.perf` variant |
| State machine | Every transition, and specifically that a failed check produces *failed*, never *up to date*, and that a published release older than the build produces its own state |
| The Settings section | A widget test per state, checking the wording is honest |
| Signature verification | **On the T20, for real:** build a release-key-signed APK, uninstall the debug-signed one, install, publish a test release, let the app find it, download, verify, install, and confirm the installed package is the new one |
| The permissions work already shipped | The same device pass: the microphone dialog, the calendar card, the countdown, the Settings sections |

## 10. Risks

| Risk | What happens |
|---|---|
| Play rejects `REQUEST_INSTALL_PACKAGES` | The seam in 7.9 is the answer; the app already refuses to sideload over a Play install |
| The release key is lost | Updates stop for everyone. Already true today, and the README says so; the updater only makes it final. The keystore is on the build machine and backed up off it — the backup's existence gets checked, not assumed |
| The one-time reinstall confuses people | The README says so, in the download section, before the first release-key-signed build ships |
| GitHub is down or rate-limits | The check fails and says so. The launcher is unaffected — it is a network call in the corner, not a dependency of the home screen |
| The user does not grant "install unknown apps" | The app says what it needs and opens the right settings screen. It never installs anything without that grant |
| A release is published with no asset for a device | "There is no build for this device yet" |

## 11. Left for the builder

- `lib/src/services/update_service.dart` — the feed, the comparison, the
  state machine.
- `lib/src/services/update_feed.dart` — the GitHub payload shape and the
  parsing, separated so it can be tested without a network.
- `lib/src/services/update_installer.dart` — the installer interface and the
  sideload implementation.
- `lib/src/widgets/update_section.dart` — the Settings section, and the
  startup toast.
- Native: `appInfo` (version, package, ABI, installer), `verifyUpdate` (the
  three checks), `installUpdate`, `canInstallPackages`,
  `openInstallPermission`.
- Manifest: `REQUEST_INSTALL_PACKAGES`, the `FileProvider`, its paths XML.
- `tool/publish_release.sh` — publish the assets, so the release and the
  updater cannot disagree about what exists.
- Tests: as tabled in section 9.
- Docs: `docs/STATUS.md` (built / verified / not verified), `docs/BUILDS.md`,
  the README's download section and its signing claim, and the licence note
  that a fork must keep the BSD notice.

## 12. What this does not settle

- Whether the startup check should exist at all on a fleet build, where the
  server would push updates instead.
- What the commercial licensing looks like. That is the other half of the
  money question and it is not this project's problem yet.
