# Store listing draft — SN-Launcher 0.3.0

This directory is a review packet, not a submitted Play Store listing. The
screenshots are existing real captures; the privacy and data-safety notes are
written against the code in this tree. Nothing here claims a capability the
build does not have.

## Listing

**App name:** SN-Launcher

**Short description (under 80 characters):**
A calm, Nest-style home screen for Android tablets.

**Full description:**

SN-Launcher turns an old Android tablet into a calm wall display: a large clock,
a rotating photograph, weather, a labelled app row, and a searchable drawer that
uses the apps actually installed on the device.

It is built for landscape tablets that stay on a wall or a stand. The shipping
build is deliberately small: launcher, settings, quick settings, calendar and
to-do. The separate **ef** build adds the experimental pages for people who want
to test them.

- Large clock and date, with optional seconds and 24-hour time.
- Rotating public-domain / CC0 / CC-BY photographs with on-screen credit.
- Weather page using Open-Meteo.
- Labelled dock and a searchable drawer of installed apps.
- Calendar and to-do pages.
- Five themes, including a time-of-day theme.
- Time-based theme windows while the Dynamic theme is selected.
- Optional Android now-playing strip and transport, after Notification access.
- Brightness and volume quick settings.

**Not in this release:** no TV/D-pad support, no remote-control server, no
voice assistant that is verified end to end, and no claim that the real
NCS-SMLauncher protocol is finished. Home control is compiled but disabled in
both builds because the tiles had nothing real behind them.

**Category:** Personalization (tablet)

**Contact:** https://github.com/SimpleAppLauncher/SN-Launcher/issues

## Build identity

- Version name: `0.3.0`
- Base version code: `9001`
- Per-ABI split codes: armeabi-v7a `10001`, arm64-v8a `11001`, x86_64 `13001`
- Reduced package: `dev.snlauncher.snlauncher`
- ef package: `dev.snlauncher.snlauncher.ef`
- Release certificate: `CN=SN-Launcher, OU=Android, O=SimpleAppLauncher, C=US`
- Certificate SHA-256:
  `94d75bcb19143281e16a98393b81f2467c3bd528632c696ffde8b3bdf4951804`

## Screenshot inventory

| File | Source | Caption |
|---|---|---|
| `screenshots/01-home.jpg` | `video/public/home.jpg` (real T20 capture, 2000×1200) | The home screen: photo, clock, weather and dock |
| `screenshots/02-now-playing.jpg` | `video/public/home-now-playing.jpg` (real T20 capture, 2000×1200) | The now-playing strip on the home screen |
| `screenshots/03-launcher-sheet.jpg` | `docs/shots/sheet.jpg` (900×537) | The launcher sheet and quick settings |
| `screenshots/04-digest.jpg` | `docs/shots/digest.jpg` (900×537) | Calendar, to-do, weather, music and theme |
| `screenshots/05-music.png` | `docs/shots/music.png` (1340×800) | The music page against the mock |

The 900×537 captures are older but real. Do not upscale them or replace them
with mockups. Capture a fresh 0.3.0 set on the T20 when ADB is available.

## Publishing status

- Built and signature-verified: reduced + ef, three ABIs each.
- Automated: `flutter analyze` clean; 287 tests pass, 1 skipped.
- Hardware: the exact 0.3.0 build was **not installed** in this pass because ADB
  was offline. Earlier T20 evidence covers now-playing, its transport and live
  track replacement; promo captures show the real dock/drawer and live photo.
- Still not done: store submission, the Play Console data-safety form, a fresh
  hardware smoke run for 0.3.0, and EF-only remote control.

See `privacy-policy.md` and `data-safety.md` beside this file.
