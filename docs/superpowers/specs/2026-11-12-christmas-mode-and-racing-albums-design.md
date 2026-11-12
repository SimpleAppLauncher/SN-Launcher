# Christmas mode and racing photo albums — design

Date: 2026-11-12
Status: draft, awaiting owner approval
Author: OpenCode

## Intent

SN-Launcher is a wall display. Right now the background is nature photography and
the colour of the screen is a time-of-day system. The owner asked for two
additions, in both the reduced and the ef build:

1. **Christmas mode** — a seasonal look. The owner chose "palette + snow
   only": a festive palette and falling snow, not a winter photo album.
2. **A background picker** whose second option is cars, and mostly racing cars
   — F1, rally, WEC, Le Mans — and whose cars mode carries a sub-option for
   **Fernando Alonso**. The Alonso album spans his whole career, is a
   deliberate 50/50 mix of the car with him in it and him as the subject, and
   puts his Renault years and his 2005/06 championship at the centre. The
   owner also chose "both" for the pictures: one bundled hero image in the app,
   the rest fetched at runtime.

## Goals

- **G1** Settings gains a **Background** section: `Landscape` / `Cars`, and
  when `Cars` is selected a sub-row appears with `Any racer` /
  `Fernando Alonso`.
- **G2** Settings gains a **Christmas** section: Christmas mode on/off, falling
  snow on/off, and an automatic 1 Dec – 6 Jan window.
- **G3** Each new album ships one bundled hero image so the first launch of
  that album shows a car, not the old landscape or a blank.
- **G4** Every photo keeps its licence and author on screen and in
  `assets/photo/ATTRIBUTION.md`. No photo whose licence the app's own filter
  refuses may reach a device.
- **G5** The reduced build gets the same Background and Christmas sections as
  the ef build.
- **G6** Today's landscape behaviour does not change for anyone who does not
  touch the new settings.
  - **Amended 2026-11-12 after the builder check.** The plan includes fixing a
    real bug in the discovery filter (Commons now appends a tracking query
    string to every image URL, and the extension check rejected all of them),
    so landscape discovery starts returning photographs again instead of
    silently returning nothing. That is a behaviour change, and it is the
    change the flag was always supposed to make. The hand-checked pool is
    untouched and stays the fallback.

## Non-goals

- Not a photo editor, not user-imported folders, not a download manager.
- Not a video or animated background.
- Not a new photo source: the pictures still come from Wikimedia Commons and
  still have to pass the app's licence gate.

## Anti-goals

- No Christmas *photo* album — the owner chose palette + snow.
- No "pixel accurate" or "verified on device" claims for anything in here.
- No share-alike / NC / ND photograph may enter a pool, even by accident.

---

## Approaches considered

### How the background choice is modelled

**1. Albums inside `PhotoFrameService` (chosen).** A `PhotoAlbum` enum
(`landscape`, `racing`, `alonso`); each album owns a curated pool of Commons
titles, a bundled hero asset, and its own shape rules. The service gains an
`album` field; Settings writes the choice into the settings store.
*Pro:* one rotation engine, one licence gate, one cache, one credit path; a new
album is one table and one asset. *Con:* album selection becomes a service-level
concern, so the service has to react to a settings change.

**2. Cars as extra `NestTheme` values** (`NestTheme.racing`, `NestTheme.alonso`).
*Pro:* free ride on the existing theme picker and the schedule windows.
*Con:* it conflates "which colours" with "which pictures". A photo album is
not a palette. The theme schedule would rotate pictures by time of day, and the
digest page's Theme card would offer a choice that changes nothing about
colour. Rejected.

**3. A second `RacingPhotoService`.**
*Pro:* zero risk to the landscape path. *Con:* it duplicates the licence gate,
the cache, the sidecar writer, the rotation timer and the credit loader — the
duplication is exactly where an unlawful photograph would slip through later.
Rejected.

### How Christmas mode is modelled

**1. A mode flag + palette override + snow overlay (chosen).** `christmasMode`,
`snowEnabled` and `christmasAuto` in the settings store;
`ShellController._recomputePalette` returns the Christmas palette while the
mode is live; a `SnowOverlay` widget paints above the background and below the
clock.
*Pro:* "Christmas mode" is literally what the owner asked for, and it composes
with the existing theme system instead of competing with it. *Con:* while
Christmas mode is on, the user's theme schedule is suspended — the Settings
copy has to say so.

