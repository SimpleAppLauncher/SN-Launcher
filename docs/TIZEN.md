# SN-Launcher on the Samsung TV

**Status: built, signed for this TV's DUID, never installed and never run.**

The `.tpk` at `build/tizen/tpk/com.giathinh.snlauncher.tv-1.0.0.tpk` was built
on 24 Oct 2026 and is signed with a Samsung-issued author certificate and a
Samsung-issued distributor certificate whose device-id extension names the TV.
That is the certificate work that was blocking installation, and it is done.

The TV side is still blocking: sdb cannot open a device. `192.168.1.11:26101`
accepts a TCP connection and then resets it, and the TV's API reports
`PowerState: standby`. This is the documented behaviour of a TV whose
developer-mode setting has not survived a reboot, or whose sdb daemon is not
running. Nothing in this repository can fix that; the TV has to be power-cycled
with the remote in hand. See **Install** below.

Do not read this as "the TV build works". It means the package exists, the
signature chain was checked, and the next step is a physical one.

---

## The target

| | |
| --- | --- |
| TV | `QA55Q60CAKXXV` (2023 55" Q60C), `192.168.1.11` |
| DUID | `uuid:65f128ff-cd11-4d1a-aecf-491a2171d972` |
| Tizen package | `com.giathinh.snlauncher.tv` |
| Manifest | `api-version="6.0"`, `profile name="tv"` |
| Runner | .NET, `exec="Runner.dll"` |
| Privilege | `http://tizen.org/privilege/internet` |
| App type | native Flutter Tizen embedding, not the HTML fallback in `tv/` |

The TV's real Tizen version has not been read off the device. The manifest
targets 6.0 because the publicly installable TV rootstrap is 6.0; do not assume
the panel runs Tizen 10.

`tv/` is the hand-written HTML/JS fallback. It is not this build and is not
what the TPK installs.

## Two versions, one source

The TV is a **target**, not a third version. The package is built from the same
Dart source and the same `SN_FEATURES` switch as the tablets:

```bash
# reduced (ships)
flutter-tizen build tpk --device-profile tv --target-arch arm --release \
  -s snlauncher

# ef (everything on)
flutter-tizen build tpk --device-profile tv --target-arch arm --release \
  -s snlauncher --dart-define=SN_FEATURES=assets/features.ef.json
```

Both keep `homeControl: false`. The ef build needs the ef JSON; the reduced
build is the one that exists now.

## Building it on this machine

The SDK surgery below is local to this Mac and is not a supported Tizen Studio
install. It exists because the legacy package manager cannot resolve the
cross-GCC dependencies on Apple Silicon, and the TV rootstrap is not publicly
distributed.

What is installed:

- Tizen SDK 10.0 at `~/tizen-sdk`, with the **TV-SAMSUNG-Public 10.0.0**
  extension.
- `flutter-tizen` 3.47.5 / Flutter 3.47.5 / Dart 3.13.4 at `~/flutter-tizen`.
- The `iot-headed-6.0-device.core` rootstrap at
  `platforms/tizen-6.0/iot-headed/rootstraps/`.
- The `arm-linux-gnueabi-gcc-9.2` and `llvm-10` toolchains, with their SBI
  plugin XMLs under `tools/smart-build-interface/plugins/`.
- .NET SDK 8.0 at `~/.dotnet`, the Tizen .NET workload, and
  `tools/tizen-core/config.yaml` pointing `dotnet_cli_path` at it.
- Java 17 (arm64) used instead of the bundled x86_64 JDK 8. The bundled `jdk`
  is renamed `jdk.x86.bak`; restoring it will break this build under Rosetta.

On 25 Oct the SDK and its data moved to iCloud Drive. Two symlinks keep the
old, space-free paths working:

```
~/tizen-sdk      -> ~/Library/Mobile Documents/com~apple~CloudDocs/tizen-sdk
~/tizen-sdk-data -> ~/Library/Mobile Documents/com~apple~CloudDocs/tizen-sdk-data
```

`sdb` and `tizen` run through the symlinks. Without them, `tizen` fails because
the iCloud path contains spaces and its launcher script does not quote them.

The build command:

```bash
export PATH="$HOME/.dotnet:$HOME/tizen-sdk/tools:$HOME/tizen-sdk/tools/ide/bin:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"
cd ~/nestlaunch
~/flutter-tizen/bin/flutter-tizen build tpk \
  --device-profile tv --target-arch arm --release -s snlauncher
```

The result is `build/tizen/tpk/com.giathinh.snlauncher.tv-1.0.0.tpk`.

If the build fails with a missing `impellerc` or `MaterialIcons-Regular.otf`
under `~/flutter-tizen/flutter/bin/cache`, the Flutter host artifacts were
cleaned when the SDK moved. Restore them once:

```bash
~/flutter-tizen/flutter/bin/flutter precache --universal
```

The TPK was rebuilt on 25 Oct 2026 through the symlinked SDK after that
precache, and the signature was checked again.

## Certificates

The TV will not install a TPK signed with the bundled public distributor
certificate. The distributor must name the TV's DUID.

Created on 24 Oct 2026:

- Samsung author: `CN=Giathinh1234`, issued by **Samsung VD Author CA**.
- Samsung distributor: `CN=TizenSDK`, issued by **VD DEVELOPER Public CA
  Class**, with
  `URI:URN:tizen:deviceid=UUID:65F128FF-CD11-4D1A-AECF-491A2171D972`.
- Signing profile `snlauncher`, active. `tizen security-profiles list` shows it.

Files live under
`~/tizen-sdk-data/keystore/samsung/snlauncher/` (`author.p12`,
`distributor.p12`, and their password envelopes). They are **not** in this
repository and must never be committed. The password is kept by the macOS
Keychain, not in the tree.

Regenerating the certificates needs a Samsung account login in a browser. The
commands (without the password) are:

```bash
node ~/Downloads/dist/bin/tizen-sdk.js certificate-manager \
  --action generate-samsung-author --profile-name snlauncher \
  --identity "Giathinh1234" --organization "SN" --country VN

node ~/Downloads/dist/bin/tizen-sdk.js certificate-manager \
  --action generate-samsung-distributor --profile-name snlauncher \
  --duid-list uuid:65f128ff-cd11-4d1a-aecf-491a2171d972 --privilege Public

node ~/Downloads/dist/bin/tizen-sdk.js certificate-manager \
  --action create-samsung-profile --profile-name snlauncher --active
```

## Install

Prerequisite, on the TV:

1. Turn the TV **on**. sdb does not connect while the TV is in standby.
2. Smart Hub → Apps → App Settings → enter `12345` on the remote.
3. Developer mode **On**; Host PC IP `192.168.1.123` (this Mac).
4. **Reboot the TV.** The developer-mode setting only starts the sdb daemon
   after a reboot. If port 26101 keeps resetting, unplug the TV for 30 seconds
   and plug it back in.
5. Run:

```bash
cd ~/nestlaunch
tool/tv_install.sh
```

The first connection should show an **Allow** prompt on the TV. Accept it.
The script installs, launches, and tries to pull a screenshot to
`build/tizen/snlauncher-tv.png`.

If it still fails, check the TV API:

```bash
curl -s http://192.168.1.11:8001/api/v2/ | grep -o '"PowerState":"[^"]*"'
```

`standby` means the TV is off. `on` with a resetting port 26101 means the
daemon is not up and the TV needs the power cycle.

## What is not verified

Everything that requires looking at the TV:

- 16:9 layout at 1920×1080.
- D-pad focus and traversal. The current shell is the tablet/drag shell; its
  root `Focus` claims Left/Right for page changes, so horizontal traversal
  inside a page is not there yet. This is the next code change, and it should
  be made with the TV in front of us, not guessed at.
- ef/reduced gating on the TV, including `homeControl: false`.
- `webview_flutter_tizen` navigation and JavaScript. It is not an endorsed
  implementation of `webview_flutter`.
- The NCS feed. The mock is at `http://192.168.1.123:8737`; the TV build has
  not pointed at a real server.
- Weather place name and photo.
- Frame timing and idle cost on the TV.

The Android and desktop status is in `docs/STATUS.md`. The TV does not change
the two-version rule: ef and reduced, one source, only the feature JSON differs.
