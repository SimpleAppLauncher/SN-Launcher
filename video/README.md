# SN-Launcher promo

A 44-second, silent 1920×1080 promo built with Remotion. Bright, clean motion
graphics on a paper background; all screenshots and the short screen recording
are real captures from a Nokia T20 running Android 13. The app is labelled
**BETA** throughout.

## Run it

```bash
npm install
npm run start      # Remotion Studio
npm run render     # video/out/sn-launcher.mp4
npm run still      # video/out/cover.png
```

The rendered files in `out/` are ignored. The tracked copy of the final render is
`sn-launcher.mp4`, with `poster.jpg` as its poster frame.

## What is on screen

- `public/home.jpg` — real home capture: live photo, clock, weather.
- `public/home-now-playing.jpg` — real home capture with the now-playing strip
  showing Rick Astley in YouTube.
- `public/stock.jpg` — the stock Android 13 launcher on the same tablet, used for
  the side-by-side comparison.
- `public/now-playing-strip.jpg` — a crop of the real now-playing strip, used as
  a detail card.
- `public/demo.mp4` — an 18-second device capture used for the dock/drawer scene.

No image is used as a page background. The background is a solid paper colour
with a faint dot grid and soft colour fields; photographs and screenshots are
presented only inside rounded cards.

## Structure

- `src/Video.tsx` — scenes, copy, timing and motion.
- `src/Root.tsx` — the 1920×1080, 30 fps, 1320-frame composition (44 s).
- `remotion.config.ts` — JPEG frames, H.264 output settings.

## Scenes

1. **Intro** — wordmark, beta label, “A calmer Android home.”
2. **Home** — real home screen; live photo frame, real clock and weather.
3. **Dock** — real device capture of the dock, drawer and search; no mockups.
4. **Now playing** — real home screen with the top-right strip; transport
   controls are forwarded to the app that owns the music.
5. **Performance** — measured warm open (median of five launches) on the Nokia
   T20: 144 ms for SN-Launcher, 140 ms for the stock launcher, plus APK size,
   min SDK and tablet layout. The same tablet measured **3.3% of one core** for
   SN-Launcher idle over a 60 s screen-on sample, against **0.15%** for the
   stock launcher; the card labels this as the cost of the live animated home,
   not a performance win.
6. **Comparison** — stock launcher vs SN-Launcher with the concrete differences.
7. **Outro** — “A calmer Android home.”, beta label and repository URL.

The video has no audio track.