**2. `NestTheme.christmas` as a seventh theme chip.**
*Pro:* appears in the existing picker and the schedule for free. *Con:* picking
a "Christmas" theme would not snow, so the picker would offer a Christmas look
that silently omits the snow. Rejected.

**3. Winter photo album + seasonal palette.** Rejected by the owner.

### Where the pictures come from

**1. Curated per-album pools, fetched live by exact title (chosen).** The
current landscape pool works this way and works well: a hand-checked list of
Commons file titles, fetched at runtime through the licence gate, with the
author's name rendered next to the album title. The same mechanism, three
times over.
*Con:* the lists are hand-maintained, so `tool/verify_photo_pool.py` has to
check all of them, not just the landscape one.

**2. Bundle everything.** *Pro:* works offline. *Con:* ~45 photos × ~400 KB is
roughly 18 MB added to an APK and to a 25 MB macOS bundle. Rejected.

**3. Pure Commons search, no curated list.** *Pro:* no maintenance.
*Con:* on the measured acceptance rate (licence-clean, ≥1600 px, correctly
shaped) a 50-result search yields 4–8 usable files, and search results are not
vetted for whether the file is actually a racing car. Rejected.

---

## Design

### 1. Data model — `lib/src/services/photo_album.dart`

```dart
enum PhotoAlbum {
  landscape('Landscape'),
  racing('Racing cars'),
  alonso('Fernando Alonso');
}
```

Each value exposes:

| member | landscape | racing | alonso |
|---|---|---|---|
| `label` | "Landscape" | "Racing cars" | "Fernando Alonso" |
| `heroAsset` | `assets/photo/landscape.jpg` | `assets/photo/racing.jpg` | `assets/photo/alonso.jpg` |
| `heroCredit` | `assets/photo/landscape.json` | `assets/photo/racing.json` | `assets/photo/alonso.json` |
| `pool` | today's list | ~42 racing titles | see below |
| `minAspect` / `maxAspect` | 0.9 / 2.6 | 0.9 / 2.6 | 0.9 / 2.6 |
| `discoveryCategories` | today's 5 | F1 / WRC / Le Mans / WEC categories | F1-driver categories |

The Alonso album keeps **two** pools, `poolCar` (him in the car) and
`poolSubject` (him as the subject), and the picker alternates between them.
That is how the owner's "50 % about the car itself and he's in it and 50 %
about him mainly the subject" becomes a rule in code instead of a hope.

### 2. `PhotoFrameService` changes

- The service gains `PhotoAlbum album` (default `landscape`), backed by
  `SettingKeys.photoAlbum`.
- Pool, aspect bounds and discovery categories become album-driven.
- Changing album clears the current file and credit so the new album's bundled
  hero shows at once, instead of the previous album's photo staying on screen.
- **Bug fix (found by probing the live API, not by reading the code):**
  `candidateFromApiPage` rejects a candidate unless `info['url']` ends with
  `.jpg`/`.jpeg`/`.png`. Commons appends
  `?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=original`
  to `imageinfo.url`, so **every** discovered photograph is currently rejected
  and discovery always returns zero candidates. The curated-pool path is
  unaffected because it reads `thumburl` and never checks the extension.
  Fix: strip the query string before the extension test.

### 3. Bundled assets

| file | source | author | licence |
|---|---|---|---|
| `assets/photo/racing.jpg` | `Renault R25 2005 United States GP (19887965).jpg` | Ryosuke Yagi | CC BY 2.0 |
| `assets/photo/alonso.jpg` | `Fernando Alonso 2005 China.jpg` | Tinou Bao | CC BY 2.0 |

Each gets a sidecar JSON in the same shape as `landscape.json` (title, author,
licence, licenceUrl, sourceUrl). `PhotoCredit.preload()` currently loads one
JSON file; it becomes a map keyed by album so each album's hero credit is
available before `runApp`.

`assets/photo/ATTRIBUTION.md` gains a row per new asset and a note that the
author's name renders on screen next to the album title.

The pool titles themselves are attributed at fetch time — the credit comes from
the Commons `extmetadata`, and the author's name is drawn on screen beside the
album title — so the on-screen attribution is the real licence obligation, not
a courtesy.

### 4. Christmas mode

**Palette.** `AmbientPalette.christmas`: midnight blue into deep pine,
`Brightness.dark`, `isNight: true`, warm white ink. It is a night palette
because a wall display at 2am in December should not glow white.

