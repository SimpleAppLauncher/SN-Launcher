# SN-Launcher

**v0.1.1** · [Download](#download) · [INFO.md](INFO.md) for the technical record

A Google Nest Hub style launcher for **Android**, for putting an old tablet on
a wall and having it look like a smart display.

<p align="center">
  <img src="docs/shots/home.jpg" width="49%" alt="The home screen: a photograph, the clock, the weather">
  <img src="docs/shots/sheet.jpg" width="49%" alt="The launcher sheet, with the app row and quick settings">
</p>
<p align="center">
  <img src="docs/shots/digest.jpg" width="80%" alt="Page two: the calendar, weather, music, photos and theme">
</p>

---

## Download

Grab it from **[releases](../../releases/latest)**.

| File | Size | For |
|---|---|---|
| **`SN-Launcher-0.1.1.apk`** | 32 MB | **Start here.** Works on any phone or tablet from roughly 2014 on. |
| `SN-Launcher-0.1.1-arm64.apk` | 18 MB | Smaller. Nearly all modern tablets. |
| `SN-Launcher-0.1.1-armv7.apk` | 16 MB | Smaller. Older budget tablets. |
| `SN-Launcher-0.1.1-x86_64.apk` | 20 MB | Chromebooks, emulators. |
| `SN-Launcher-0.1.1-beta-arm64.apk` | 18 MB | The beta. Everything on. |

Copy the `.apk` to the device and tap it, allowing **Install unknown apps** for
whatever opened it. Or over USB:

```bash
adb install -r SN-Launcher-0.1.1.apk
```

Then set it as your home screen.

### Two things to know first

**It is signed with a debug key.** Android allows sideloading a debug-signed
APK, so it installs fine — but there is no release keystore in the repository,
and the key that signed this file lives on one machine. If a later build is
signed with a different key, Android refuses to install over the top and you
have to uninstall first, losing your settings. **Expect to reinstall rather
than upgrade.**

**It wants to be the home screen.** Set it as default launcher after
installing.

---

## What you get

**The shipping build** is a launcher: the Nest-style clock and photo, the app
row and the full app grid, brightness and volume, and a settings page.

Page two holds the two things worth glancing at: a **calendar** that shows the
date and what's on today, and a **to-do list** you can add to, tick off and
delete. The to-do list is saved on the device, so it is still there tomorrow.

**The beta** additionally has the voice assistant, a music player, rotating
photographs, live weather, and the "Sun" theme that follows the time of day. It
is a *separate app* with its own icon, so you can install both and compare.

What is in each build is decided by a JSON file, not by code — see
[`docs/BUILDS.md`](docs/BUILDS.md).

---

## What actually works

Run on real hardware: a **Samsung Galaxy Tab A7 Lite** (Android 15, MediaTek
MT6789, 800x1340) and a **Nokia T20** (Android 13, Unisoc T610, 2000x1200).

| | |
| --- | --- |
| The clock, date and weather | ✓ |
| The photo frame, rotating every 10 min | ✓ |
| The app row and the six-column grid | ✓ |
| A calendar reading real events, with the date | ✓ |
| A to-do list you can add to, tick off and delete | ✓ |
| The quick-settings row — every button does something | ✓ |
| Five themes | ✓ |
| Settings | ✓ |
| Cold start | **362–405 ms** on the Tab A7 Lite |

**Not yet run on any device: the voice assistant and the music player.** Both
are in the beta build. They compile and their tests pass, which is not the same
thing as working — the microphone path has never heard a microphone.

---

## Known rough edges

- **Held in portrait on a portrait-native tablet the layout looks small.** The
  manifest pins `sensorLandscape`, so turn the tablet sideways.
- **The quick-settings row has seven buttons and the spacing is measured
  against a photograph of a real Nest Hub Max — but two of the seven are not
  the same controls the real device shows.**
- **"Pixel-accurate" was an overstatement.** Measured against a reference
  photograph: the clock block and the badge pitch. Eyeballed: everything else.
  The full accounting is in [INFO.md](INFO.md) §1.
- **The navigation is a page carousel; the real device uses layers.** Also in
  INFO.md §1.

---

## Credits

Written by **Giathinh1234**, and built with **[OpenCode](https://opencode.ai)** —
not Claude Code, and no part of it came from Anthropic. There is no
`Co-Authored-By: Claude` trailer anywhere in the history, and GitHub's
contributor list for this repository contains exactly one account. The
OpenCode references in [`docs/MODELS.md`](docs/MODELS.md) and
[`tool/chatlog.py`](tool/chatlog.py) are deliberate, so the tool is
unambiguous without anyone having to guess.

Built in Flutter — the same stack Google used for the real Nest Hub, which is
what makes matching it realistic at all.

* **Google Sans** (SIL OFL 1.1), bundled genuinely rather than approximated.
  This is the single biggest reason the clock reads as "Google".
* **Material Symbols** (Apache 2.0), subsetted to the 172 glyphs in use.
* **Poppins** (SIL OFL 1.1) for the thinner "Timeless Light" clock face.
* The bundled photograph — *Cub Lake at dawn* by **Debra Miller** — is public
  domain, and her name is rendered on screen because the licence asks for it.
  The rotating pool is public domain, CC0 or plain CC-BY only.
* Brand marks (Spotify, Netflix, Pandora, YouTube) are drawn as paths.

---

## Build it yourself

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

**[INFO.md](INFO.md)** has everything else: how the pixel measurements were
taken and what is *not* measured, the rendering architecture, the photo
licensing pipeline, the Gradle quirks, the signing situation, and the honest
list of known gaps.

Two documents govern how it gets built, both committed so they survive context
compression: **[AGENTS.md](AGENTS.md)** for the agent's working rules, and
**[docs/HOW-TO-USE-THIS.txt](docs/HOW-TO-USE-THIS.txt)** for the human side —
the lessons from this project that actually cost something.