**Mode plumbing.** Three settings keys: `christmasMode`, `snowEnabled`,
`christmasAuto`. `ShellController` exposes `christmasActive` — true when
`christmasMode` is on, or when `christmasAuto` is on and today falls between
1 Dec and 6 Jan inclusive. `_recomputePalette` returns the Christmas palette
when `christmasActive`; otherwise the existing time-of-day behaviour is
untouched.

**Snow.** `SnowOverlay` — one `CustomPainter`, ~120 flakes, each with a
position, a fall speed, a drift and a radius. It sits above the ambient
background and the photo, below the clock, so the snow falls in front of the
picture and behind the text. `NestShell.animateDecorations == false` (the
test flag) freezes it into a static arrangement so tests are deterministic.

### 5. Settings UI

Two new sections in `lib/src/widgets/settings_page.dart`, in this order:
**Appearance**, **Background**, **Christmas**, **Display**, **Assistant**.

**Background**

```
Background
  [ Landscape ]  [ Cars ]

Cars focus          (row appears only when "Cars" is selected)
  [ Any racer ]  [ Fernando Alonso ]
```

The stored value is one of `landscape` / `racing` / `alonso`; the two rows are
one setting seen from two angles.

**Christmas**

```
Christmas mode          [ on/off ]
Falling snow            [ on/off ]   (disabled while the mode is off)
Automatic 1 Dec – 6 Jan [ on/off ]
```

One line of copy under the section: "While Christmas mode is on, the theme
schedule is paused."

Neither section is behind a feature flag: the owner asked for both in both
builds.

### 6. Feature flags

- `assets/features.json`: `themePicker` → `true`, so the reduced build's digest
  page shows its Theme card too.
- `assets/features.ef.json`: unchanged.
- No new flag is introduced for Background or Christmas.

### 7. Pools

Every title below was checked live against the Commons API: the file exists,
its licence is public domain / CC0 / CC BY 2.0 / 3.0 / 4.0, and it is at least
1600 px wide. Share-alike, NC and ND files were dropped even when they were a
better photograph — for example `Alonso (Renault) qualifying at USGP 2005.jpg`
and `2005 British GP.jpg` are both CC BY-SA and are therefore **not** used.

**Racing — F1 / Renault** (Renault R25 2005 United States GP · 2005 Renault
R25 · 2005-03-04 Motorshow Geneva 063.JPG · 2005 F1 Champion · Renault R25
Display Car · First corner 2005 Turkish Grand Prix · GPTurkey05 start ·
Lineup of Team Renault F1 Cars · 1990's Classic Renault Team F1 Car ·
Renault R25 V6 Turbo Baccara (1994) · Renault R24/R23B museum shots)

**Racing — Le Mans / WEC** (Porsche 919 Hybrid ×5 · No. 2 Porsche 919 Hybrid ·
Audi-R18-TDI-2011 · Audi R18 TDI Winning Car · Audi Sport Team Joest's Audi
R18 TDI ×2 · No. 8 Audi R18 (2016) · 2018 Toyota Gazoo Racing's Toyota TS050
Hydrid · Toyota TS050 Hybrid No. 8 · Peugeot 908 ×3 · Peugeot 908 Le Mans
2011 third overall · 2023 24 Hours of Le Mans ×4)

**Racing — rally** (2005 Citroen Xsara WRC ×3 · Xsara WRC.JPG · Citroen Xsara
VTS Sport ×2 · BMW M3 Rally Coupé (E30, 1988) ×2 · Lancia Stratos HF Group 4
Rally ×2 · Lancia Stratos HF Rally · Lancia Stratos ×3 · Ford RS200 ×3 ·
1984 Ford RS200 Rally · Ford Fiesta RS WRC 2011 ×2 · Hyundai Accent WRC ·
Peugeot 206 WRC · Alpine Renault)

**Alonso — in the car** (Fernando Alonso 2005 China · Renault R28 Fernando
Alonso · Renault Pit Box, Imola 2005 · McLarens 2005 San Marino · the 2006
United States GP set ×5 · Renault duo 2006 United States GP · F1 - Mclaren
Honda - Fernando Alonso · Fernando Alonso - McLaren ×6 · McLaren-Honda MP4-31
2016 Silverstone · Fernando Alonso 2016 British Grand Prix · Belgian GP -
McLaren Honda · Fernando Alonso 2007 Britain · Ferrari F1 - Fernando Alonso ·
Fernando Alonso - Ferrari F138 · Ferrari F2013 ×3 · 2012 Italian GP - Alonso
on pit · 2012 Italian GP - Alonso pit · 2012 Japan GP - Alonso car · Fernando
Alonso on three wheels during 2009 Hungarian Grand Prix · Button + Alonso
Malaysian GP 2010 · Fernando Alonso 2009 Belgium · Fernando Alonso 2009
Singapore · Toyota TS050 Hybrid driven by Fernando Alonso (the 2023 Le Mans
win) · Toyota TS050 Hybrid No. 8 Fernando Alonso · FIA F1 Imola 2025 No. 14
Alonso · Fernando Alonso 2025 Italian Grand Prix qualifying)

**Alonso — as the subject** (2012 Italian GP - Champagne · 2012 Italian GP -
drivers press conference · 2012 Italian GP - Alonso cameraman · Alonso Barca
2012 · Fernando Alonso - Inggris 2012 · Ferrari Alonso and McLaren Hamilton
Barcelona 2012 · Fernando Alonso and Jacques Villeneuve 2006 Indianapolis ·
Giancarlo Fisichella and Fernando Alonso 2006 Indianapolis ×2 · Michael
Schumacher and Fernando Alonso 2006 United States GP · Fernando Alonso and
Jarno Trulli 2006 Indianapolis · 2019 Indianapolis 500 Fernando Alonso ×2 ·
Fernando Alonso (35461870753))

**Portrait-format photographs are excluded from the Alonso album on purpose.**
The wall display crops to 16:9 with `BoxFit.cover`, and a cropped portrait of a
person's face is worse than no photograph at all. The championship moments
(2005 title year at Imola, 2006 title clinched at the United States Grand Prix)
are available in landscape format and are in the pool.

### 8. Tests

| file | what it proves |
|---|---|
| `test/photo_album_test.dart` | every album has a non-empty pool and a hero asset; every pool title is a `.jpg`/`.jpeg`/`.png`; the Alonso album's two pools are both non-empty and roughly balanced; per-album aspect bounds are sane |
| `test/christmas_mode_test.dart` | the Christmas palette passes the app's own readability check; the auto window is right on 30 Nov 23:59, 1 Dec 00:00, 6 Jan 23:59 and 7 Jan 00:00; the snow overlay paints without overflow at all 11 aspect shapes |
| `test/aspect_ratio_test.dart` (extended) | the new Background and Christmas settings sections open without overflow at 1:1, 4:3, 3:4 and 9:16 |
| `test/photo_frame_service_test.dart` (extended) | `candidateFromApiPage` accepts a real Commons payload whose `url` carries the `?utm_source=…` query string, and still rejects a share-alike licence |

### 9. Documentation

`README.md`, `INFO.md`, `docs/STATUS.md` and `assets/photo/ATTRIBUTION.md` are
updated in the same change, and state only what has actually been verified: the
photos are curated from Wikimedia Commons and carry their licences; the
Christmas mode is a palette and a snow animation; nothing in here has been run
on a physical device unless it has.

## Verification plan

1. `flutter analyze` — clean.
2. `flutter test` — the existing 303 tests plus the new ones, all green.
3. `tool/verify_photo_pool.py` extended to all three pools: for every title,
   live-check that the file exists, that its licence is redistributable, and
   that a thumbnail can be fetched. Non-zero exit on failure, so it can run in
   CI.
4. Screenshots at 16:9, 1:1 and 4:3 of: the Background section, the Christmas
   section, Christmas mode running with snow, the racing album and the Alonso
   album.
5. A release build of both variants (`flutter build apk --release` and the
   ef variant) to confirm the new assets ship and the APK did not grow out of
   hand.

**Not** claimed: anything about how this looks on the owner's SM-X110 or T20
until he runs it and says so.

## Risks

| risk | mitigation |
|---|---|
| A Commons file is renamed or its licence changes | the licence is re-checked at fetch time, a failed file is skipped, and `tool/verify_photo_pool.py` catches it in CI |
| The 45 extra pool entries drift out of date | the verifier script, run on every change to the pools |
| Snow costs frame rate on a weak GPU | one `CustomPainter`, one layer, no per-flake widgets, and it is switchable off |
| The bundled heroes add ~700 KB | both are re-encoded to ~1920 px wide, JPEG quality 80 |
